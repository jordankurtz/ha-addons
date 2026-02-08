#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

# ==============================================================================
# Unbound Recursive DNS Add-on for Home Assistant
# Generates unbound.conf from add-on options and starts unbound in foreground
# ==============================================================================

declare dnssec
declare verbosity
declare num_threads
declare msg_cache_size
declare rrset_cache_size
declare forwarding_enabled
declare forward_tls
declare query_logging
declare listen_port
declare custom_server_config

# --- Read configuration ---
query_logging=$(bashio::config 'query_logging')
dnssec=$(bashio::config 'dnssec')
verbosity=$(bashio::config 'verbosity')
num_threads=$(bashio::config 'num_threads')
msg_cache_size=$(bashio::config 'msg_cache_size')
rrset_cache_size=$(bashio::config 'rrset_cache_size')
forwarding_enabled=$(bashio::config 'forwarding_enabled')
forward_tls=$(bashio::config 'forward_tls')
listen_port=$(bashio::config 'listen_port')
custom_server_config=$(bashio::config 'custom_server_config' '')

# --- Set timezone from HA ---
if bashio::supervisor.ping; then
    timezone=$(bashio::info.timezone)
    if [ -n "${timezone}" ]; then
        export TZ="${timezone}"
        bashio::log.info "Timezone set to ${timezone}"
    fi
fi

# --- Persistent data directory ---
bashio::log.info "Setting up persistent data directory..."
mkdir -p /data/unbound

# --- Root hints ---
ROOT_HINTS="/data/unbound/root.hints"
PACKAGED_HINTS="/usr/share/dns/root.hints"

if [ -f "${ROOT_HINTS}" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "${ROOT_HINTS}") ))
    max_age=$(( 30 * 86400 ))
else
    age=$(( 999999999 ))
    max_age=0
fi

if [ "${age}" -gt "${max_age}" ]; then
    bashio::log.info "Updating root hints from internic..."
    if curl -sSf -o "${ROOT_HINTS}.tmp" \
        "https://www.internic.net/domain/named.root" 2>/dev/null; then
        mv "${ROOT_HINTS}.tmp" "${ROOT_HINTS}"
        bashio::log.info "Root hints updated successfully"
    else
        bashio::log.warning "Failed to download root hints, using packaged version"
        rm -f "${ROOT_HINTS}.tmp"
        if [ ! -f "${ROOT_HINTS}" ]; then
            cp "${PACKAGED_HINTS}" "${ROOT_HINTS}"
        fi
    fi
fi

# --- DNSSEC trust anchor ---
if bashio::var.true "${dnssec}"; then
    bashio::log.info "Updating DNSSEC trust anchor..."
    unbound-anchor -a /data/unbound/root.key -r "${ROOT_HINTS}" || true
    # Ensure root.key exists even if unbound-anchor failed
    if [ ! -f /data/unbound/root.key ]; then
        bashio::log.warning "unbound-anchor did not create root.key, copying packaged root key"
        cp /usr/share/dns/root.key /data/unbound/root.key
    fi
fi

# --- Generate unbound.conf ---
bashio::log.info "Generating unbound configuration..."

LOG_QUERIES="no"
if bashio::var.true "${query_logging}"; then
    LOG_QUERIES="yes"
fi

VALIDATOR_MODULE=""
TRUST_ANCHOR_LINE=""
if bashio::var.true "${dnssec}"; then
    VALIDATOR_MODULE="validator "
    TRUST_ANCHOR_LINE="    auto-trust-anchor-file: \"/data/unbound/root.key\""
fi

cat > /etc/unbound/unbound.conf <<EOF
server:
    verbosity: ${verbosity}
    num-threads: ${num_threads}

    interface: 0.0.0.0
    port: ${listen_port}
    do-ip4: yes
    do-ip6: no
    do-udp: yes
    do-tcp: yes

    msg-cache-size: ${msg_cache_size}
    rrset-cache-size: ${rrset_cache_size}

    root-hints: "${ROOT_HINTS}"

    # Query logging
    log-queries: ${LOG_QUERIES}
    log-replies: ${LOG_QUERIES}

    # Security hardening
    harden-glue: yes
    harden-dnssec-stripped: yes
    harden-referral-path: no
    harden-algo-downgrade: no
    use-caps-for-id: yes
    hide-identity: yes
    hide-version: yes
    qname-minimisation: yes

    # Performance
    prefetch: yes
    serve-expired: yes
    minimal-responses: yes
    so-reuseport: yes

    # DNSSEC
    module-config: "${VALIDATOR_MODULE}iterator"
${TRUST_ANCHOR_LINE}

    # Private address ranges (RFC 1918) - do not query upstream for these
    private-address: 10.0.0.0/8
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: fd00::/8
    private-address: fe80::/10

EOF

# --- Access control ---
for i in $(bashio::config 'access_control|keys'); do
    acl=$(bashio::config "access_control[${i}]")
    echo "    access-control: ${acl}" >> /etc/unbound/unbound.conf
done

echo "" >> /etc/unbound/unbound.conf

# --- Custom server config ---
if [ -n "${custom_server_config}" ]; then
    bashio::log.info "Appending custom server configuration..."
    echo "    # Custom server configuration" >> /etc/unbound/unbound.conf
    echo "${custom_server_config}" >> /etc/unbound/unbound.conf
    echo "" >> /etc/unbound/unbound.conf
fi

# --- Forwarding ---
if bashio::var.true "${forwarding_enabled}"; then
    bashio::log.info "Configuring forwarding mode..."
    {
        echo "forward-zone:"
        echo "    name: \".\""
        if bashio::var.true "${forward_tls}"; then
            echo "    forward-tls-upstream: yes"
        fi
        for i in $(bashio::config 'forward_servers|keys'); do
            server=$(bashio::config "forward_servers[${i}]")
            echo "    forward-addr: ${server}"
        done
    } >> /etc/unbound/unbound.conf
else
    bashio::log.info "Running in recursive mode (resolving from root servers)"
fi

# --- Validate configuration ---
bashio::log.info "Validating configuration..."
if ! unbound-checkconf /etc/unbound/unbound.conf; then
    bashio::log.fatal "Invalid unbound configuration! Check your settings."
    exit 1
fi

# --- Ensure runtime directory ---
mkdir -p /var/run/unbound
chown unbound:unbound /var/run/unbound 2>/dev/null || true
chown -R unbound:unbound /data/unbound 2>/dev/null || true

# --- Start unbound ---
bashio::log.info "Starting Unbound DNS..."
bashio::log.info "Listening on port ${listen_port}"
bashio::log.info "DNSSEC: ${dnssec}"
if bashio::var.true "${forwarding_enabled}"; then
    bashio::log.info "Mode: forwarding"
else
    bashio::log.info "Mode: recursive"
fi

# Trap for graceful shutdown
trap 'bashio::log.info "Shutting down..."; kill ${UNBOUND_PID} 2>/dev/null; wait' SIGTERM SIGINT

unbound -d -c /etc/unbound/unbound.conf &
UNBOUND_PID=$!

wait ${UNBOUND_PID}
