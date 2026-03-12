#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

# ==============================================================================
# Ultrafeeder Add-on for Home Assistant
# Starts readsb, tar1090 (via lighttpd), piaware, and mlat-client instances
# ==============================================================================

declare gps_source
declare gpsd_host
declare gpsd_port
declare latitude
declare longitude
declare altitude_ft
declare altitude_m
declare receiver_type
declare gain
declare rtlsdr_ppm
declare rtlsdr_device_serial
declare log_level
declare gps_coordinate_updates
declare gps_coordinate_update_interval

# Temp files for coordinating planned readsb restarts
COORD_UPDATE_FILE="/tmp/ultrafeeder_coord_update"
READSB_PID_FILE="/tmp/readsb.pid"

# UUID persistence file
UUID_FILE="/data/ultrafeeder/uuids.json"

# Track background PIDs
MLAT_PIDS=()
PIAWARE_PID=""
GPS_MONITOR_PID=""
LIGHTTPD_PID=""
READSB_PID=""

# --- Read configuration ---
log_level=$(bashio::config 'log_level' 'info')
bashio::log.level "${log_level}"

gps_source=$(bashio::config 'gps_source' 'manual')
altitude_ft=$(bashio::config 'altitude_ft' '0')
altitude_m=$(bashio::config 'altitude_m' '0')
gps_coordinate_updates=$(bashio::config 'gps_coordinate_updates' 'false')
gps_coordinate_update_interval=$(bashio::config 'gps_coordinate_update_interval' '60')
receiver_type=$(bashio::config 'receiver_type' 'rtlsdr')
gain=$(bashio::config 'gain' 'auto')
rtlsdr_ppm=$(bashio::config 'rtlsdr_ppm' '0')
rtlsdr_device_serial=$(bashio::config 'rtlsdr_device_serial' '')

# --- Compute altitude in meters ---
if [ "${altitude_m}" -gt 0 ] 2>/dev/null; then
    bashio::log.info "Using altitude: ${altitude_m}m (from altitude_m)"
else
    altitude_m=$(( altitude_ft * 3048 / 10000 ))
    bashio::log.info "Using altitude: ${altitude_m}m (converted from ${altitude_ft}ft)"
fi

# --- UUID management ---
# Loads or generates a UUID for a given service. User config overrides take priority.
# Usage: get_uuid <service_name> <config_value>
get_uuid() {
    local service="$1"
    local config_val="$2"

    # User-provided UUID takes priority
    if [ -n "${config_val}" ]; then
        echo "${config_val}"
        return
    fi

    # Initialize UUID file if missing
    if [ ! -f "${UUID_FILE}" ]; then
        echo '{}' > "${UUID_FILE}"
    fi

    # Check for existing persisted UUID
    local saved
    saved=$(jq -r --arg s "${service}" '.[$s] // empty' "${UUID_FILE}")
    if [ -n "${saved}" ]; then
        echo "${saved}"
        return
    fi

    # Generate and persist a new UUID
    local new_uuid
    new_uuid=$(cat /proc/sys/kernel/random/uuid)
    jq --arg s "${service}" --arg u "${new_uuid}" '.[$s] = $u' "${UUID_FILE}" > "${UUID_FILE}.tmp" \
        && mv "${UUID_FILE}.tmp" "${UUID_FILE}"
    bashio::log.info "Generated new UUID for ${service}: ${new_uuid}"
    echo "${new_uuid}"
}

