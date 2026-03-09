# Changelog

## 1.3.1

- Replace `gpspipe` with Python `gpsd_client` for querying gpsd (fixes gpspipe 3.27.x hanging with no output)
- Remove `gpsd-clients` package dependency

## 1.3.0

- Add `gps_coordinate_updates` option: when enabled, PiAware polls gpsd periodically and restarts dump1090-fa when position changes by more than ~100m
- Add `gps_coordinate_update_interval` option (30–3600s, default: 60s)
- Refactor dump1090-fa startup into a function to support clean planned restarts

## 1.2.0

- Add `log_level` option (trace|debug|info|notice|warning, default: info)
- GPS fix failure in gpsd mode is now a warning — PiAware starts without coordinates rather than exiting

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
