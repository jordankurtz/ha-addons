#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

# ==============================================================================
# Pi-hole Add-on for Home Assistant
# Starts Pi-hole FTL DNS with nginx ingress proxy
# ==============================================================================

declare dns1
declare dns2
declare web_password
declare dnssec
declare conditional_forwarding
declare interface
declare query_logging

# --- Read configuration ---
dns1=$(bashio::config 'dns1')
dns2=$(bashio::config 'dns2' '')
web_password=$(bashio::config 'web_password' '')
dnssec=$(bashio::config 'dnssec')
conditional_forwarding=$(bashio::config 'conditional_forwarding')
interface=$(bashio::config 'interface' 'eth0')
query_logging=$(bashio::config 'query_logging')

# --- Set timezone from HA ---
if bashio::supervisor.ping; then
    timezone=$(bashio::info.timezone)
    if [ -n "${timezone}" ]; then
        export TZ="${timezone}"
        bashio::log.info "Timezone set to ${timezone}"
    fi
fi

# --- Persistent data directories ---
bashio::log.info "Setting up persistent data directories..."
mkdir -p /data/pihole /data/dnsmasq.d

# Symlink persistent directories
if [ ! -L /etc/pihole ]; then
    cp -a /etc/pihole/* /data/pihole/ 2>/dev/null || true
    rm -rf /etc/pihole
    ln -s /data/pihole /etc/pihole
fi

if [ ! -L /etc/dnsmasq.d ]; then
    cp -a /etc/dnsmasq.d/* /data/dnsmasq.d/ 2>/dev/null || true
    rm -rf /etc/dnsmasq.d
    ln -s /data/dnsmasq.d /etc/dnsmasq.d
fi

# --- Configure Pi-hole v6 via FTLCONF_ environment variables ---
export FTLCONF_dns_upstreams="${dns1}"
if [ -n "${dns2}" ]; then
    export FTLCONF_dns_upstreams="${dns1};${dns2}"
fi

export FTLCONF_dns_interface="${interface}"

if [ -n "${web_password}" ]; then
    export FTLCONF_webserver_api_password="${web_password}"
else
    export FTLCONF_webserver_api_password=""
fi

if bashio::var.true "${dnssec}"; then
    export FTLCONF_dns_dnssec="true"
else
    export FTLCONF_dns_dnssec="false"
fi

if bashio::var.true "${query_logging}"; then
    export FTLCONF_dns_queryLogging="true"
else
    export FTLCONF_dns_queryLogging="false"
fi

# --- Conditional forwarding ---
if bashio::var.true "${conditional_forwarding}"; then
    cf_ip=$(bashio::config 'conditional_forwarding_ip' '')
    cf_domain=$(bashio::config 'conditional_forwarding_domain' '')
    cf_cidr=$(bashio::config 'conditional_forwarding_cidr' '')

    if [ -n "${cf_ip}" ] && [ -n "${cf_domain}" ]; then
        export FTLCONF_dns_revServer_active="true"
        export FTLCONF_dns_revServer_target="${cf_ip}"
        export FTLCONF_dns_revServer_domain="${cf_domain}"
        if [ -n "${cf_cidr}" ]; then
            export FTLCONF_dns_revServer_cidr="${cf_cidr}"
        fi
        bashio::log.info "Conditional forwarding enabled: ${cf_domain} -> ${cf_ip}"
    else
        bashio::log.warning "Conditional forwarding enabled but IP or domain not set"
    fi
fi

# --- Configure web server to listen on port 80 ---
export FTLCONF_webserver_port="80"

# --- Ensure log directory exists ---
mkdir -p /var/log/pihole
touch /var/log/pihole/pihole.log
chown -R pihole:pihole /var/log/pihole 2>/dev/null || true
chown -R pihole:pihole /data/pihole 2>/dev/null || true
chown -R pihole:pihole /var/run/pihole 2>/dev/null || true

# --- Configure ingress nginx ---
if [ -n "${web_password}" ]; then
    bashio::log.info "Web password is set; ingress will show a notice page"
    bashio::log.info "Use http://<your-ha-ip>/admin/ for password-protected access"

    # Detect the HA IP for the notice page link
    ha_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    direct_url="http://${ha_ip:-<your-ha-ip>}/admin/"

    # Write notice page
    mkdir -p /var/www
    cat > /var/www/ingress-notice.html <<HTMLEOF
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pi-hole</title>
<style>
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, sans-serif;
    display: flex; align-items: center; justify-content: center;
    min-height: 100vh; margin: 0;
    background: #f5f5f5; color: #333;
  }
  .card {
    background: #fff; border-radius: 8px; padding: 2rem 2.5rem;
    max-width: 520px; box-shadow: 0 2px 8px rgba(0,0,0,.1);
    text-align: center;
  }
  h2 { margin-top: 0; color: #d32f2f; }
  a { color: #1976d2; }
  code { background: #eee; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
  .tip { background: #e8f5e9; border-radius: 6px; padding: 1rem; margin-top: 1rem; text-align: left; }
</style>
</head>
<body>
<div class="card">
  <h2>Web Password Active</h2>
  <p>
    Pi-hole's login flow does not work through Home Assistant ingress due to
    redirect and session cookie limitations.
  </p>
  <p>
    Access the admin interface directly at:<br>
    <a href="${direct_url}" target="_blank">${direct_url}</a>
  </p>
  <div class="tip">
    <strong>Tip:</strong> To use Pi-hole through the HA sidebar instead, clear
    the <code>web_password</code> option in the add-on configuration and
    restart. Home Assistant's own authentication protects ingress access.
  </div>
</div>
</body>
</html>
HTMLEOF

    # Replace nginx config with notice page server
    cat > /etc/nginx/conf.d/ingress.conf <<'NGINXEOF'
server {
    listen 8099 default_server;
    root /var/www;
    location / {
        try_files /ingress-notice.html =404;
        add_header X-Frame-Options "" always;
    }
}
NGINXEOF
fi

# --- Start nginx for ingress ---
bashio::log.info "Starting nginx for ingress on port 8099..."
nginx -g 'daemon off;' &
NGINX_PID=$!

# --- Start Pi-hole FTL ---
bashio::log.info "Starting Pi-hole FTL DNS..."
bashio::log.info "Upstream DNS: ${FTLCONF_dns_upstreams}"
bashio::log.info "DNSSEC: ${FTLCONF_dns_dnssec}"
bashio::log.info "Interface: ${interface}"

# Trap for graceful shutdown
trap 'bashio::log.info "Shutting down..."; kill ${NGINX_PID} 2>/dev/null; kill ${FTL_PID} 2>/dev/null; wait' SIGTERM SIGINT

pihole-FTL no-daemon &
FTL_PID=$!

# Wait for any process to exit
wait -n ${NGINX_PID} ${FTL_PID}
bashio::log.warning "Process exited, shutting down add-on..."
kill ${NGINX_PID} 2>/dev/null
kill ${FTL_PID} 2>/dev/null
wait