# --- Resolve coordinates ---
if [ "${gps_source}" = "gpsd" ]; then
    gpsd_host=$(bashio::config 'gpsd_host' '')
    gpsd_port=$(bashio::config 'gpsd_port' '2947')
    [ -z "${gpsd_host}" ] && gpsd_host="homeassistant.local"

    bashio::log.info "GPS source: gpsd (${gpsd_host}:${gpsd_port})"

    fix=""
    for attempt in 1 2 3 4 5; do
        bashio::log.info "Querying gpsd for fix (attempt ${attempt}/5)..."
        raw=$(gpsd_client --host "${gpsd_host}" --port "${gpsd_port}" --count 30 --timeout 30 2>/dev/null || true)
        bashio::log.trace "gpsd_client raw output: ${raw}"
        fix=$(echo "${raw}" | jq -c 'select(.class=="TPV") | select(.mode>=2) | select(.lat!=null and .lon!=null)' | tail -1)
        bashio::log.debug "Parsed fix: ${fix:-<none>}"
        [ -n "${fix}" ] && break
        [ "${attempt}" -lt 5 ] && bashio::log.info "No fix yet, retrying in 15s..." && sleep 15
    done

    if [ -z "${fix}" ]; then
        bashio::log.warning "Could not obtain a GPS fix from gpsd after 5 attempts. Starting without coordinates."
        latitude=""
        longitude=""
    else
        latitude=$(echo "${fix}" | jq -r '.lat')
        longitude=$(echo "${fix}" | jq -r '.lon')

        if [ -z "${latitude}" ] || [ "${latitude}" = "null" ] || [ -z "${longitude}" ] || [ "${longitude}" = "null" ]; then
            bashio::log.warning "gpsd returned a fix but lat/lon were null. Starting without coordinates."
            latitude=""
            longitude=""
        else
            bashio::log.info "Coordinates from gpsd: lat=${latitude}, lon=${longitude}"
        fi
    fi
else
    latitude=$(bashio::config 'latitude' '')
    longitude=$(bashio::config 'longitude' '')

    if [ -z "${latitude}" ] || [ -z "${longitude}" ]; then
        bashio::log.fatal "latitude and longitude are required when gps_source is 'manual'."
        exit 1
    fi
fi

# --- Build readsb arguments ---
READSB_STATIC_ARGS=(
    --net
    --net-sbs-port 30003
    --net-bi-port 30004
    --net-bo-port 30005
    --net-ro-port 30002
    --fix
    --json-location-accuracy 1
    --write-json /run/readsb
    --write-json-every 1
    --write-globe-history /data/ultrafeeder/globe_history
    --write-json-globe-index
    --heatmap-dir /data/ultrafeeder/heatmap
    --quiet
)

case "${receiver_type}" in
    rtlsdr)
        READSB_STATIC_ARGS+=(--device-type rtlsdr)
        if [ "${gain}" = "auto" ]; then
            READSB_STATIC_ARGS+=(--gain -1)
        elif [ "${gain}" = "max" ]; then
            READSB_STATIC_ARGS+=(--gain -10)
        else
            READSB_STATIC_ARGS+=(--gain "${gain}")
        fi
        if [ "${rtlsdr_ppm}" != "0" ]; then
            READSB_STATIC_ARGS+=(--ppm "${rtlsdr_ppm}")
        fi
        if [ -n "${rtlsdr_device_serial}" ]; then
            READSB_STATIC_ARGS+=(--device "${rtlsdr_device_serial}")
        fi
        ;;
    beast)
        READSB_STATIC_ARGS+=(--net-only --net-connector "localhost,30004,beast_in")
        ;;
    relay)
        READSB_STATIC_ARGS+=(--net-only)
        ;;
esac

# --- Add aggregator feed connectors ---
# Each enabled feed adds a --net-connector to push Beast data to the aggregator.
# readsb handles connection management and auto-reconnect internally.

declare -A FEED_HOSTS=(
    [adsb_fi]="feed.adsb.fi,30004,beast_reduce_plus_out"
    [adsbexchange]="feed1.adsbexchange.com,30004,beast_reduce_plus_out"
    [adsb_lol]="in.adsb.lol,30004,beast_reduce_plus_out"
    [airplanes_live]="feed.airplanes.live,30004,beast_reduce_plus_out"
    [planespotters]="feed.planespotters.net,30004,beast_reduce_plus_out"
    [theairtraffic]="feed.theairtraffic.com,30004,beast_reduce_plus_out"
)

