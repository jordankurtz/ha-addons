#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

# ==============================================================================
# gpsd Add-on for Home Assistant
# Exposes a USB GPS device over TCP port 2947 and optionally updates the HA
# home zone with the current GPS coordinates.
# ==============================================================================

declare gps_device
declare update_ha_location
declare location_update_interval
declare require_3d_fix
declare min_satellites
declare log_level

# --- Read configuration ---
log_level=$(bashio::config 'log_level' 'info')
bashio::log.level "${log_level}"

gps_device=$(bashio::config 'gps_device' '')
update_ha_location=$(bashio::config 'update_ha_location')
location_update_interval=$(bashio::config 'location_update_interval' '60')
require_3d_fix=$(bashio::config 'require_3d_fix')
min_satellites=$(bashio::config 'min_satellites' '4')

bashio::log.debug "Configuration: gps_device='${gps_device}' update_ha_location='${update_ha_location}' interval='${location_update_interval}' require_3d_fix='${require_3d_fix}' min_satellites='${min_satellites}'"

# --- Device detection ---
if [ -z "${gps_device}" ]; then
    bashio::log.info "No GPS device configured, auto-detecting..."
    for candidate in /dev/ttyACM* /dev/ttyUSB* /dev/ttyAMA*; do
        if [ -e "${candidate}" ]; then
            bashio::log.info "  ${candidate}: found"
            [ -z "${gps_device}" ] && gps_device="${candidate}"
        else
            bashio::log.info "  ${candidate}: not present"
        fi
    done
    [ -n "${gps_device}" ] && bashio::log.info "Using first detected device: ${gps_device}"
    if [ -z "${gps_device}" ]; then
        bashio::log.fatal "No GPS device found. Connect a USB GPS and configure gps_device or ensure it appears at /dev/ttyACM0, /dev/ttyUSB0, or /dev/ttyAMA0."
        exit 1
    fi
else
    if [ ! -e "${gps_device}" ]; then
        bashio::log.fatal "Configured GPS device '${gps_device}' not found."
        exit 1
    fi
    bashio::log.info "Using configured GPS device: ${gps_device}"
fi

# --- Graceful shutdown handler ---
GPSD_PID=""
LOOP_PID=""
UI_PID=""

cleanup() {
    bashio::log.info "Shutting down gpsd addon..."
    [ -n "${LOOP_PID}" ] && kill "${LOOP_PID}" 2>/dev/null
    [ -n "${UI_PID}" ]   && kill "${UI_PID}"   2>/dev/null
    [ -n "${GPSD_PID}" ] && kill "${GPSD_PID}" 2>/dev/null
    wait
    exit 0
}
trap cleanup SIGTERM SIGINT

# --- Start gpsd ---
# -n: keep polling device even with no clients (maintains warm fix)
# -N: run in foreground so we can track the PID
# -S 2947: listen on port 2947
# -G: listen on all interfaces (required for cross-addon access)
bashio::log.info "Starting gpsd on ${gps_device} (port 2947)..."
bashio::log.debug "gpsd command: gpsd -n -N -S 2947 -G ${gps_device}"
gpsd -n -N -S 2947 -G "${gps_device}" &
GPSD_PID=$!

# Give gpsd a moment to bind its socket
sleep 1

if ! kill -0 "${GPSD_PID}" 2>/dev/null; then
    bashio::log.fatal "gpsd failed to start!"
    exit 1
fi
bashio::log.info "gpsd started (PID: ${GPSD_PID})"

