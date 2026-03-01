# Changelog

## 1.0.0

- Initial release
- USB GPS device auto-detection (ttyACM0, ttyUSB0, ttyAMA0, ttyS0)
- gpsd exposed on TCP port 2947 (all interfaces) for cross-addon access
- Periodic HA home zone location updates via `homeassistant.set_location`
- Configurable update interval, fix quality requirements, and satellite minimum
- Multi-architecture support (amd64, aarch64, armv7)