if bashio::var.true "$(bashio::config 'feed_adsb_fi')"; then
    READSB_STATIC_ARGS+=(--net-connector "${FEED_HOSTS[adsb_fi]}")
    bashio::log.info "Feed enabled: adsb.fi"
fi
if bashio::var.true "$(bashio::config 'feed_adsbexchange')"; then
    READSB_STATIC_ARGS+=(--net-connector "${FEED_HOSTS[adsbexchange]}")
    bashio::log.info "Feed enabled: ADSBExchange"
fi
if bashio::var.true "$(bashio::config 'feed_adsb_lol')"; then
    READSB_STATIC_ARGS+=(--net-connector "${FEED_HOSTS[adsb_lol]}")
    bashio::log.info "Feed enabled: adsb.lol"
fi
if bashio::var.true "$(bashio::config 'feed_airplanes_live')"; then
    READSB_STATIC_ARGS+=(--net-connector "${FEED_HOSTS[airplanes_live]}")
    bashio::log.info "Feed enabled: airplanes.live"
fi
if bashio::var.true "$(bashio::config 'feed_planespotters')"; then
    READSB_STATIC_ARGS+=(--net-connector "${FEED_HOSTS[planespotters]}")
    bashio::log.info "Feed enabled: planespotters.net"
fi
if bashio::var.true "$(bashio::config 'feed_theairtraffic')"; then
    READSB_STATIC_ARGS+=(--net-connector "${FEED_HOSTS[theairtraffic]}")
    bashio::log.info "Feed enabled: theairtraffic.com"
fi

# Custom feeds
custom_feed_count=$(bashio::config 'custom_feeds | length')
for (( i=0; i<custom_feed_count; i++ )); do
    host=$(bashio::config "custom_feeds[${i}].host")
    beast_port=$(bashio::config "custom_feeds[${i}].beast_port")
    if [ -n "${host}" ]; then
        READSB_STATIC_ARGS+=(--net-connector "${host},${beast_port},beast_reduce_plus_out")
        bashio::log.info "Custom feed enabled: ${host}:${beast_port}"
    fi
done

# --- start_readsb <lat> <lon> ---
start_readsb() {
    local lat="$1"
    local lon="$2"
    local args=("${READSB_STATIC_ARGS[@]}")

    if [ -n "${lat}" ] && [ -n "${lon}" ]; then
        args+=(--lat "${lat}" --lon "${lon}")
    else
        bashio::log.warning "No coordinates available — range rings and map centering will be unavailable."
    fi

    bashio::log.debug "readsb args: ${args[*]}"
    readsb "${args[@]}" &
    local pid=$!
    echo "${pid}" > "${READSB_PID_FILE}"
}

# --- Configure tar1090 ---
configure_tar1090() {
    local config_file="/usr/local/share/tar1090/html/config.js"
    bashio::log.info "Writing tar1090 config..."
    {
        echo "// Auto-generated by ultrafeeder run.sh"
        echo "PageName = \"Ultrafeeder\";"
        if [ -n "${latitude}" ] && [ -n "${longitude}" ]; then
            echo "SiteShow = true;"
            echo "SiteLat = ${latitude};"
            echo "SiteLon = ${longitude};"
        else
            echo "SiteShow = false;"
        fi
        echo "EnableHeatmap = true;"
        echo "HeatmapDir = \"/heatmap/\";"
        echo "GlobeHistoryDir = \"/globe_history/\";"
    } > "${config_file}"
}

