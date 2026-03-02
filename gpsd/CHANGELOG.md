# Changelog

## 1.5.1

- Fix startup hang caused by gpsd 3.27.x binding its TCP socket after device initialisation; now polls for socket readiness (up to 8 s) before probing and logs a clear warning if the port never comes up
- Cap `gpspipe` calls with hard `timeout` guards so a connection failure never stalls the startup probe or location-update loop for 2+ minutes

## 1.5.0

- Build gpsd 3.27.5 from source (GitLab upstream) instead of installing the Debian Bookworm package (3.24); includes CVE fixes and protocol improvements from 3.25–3.27.5
- Version is pinned via `GPSD_VERSION` build arg (default: `release-3.27.5`)

## 1.4.0

- Verify serial link to GPS module at startup via gpsd DEVICES response; logs driver name (u-blox, SiRF, etc.) on success or a clear warning if the module isn't responding
- Remove `/dev/gps0` from auto-detection probe list (udev symlink never exists inside a container)

## 1.3.0

- Add web UI via HA ingress: shows fix status, coordinates, altitude, satellite count, DOP accuracy values, speed, heading, and climb rate; auto-refreshes every 3 seconds

## 1.2.0

- Auto-detection now uses glob patterns to discover all connected devices (any index), not just index 0
- Replaced `/dev/ttyS0` (RS-232 legacy port) with `/dev/gps0` (gpsd udev symlink) in probe list
- All candidate devices logged as "found" or "not present" at startup

## 1.1.0

- Add `log_level` option (trace|debug|info|notice|warning, default: info)

## 1.0.0

- Initial release
- USB GPS device auto-detection (ttyACM0, ttyUSB0, ttyAMA0, ttyS0)
- gpsd exposed on TCP port 2947 (all interfaces) for cross-addon access
- Periodic HA home zone location updates via `homeassistant.set_location`
- Configurable update interval, fix quality requirements, and satellite minimum
- Multi-architecture support (amd64, aarch64, armv7)
