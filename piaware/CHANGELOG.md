# Changelog

## 1.1.0

- Add `gps_source` option: set to `gpsd` to query the gpsd addon for coordinates at startup instead of entering them manually
- Add `gpsd_host` and `gpsd_port` options for gpsd connection (default: `homeassistant.local:2947`)
- `latitude` and `longitude` are now optional fields; runtime validation enforces them when `gps_source=manual`
- Install `gpsd-clients` (`gpspipe`) for querying the gpsd addon

## 1.0.0

- Initial release
- dump1090-fa ADS-B decoder
- PiAware FlightAware feeder
- SkyAware web map via Home Assistant ingress
- Automatic feeder ID persistence
- RTL-SDR gain and PPM configuration
- MLAT support
- Beast and SBS output ports for feeding other services
- Multi-architecture support (amd64, aarch64, armv7)