# --- Start piaware ---
start_piaware() {
    local feeder_id
    feeder_id=$(bashio::config 'flightaware_feeder_id' '')
    local allow_mlat
    allow_mlat=$(bashio::config 'flightaware_allow_mlat' 'true')

    mkdir -p /data/ultrafeeder/piaware

    # Handle feeder ID: config > saved file > auto-generate
    if [ -n "${feeder_id}" ]; then
        bashio::log.info "Using FlightAware feeder ID from configuration: ${feeder_id}"
    elif [ -f /data/ultrafeeder/piaware/feeder-id ]; then
        feeder_id=$(cat /data/ultrafeeder/piaware/feeder-id)
        bashio::log.info "Using saved FlightAware feeder ID: ${feeder_id}"
    else
        bashio::log.info "No FlightAware feeder ID found, will be auto-generated by PiAware"
    fi

    if [ -n "${feeder_id}" ]; then
        piaware-config feeder-id "${feeder_id}"
    fi

    piaware-config receiver-type other
    piaware-config receiver-host localhost
    piaware-config receiver-port 30005

    if bashio::var.true "${allow_mlat}"; then
        piaware-config allow-mlat yes
    else
        piaware-config allow-mlat no
    fi

    piaware -plainlog -statusfile /run/piaware/status.json &
    PIAWARE_PID=$!
    bashio::log.info "PiAware started (PID: ${PIAWARE_PID})"

    # Capture feeder ID after startup
    (
        sleep 15
        if [ ! -f /data/ultrafeeder/piaware/feeder-id ]; then
            captured_id=""
            if [ -f /var/cache/piaware/feeder_id ]; then
                captured_id=$(cat /var/cache/piaware/feeder_id)
            elif command -v piaware-config > /dev/null; then
                captured_id=$(piaware-config -show feeder-id 2>/dev/null || true)
            fi
            if [ -n "${captured_id}" ] && [ "${captured_id}" != "not set" ]; then
                echo "${captured_id}" > /data/ultrafeeder/piaware/feeder-id
                bashio::log.info "FlightAware feeder ID captured and saved: ${captured_id}"
            fi
        fi
    ) &
}

