# Ultrafeeder

ADS-B receiver addon built around **readsb** (actively maintained dump1090 fork), **tar1090** (aircraft map web UI), and multi-service feeding to all major ADS-B aggregators.

## Features

- **readsb** decoder with RTL-SDR, Beast, or relay input
- **tar1090** web map accessible via Home Assistant ingress
- **Multi-service feeding** to FlightAware, adsb.fi, ADSBExchange, adsb.lol, airplanes.live, planespotters.net, and theairtraffic.com
- **MLAT** (multilateration) support for all compatible aggregators
- **GPS support** via the gpsd addon with optional coordinate updates
- **Custom feeds** for additional aggregators
- **UUID auto-generation** and persistence across restarts

## Prerequisites

- An RTL-SDR dongle with a 1090 MHz antenna (for rtlsdr mode)
- Account(s) with the aggregator services you want to feed

## Configuration

### Location

Set your receiver coordinates using either manual entry or the gpsd addon.

- **GPS Source**: `manual` (enter coordinates below) or `gpsd` (query gpsd addon)
- **gpsd Host**: Hostname of gpsd server (defaults to `homeassistant.local`)
- **gpsd Port**: TCP port for gpsd (default `2947`)
- **GPS Coordinate Updates**: Enable periodic polling of gpsd for position changes
- **GPS Update Interval**: Seconds between GPS polls (30-3600)
- **Latitude / Longitude**: Manual coordinates (required when GPS source is manual)
- **Altitude (feet)**: Antenna altitude above sea level in feet
- **Altitude (meters)**: Antenna altitude in meters (takes precedence over feet if set)

### Receiver

- **Receiver Type**: `rtlsdr` (local USB dongle), `beast` (Beast protocol input from another receiver), or `relay` (network-only, no local device)
- **Gain**: `auto`, `max`, or a specific dB value (e.g., `49.6`)
- **RTL-SDR PPM Correction**: Frequency offset correction
- **RTL-SDR Device Serial**: Target a specific dongle by serial number

### Aggregator Feeds

Enable each service you want to feed. UUIDs are auto-generated on first enable and persisted in `/data/ultrafeeder/uuids.json`. You can override with your own UUID if you already have one.

| Service | Feed Toggle | UUID Field |
|---------|------------|------------|
| FlightAware | `feed_flightaware` | `flightaware_feeder_id` |
| adsb.fi | `feed_adsb_fi` | `adsb_fi_uuid` |
| ADSBExchange | `feed_adsbexchange` | `adsbexchange_uuid` |
| adsb.lol | `feed_adsb_lol` | `adsb_lol_uuid` |
| airplanes.live | `feed_airplanes_live` | `airplanes_live_uuid` |
| planespotters.net | `feed_planespotters` | `planespotters_uuid` |
| theairtraffic.com | `feed_theairtraffic` | `theairtraffic_uuid` |

### Custom Feeds

Add additional aggregators using the custom feeds list. Each entry needs:

- **host**: Aggregator hostname
- **beast_port**: Beast data port (typically 30004)
- **mlat_port**: MLAT server port (set to 0 to disable MLAT for this feed)

### FlightAware

FlightAware feeding uses the built-in PiAware client. The feeder ID is auto-generated on first connection and saved to `/data/ultrafeeder/piaware/feeder-id`. To claim your feeder, visit [FlightAware](https://flightaware.com/adsb/piaware/claim) after the first successful connection.

## Network Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 8080 | HTTP | tar1090 web map (via ingress) |
| 30003 | TCP | SBS BaseStation format output |
| 30005 | TCP | Beast protocol output |

## Architecture

```
RTL-SDR → readsb (decoder)
             ├── JSON output → tar1090 (web UI via lighttpd/ingress)
             ├── Beast output :30005 → piaware (FlightAware feeder)
             ├── --net-connector → adsb.fi, ADSBExchange, adsb.lol, etc.
             └── Beast output :30005 → mlat-client instances → MLAT servers
                                        └── results back → readsb :30004
```

## Troubleshooting

### No aircraft on the map
- Check that your RTL-SDR dongle is connected and visible (`dmesg` should show it)
- Try setting gain to `max` or a specific value instead of `auto`
- Verify your antenna is connected and suitable for 1090 MHz

### Feed not connecting
- Check the addon logs for connection errors
- Verify your UUID is correct if you provided one manually
- Some services may take a few minutes to show your feeder as active

### MLAT not working
- MLAT requires accurate coordinates — ensure latitude, longitude, and altitude are correct
- MLAT needs at least 3-4 receivers in range to produce results
- Check that the aggregator supports MLAT (all built-in services do)

### FlightAware feeder ID not generated
- PiAware may take up to a minute to connect and receive a feeder ID
- Check `/data/ultrafeeder/piaware/feeder-id` after the addon has been running for a few minutes
- If the file doesn't exist, check the addon logs for PiAware errors