# Wait for gpsd to accept connections (up to 10 s) and log what we get.
# gpsd 3.27.x may take several seconds to bind the TCP socket after startup.
gpsd_diag=$(python3 -c "
import socket, sys, time, json

for attempt in range(10):
    try:
        s = socket.create_connection(('127.0.0.1', 2947), timeout=2)
        s.settimeout(5)
        # gpsd sends VERSION immediately on connect
        data = s.recv(4096).decode('utf-8', errors='replace').strip()
        s.close()
        print(f'CONNECTED after {attempt + 1}s — first response: {data[:200]}')
        sys.exit(0)
    except ConnectionRefusedError:
        print(f'attempt {attempt + 1}: connection refused', file=sys.stderr)
        time.sleep(1)
    except socket.timeout:
        print(f'CONNECTED after {attempt + 1}s — but no data received (socket timeout)')
        sys.exit(0)
    except OSError as e:
        print(f'attempt {attempt + 1}: {e}', file=sys.stderr)
        time.sleep(1)

print('FAILED — gpsd not accepting connections on 127.0.0.1:2947 after 10 attempts')
sys.exit(1)
" 2>&1)
bashio::log.info "gpsd socket check: ${gpsd_diag}"

# Verify the serial link is alive by checking the gpsd DEVICES response.
# gpsd emits a DEVICES message within the first few JSON frames — it lists every
# device it has successfully opened and the driver it detected. An empty device
# list or a missing 'activated' timestamp means the module isn't responding.
bashio::log.info "Verifying serial link to ${gps_device}..."
probe_output=$(timeout 15 gpsd_client --count 5 --timeout 10 2>/dev/null || true)
bashio::log.trace "gpspipe probe output: ${probe_output}"

device_info=$(echo "${probe_output}" \
    | jq -c --arg path "${gps_device}" \
        'select(.class=="DEVICES") | .devices[] | select(.path==$path)' \
    | head -1)

if [ -n "${device_info}" ]; then
    activated=$(echo "${device_info}" | jq -r '.activated // empty')
    driver=$(echo "${device_info}" | jq -r '.driver // "unknown"')
    if [ -n "${activated}" ]; then
        bashio::log.info "Serial link OK — driver: ${driver}, device: ${gps_device}"
    else
        bashio::log.warning "Device ${gps_device} found by gpsd but not yet activated (driver: ${driver}). Data may not be flowing yet."
    fi
else
    bashio::log.warning "gpsd did not report ${gps_device} as an active device. The module may not be responding — check the cable and that the device is a GPS receiver."
fi

# --- HA location update loop ---
update_ha_location_loop() {
    local consecutive_misses=0
    local min_mode=2
    bashio::var.true "${require_3d_fix}" && min_mode=3

    bashio::log.info "Location update loop started (interval: ${location_update_interval}s, min_mode: ${min_mode}, min_satellites: ${min_satellites})"

    while true; do
        bashio::log.debug "Polling gpsd for TPV message..."

        # Collect up to 30 JSON messages from gpsd, timeout 30s
        raw=$(timeout 35 gpsd_client --count 30 --timeout 30 2>/dev/null || true)
        bashio::log.trace "gpspipe raw output: ${raw}"

        # Find the last TPV message with a valid fix, sufficient mode, and coordinates
        fix=$(echo "${raw}" \
            | jq -c --argjson min_mode "${min_mode}" --argjson min_sats "${min_satellites}" \
                'select(.class=="TPV")
                 | select(.mode >= $min_mode)
                 | select(.lat != null and .lon != null)' \
            | tail -1)

        if [ -n "${fix}" ]; then
            consecutive_misses=0
            lat=$(echo "${fix}" | jq -r '.lat')
            lon=$(echo "${fix}" | jq -r '.lon')
            alt=$(echo "${fix}" | jq -r 'if .alt then (.alt | round) else empty end')
            mode=$(echo "${fix}" | jq -r '.mode')

            bashio::log.info "GPS fix: lat=${lat}, lon=${lon}${alt:+, alt=${alt}m}"
            bashio::log.debug "Fix details: mode=${mode}, raw=${fix}"

            payload="{\"latitude\": ${lat}, \"longitude\": ${lon}}"
            [ -n "${alt}" ] && payload="{\"latitude\": ${lat}, \"longitude\": ${lon}, \"elevation\": ${alt}}"

            bashio::log.debug "Posting location to HA: ${payload}"
            response=$(curl -s -o /dev/null -w "%{http_code}" \
                -X POST \
                -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "${payload}" \
                "http://supervisor/core/api/services/homeassistant/set_location")

            if [ "${response}" = "200" ]; then
                bashio::log.debug "HA home zone updated successfully (HTTP ${response})"
            else
                bashio::log.warning "Failed to update HA home zone (HTTP ${response})"
            fi
        else
            consecutive_misses=$((consecutive_misses + 1))
            bashio::log.debug "No valid GPS fix (miss #${consecutive_misses})"
            if [ "${consecutive_misses}" -ge 10 ]; then
                bashio::log.warning "No valid GPS fix for ${consecutive_misses} consecutive attempts. Check antenna placement and satellite visibility."
            fi
        fi

        sleep "${location_update_interval}"
    done
}

if bashio::var.true "${update_ha_location}"; then
    update_ha_location_loop &
    LOOP_PID=$!
else
    bashio::log.info "HA location updates disabled."
fi

# --- Start status UI ---
bashio::log.info "Starting GPS status UI on port 8080..."
python3 /usr/share/gpsd-ui/server.py &
UI_PID=$!

# --- Monitor gpsd ---
bashio::log.info "gpsd is running. Monitoring..."
wait "${GPSD_PID}"

bashio::log.warning "gpsd exited unexpectedly, shutting down..."
cleanup
