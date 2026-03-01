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

# --- Read configuration ---
gps_device=$(bashio::config 'gps_device' '')
update_ha_location=$(bashio::config 'update_ha_location')
location_update_interval=$(bashio::config 'location_update_interval' '60')
require_3d_fix=$(bashio::config 'require_3d_fix')
min_satellites=$(bashio::config 'min_satellites' '4')

# --- Device detection ---
if [ -z "${gps_device}" ]; then
    bashio::log.info "No GPS device configured, auto-detecting..."
    for candidate in /dev/ttyACM0 /dev/ttyUSB0 /dev/ttyAMA0 /dev/ttyS0; do
        if [ -e "${candidate}" ]; then
            gps_device="${candidate}"
            bashio::log.info "Auto-detected GPS device: ${gps_device}"
            break
        fi
    done
    if [ -z "${gps_device}" ]; then
        bashio::log.fatal "No GPS device found. Connect a USB GPS and configure gps_device or ensure it appears at /dev/ttyACM0, /dev/ttyUSB0, /dev/ttyAMA0, or /dev/ttyS0."
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

cleanup() {
    bashio::log.info "Shutting down gpsd addon..."
    [ -n "${LOOP_PID}" ] && kill "${LOOP_PID}" 2>/dev/null
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
gpsd -n -N -S 2947 -G "${gps_device}" &
GPSD_PID=$!

# Give gpsd a moment to bind its socket before clients connect
sleep 2

if ! kill -0 "${GPSD_PID}" 2>/dev/null; then
    bashio::log.fatal "gpsd failed to start!"
    exit 1
fi
bashio::log.info "gpsd started (PID: ${GPSD_PID})"

# --- HA location update loop ---
update_ha_location_loop() {
    local consecutive_misses=0
    local min_mode=2
    bashio::var.true "${require_3d_fix}" && min_mode=3

    bashio::log.info "Location update loop started (interval: ${location_update_interval}s, min_mode: ${min_mode}, min_satellites: ${min_satellites})"

    while true; do
        # Collect up to 30 JSON messages from gpsd, timeout 30s
        raw=$(gpspipe -w -n 30 -t 30 2>/dev/null || true)

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
            alt=$(echo "${fix}" | jq -r '.alt // empty')

            bashio::log.info "GPS fix: lat=${lat}, lon=${lon}${alt:+, alt=${alt}m}"

            payload="{\"latitude\": ${lat}, \"longitude\": ${lon}}"
            [ -n "${alt}" ] && payload="{\"latitude\": ${lat}, \"longitude\": ${lon}, \"elevation\": ${alt}}"

            response=$(curl -s -o /dev/null -w "%{http_code}" \
                -X POST \
                -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "${payload}" \
                "http://supervisor/core/api/services/homeassistant/set_location")

            if [ "${response}" = "200" ]; then
                bashio::log.debug "HA home zone updated successfully"
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

# --- Monitor gpsd ---
bashio::log.info "gpsd is running. Monitoring..."
wait "${GPSD_PID}"

bashio::log.warning "gpsd exited unexpectedly, shutting down..."
cleanup
