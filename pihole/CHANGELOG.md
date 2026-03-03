# Changelog

## 1.3.0

- Add `ntp_sync` option (default: true) — set to false to disable Pi-hole FTL's built-in NTP sync, useful when the host already runs an NTP daemon or the container lacks clock-setting privileges

## 1.2.0

- Bump Pi-hole to 2026.02.0 (Core v6.4, Web v6.4.1, FTL v6.5)

## 1.1.0

- Add `listening_mode` option (local|single|bind|all, default: local) — was previously hardcoded to "all"
- Fix gravity update running before FTL is ready; now polls for FTL readiness before running `pihole -g`

## 1.0.1

- Listen on all interfaces by default
- Run gravity update on startup to initialize blocklists

## 1.0.0

- Initial release
- Pi-hole v6 with FTL DNS
- Home Assistant ingress support via nginx
- DNSSEC validation support
- Conditional forwarding support
- Persistent configuration across restarts
- Multi-architecture support (amd64, aarch64, armv7, armhf, i386)
