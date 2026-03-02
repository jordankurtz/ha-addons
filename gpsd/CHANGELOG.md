# Changelog

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
