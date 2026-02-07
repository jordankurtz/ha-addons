# Home Assistant Add-on: Pi-hole

## Overview

Pi-hole is a network-wide ad blocker that acts as a DNS sinkhole. This add-on
runs Pi-hole v6 with FTL DNS on your Home Assistant instance, allowing you to
block ads and trackers for all devices on your network.

## How it works

Pi-hole intercepts DNS queries from your network devices and blocks requests to
known advertising and tracking domains. Legitimate queries are forwarded to your
configured upstream DNS servers.

## Installation

1. Add this repository to your Home Assistant add-on store
2. Install the Pi-hole add-on
3. Configure your options (see below)
4. Start the add-on
5. Configure your router's DHCP to use your Home Assistant IP as the DNS server

## Configuration

### Option: `dns1` (required)

Primary upstream DNS server. Default: `8.8.8.8` (Google DNS).

### Option: `dns2` (optional)

Secondary upstream DNS server. Default: `8.8.4.4` (Google DNS).

### Option: `web_password` (optional)

Password for the Pi-hole web admin interface. This password is used for
direct access to the web interface (e.g., `http://<your-ha-ip>/admin/`) and
for API consumers like Nebula Sync. See [Web Interface](#web-interface) for
details on how authentication works with Home Assistant ingress.

### Option: `dnssec` (optional)

Enable DNSSEC validation to verify that DNS responses have not been tampered
with. Default: `false`.

### Option: `conditional_forwarding` (optional)

Enable conditional forwarding to allow Pi-hole to resolve local device
hostnames through your router. Default: `false`.

When enabled, you must also configure:

- **`conditional_forwarding_ip`**: Your router's IP address
- **`conditional_forwarding_domain`**: Your local domain (e.g., `lan`, `home`)
- **`conditional_forwarding_cidr`**: Your local network CIDR (e.g., `192.168.1.0/24`)

### Option: `interface` (optional)

Network interface for Pi-hole to listen on. Default: `eth0`.

### Option: `query_logging` (optional)

Enable or disable DNS query logging. Default: `true`.

## Network Configuration

This add-on uses host networking mode to bind directly to port 53 (DNS). You
need to ensure:

1. No other DNS server is running on port 53 on your Home Assistant host
2. Your router or DHCP server is configured to point clients to your Home
   Assistant IP as their DNS server

## Web Interface

The Pi-hole web admin interface is accessible in two ways:

### Home Assistant Ingress (sidebar)

Click the "Pi-hole" panel in the Home Assistant sidebar. Access is protected
by Home Assistant's own authentication — you must be logged in to HA to
reach it. The `web_password` option has no effect here; leave it empty for
the smoothest experience through ingress.

### Direct Access

Browse to `http://<your-ha-ip>/admin/`. If `web_password` is set, you will
be prompted to log in. This is also the address API consumers like Nebula
Sync should use.

### Why the web password does not work through ingress

Pi-hole v6's login flow relies on HTTP redirects and session cookies scoped
to the `/admin/` path. Home Assistant ingress serves the interface under a
different path (`/api/hassio_ingress/<token>/admin/`), which causes two
problems:

1. **Redirects escape ingress** — FTL's login redirect produces a `Location`
   header that the browser follows directly to the add-on's internal port,
   bypassing Home Assistant.
2. **Session cookies never match** — FTL sets cookies with `Path=/admin/`,
   but the browser sees the ingress path, so it never sends the cookie back.

Pi-hole's FTL does not currently offer a way to disable authentication for
localhost or trusted-proxy requests, so there is no workaround. This is a
known upstream limitation and is the same pattern seen with other Pi-hole
reverse proxy setups.

## Data Persistence

Pi-hole configuration and data are stored persistently in the add-on's data
directory. Your settings, blocklists, and query history survive add-on
restarts and updates.

## Known Issues

- **Web password does not work through ingress** — see
  [above](#why-the-web-password-does-not-work-through-ingress). Leave
  `web_password` empty for ingress use; set it only if you need direct
  access protection or API authentication (e.g., Nebula Sync).
- If you have the Home Assistant DNS add-on running, there may be a port 53
  conflict. Disable it or change its port before starting Pi-hole.
- Some Pi-hole features that rely on DHCP are not available in this add-on
  configuration.

## External Documentation

- [Pi-hole Documentation](https://docs.pi-hole.net/)
- [Pi-hole Docker Configuration](https://docs.pi-hole.net/docker/configuration/)
- [FTL Configuration Reference](https://docs.pi-hole.net/ftldns/configfile/)
- [Pi-hole API](https://docs.pi-hole.net/api/)
- [Pi-hole Discourse Community](https://discourse.pi-hole.net/)

## Support

For bugs and feature requests, please open an issue on
[GitHub](https://github.com/jordankurtz/ha-addons/issues).