# --- Start mlat-client instances ---
# Each MLAT-enabled aggregator gets its own mlat-client process.
# Results feed back into readsb's beast input port so MLAT positions appear on tar1090.
start_mlat_clients() {
    if [ -z "${latitude}" ] || [ -z "${longitude}" ]; then
        bashio::log.warning "No coordinates available — skipping MLAT clients"
        return
    fi

    declare -A MLAT_SERVERS=(
        [adsb_fi]="feed.adsb.fi,31090"
        [adsbexchange]="feed.adsbexchange.com,31090"
        [adsb_lol]="in.adsb.lol,31090"
        [airplanes_live]="feed.airplanes.live,31090"
        [planespotters]="mlat.planespotters.net,31090"
        [theairtraffic]="mlat.theairtraffic.com,31090"
    )

    declare -A MLAT_UUID_CONFIGS=(
        [adsb_fi]="adsb_fi_uuid"
        [adsbexchange]="adsbexchange_uuid"
        [adsb_lol]="adsb_lol_uuid"
        [airplanes_live]="airplanes_live_uuid"
        [planespotters]="planespotters_uuid"
        [theairtraffic]="theairtraffic_uuid"
    )

    declare -A MLAT_FEED_FLAGS=(
        [adsb_fi]="feed_adsb_fi"
        [adsbexchange]="feed_adsbexchange"
        [adsb_lol]="feed_adsb_lol"
        [airplanes_live]="feed_airplanes_live"
        [planespotters]="feed_planespotters"
        [theairtraffic]="feed_theairtraffic"
    )

    for service in adsb_fi adsbexchange adsb_lol airplanes_live planespotters theairtraffic; do
        local feed_flag="${MLAT_FEED_FLAGS[${service}]}"
        if ! bashio::var.true "$(bashio::config "${feed_flag}")"; then
            continue
        fi

        local server_info="${MLAT_SERVERS[${service}]}"
        local server_host="${server_info%%,*}"
        local server_port="${server_info##*,}"

        local uuid_config="${MLAT_UUID_CONFIGS[${service}]}"
        local uuid_val
        uuid_val=$(bashio::config "${uuid_config}" '')
        local uuid
        uuid=$(get_uuid "${service}" "${uuid_val}")

        bashio::log.info "Starting mlat-client for ${service} (${server_host}:${server_port})"
        mlat-client \
            --input-type dump1090 \
            --input-connect localhost:30005 \
            --server "${server_host}:${server_port}" \
            --lat "${latitude}" --lon "${longitude}" --alt "${altitude_m}" \
            --user "${uuid}" \
            --results beast,connect,localhost:30004 \
            2>&1 | while read -r line; do bashio::log.debug "[mlat:${service}] ${line}"; done &
        MLAT_PIDS+=($!)
    done

    # Custom feed MLAT clients
    for (( i=0; i<custom_feed_count; i++ )); do
        local host
        host=$(bashio::config "custom_feeds[${i}].host")
        local mlat_port
        mlat_port=$(bashio::config "custom_feeds[${i}].mlat_port" '0')

        if [ -n "${host}" ] && [ "${mlat_port}" -gt 0 ] 2>/dev/null; then
            local uuid
            uuid=$(get_uuid "custom_${host}" "")
            bashio::log.info "Starting mlat-client for custom feed ${host}:${mlat_port}"
            mlat-client \
                --input-type dump1090 \
                --input-connect localhost:30005 \
                --server "${host}:${mlat_port}" \
                --lat "${latitude}" --lon "${longitude}" --alt "${altitude_m}" \
                --user "${uuid}" \
                --results beast,connect,localhost:30004 \
                2>&1 | while read -r line; do bashio::log.debug "[mlat:${host}] ${line}"; done &
            MLAT_PIDS+=($!)
        fi
    done

    if [ ${#MLAT_PIDS[@]} -gt 0 ]; then
        bashio::log.info "Started ${#MLAT_PIDS[@]} mlat-client instance(s)"
    fi
}

# --- GPS coordinate monitor loop ---
gps_monitor_loop() {
    local current_lat="${latitude}"
    local current_lon="${longitude}"

    bashio::log.info "GPS coordinate monitor started (interval: ${gps_coordinate_update_interval}s)"

    while true; do
        sleep "${gps_coordinate_update_interval}"

        raw=$(gpsd_client --host "${gpsd_host}" --port "${gpsd_port}" --count 30 --timeout 30 2>/dev/null || true)
        bashio::log.trace "GPS monitor gpsd_client output: ${raw}"
        fix=$(echo "${raw}" | jq -c 'select(.class=="TPV") | select(.mode>=2) | select(.lat!=null and .lon!=null)' | tail -1)

        if [ -z "${fix}" ]; then
            bashio::log.debug "GPS monitor: no fix available"
            continue
        fi

        new_lat=$(echo "${fix}" | jq -r '.lat')
        new_lon=$(echo "${fix}" | jq -r '.lon')

        changed=$(awk -v nlat="${new_lat}" -v clat="${current_lat:-0}" \
                       -v nlon="${new_lon}" -v clon="${current_lon:-0}" \
                  'BEGIN {
                       dlat = nlat - clat; if (dlat < 0) dlat = -dlat
                       dlon = nlon - clon; if (dlon < 0) dlon = -dlon
                       print (dlat > 0.001 || dlon > 0.001) ? "yes" : "no"
                   }')

        if [ "${changed}" = "yes" ]; then
            bashio::log.info "Location changed: (${current_lat},${current_lon}) -> (${new_lat},${new_lon}) — restarting readsb"
            current_lat="${new_lat}"
            current_lon="${new_lon}"

            echo "${new_lat} ${new_lon}" > "${COORD_UPDATE_FILE}"
            readsb_pid=$(cat "${READSB_PID_FILE}" 2>/dev/null)
            [ -n "${readsb_pid}" ] && kill "${readsb_pid}" 2>/dev/null
        else
            bashio::log.debug "GPS monitor: position unchanged (lat=${new_lat}, lon=${new_lon})"
        fi
    done
}

# --- Graceful shutdown handler ---
cleanup() {
    bashio::log.info "Shutting down..."
    [ -n "${GPS_MONITOR_PID}" ] && kill "${GPS_MONITOR_PID}" 2>/dev/null
    [ -n "${READSB_PID}" ] && kill "${READSB_PID}" 2>/dev/null
    [ -n "${LIGHTTPD_PID}" ] && kill "${LIGHTTPD_PID}" 2>/dev/null
    [ -n "${PIAWARE_PID}" ] && kill "${PIAWARE_PID}" 2>/dev/null
    for pid in "${MLAT_PIDS[@]}"; do
        kill "${pid}" 2>/dev/null
    done
    rm -f "${COORD_UPDATE_FILE}" "${READSB_PID_FILE}"
    wait
    exit 0
}
trap cleanup SIGTERM SIGINT

# --- Persistent data directory ---
mkdir -p /data/ultrafeeder /data/ultrafeeder/globe_history /data/ultrafeeder/heatmap

# --- Configure tar1090 ---
configure_tar1090

# --- Start readsb ---
bashio::log.info "Starting readsb..."
bashio::log.info "  Latitude:      ${latitude:-<not set>}"
bashio::log.info "  Longitude:     ${longitude:-<not set>}"
bashio::log.info "  Altitude:      ${altitude_m}m"
bashio::log.info "  Gain:          ${gain}"
bashio::log.info "  Receiver type: ${receiver_type}"

start_readsb "${latitude}" "${longitude}"
READSB_PID=$(cat "${READSB_PID_FILE}")

sleep 3

if ! kill -0 "${READSB_PID}" 2>/dev/null; then
    bashio::log.error "readsb failed to start!"
    exit 1
fi
bashio::log.info "readsb started (PID: ${READSB_PID})"

# --- Start lighttpd (tar1090 web server) ---
bashio::log.info "Starting lighttpd for tar1090..."
lighttpd -f /etc/lighttpd/lighttpd.conf -D &
LIGHTTPD_PID=$!

# --- Start piaware (if enabled) ---
if bashio::var.true "$(bashio::config 'feed_flightaware')"; then
    bashio::log.info "Starting PiAware for FlightAware feeding..."
    start_piaware
fi

# --- Start MLAT clients ---
start_mlat_clients

# --- Start GPS coordinate monitor ---
if [ "${gps_source}" = "gpsd" ] && bashio::var.true "${gps_coordinate_updates}"; then
    gps_monitor_loop &
    GPS_MONITOR_PID=$!
fi

# --- Monitor processes ---
bashio::log.info "All processes started, monitoring..."

while true; do
    sleep 10

    # readsb is critical
    if ! kill -0 "${READSB_PID}" 2>/dev/null; then
        if [ -f "${COORD_UPDATE_FILE}" ]; then
            read -r latitude longitude < "${COORD_UPDATE_FILE}"
            rm -f "${COORD_UPDATE_FILE}"
            bashio::log.info "Restarting readsb with updated coordinates: lat=${latitude}, lon=${longitude}"
            configure_tar1090
            start_readsb "${latitude}" "${longitude}"
READSB_PID=$(cat "${READSB_PID_FILE}")
            sleep 3
            if ! kill -0 "${READSB_PID}" 2>/dev/null; then
                bashio::log.error "readsb failed to restart after coordinate update!"
                cleanup
            fi
            bashio::log.info "readsb restarted (PID: ${READSB_PID})"
        else
            bashio::log.error "readsb exited unexpectedly, shutting down..."
            cleanup
        fi
    fi

    # lighttpd is critical
    if ! kill -0 "${LIGHTTPD_PID}" 2>/dev/null; then
        bashio::log.error "lighttpd exited unexpectedly, shutting down..."
        cleanup
    fi

    # piaware auto-restarts if it was enabled
    if [ -n "${PIAWARE_PID}" ] && ! kill -0 "${PIAWARE_PID}" 2>/dev/null; then
        bashio::log.warning "PiAware exited, restarting..."
        start_piaware
    fi
done
