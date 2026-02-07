# Home Assistant Add-on: PiAware

## Overview

This add-on provides a full ADS-B (Automatic Dependent Surveillance-Broadcast)
receiver stack for tracking aircraft. It includes:

- **dump1090-fa**: Decodes ADS-B signals from an RTL-SDR USB dongle
- **PiAware**: Feeds decoded data to FlightAware
- **SkyAware**: Web-based aircraft map accessible through Home Assistant

## Prerequisites

- An RTL-SDR USB dongle (e.g., FlightAware Pro Stick, generic RTL2832U)
- A 1090 MHz ADS-B antenna
- A FlightAware account (free) at https://flightaware.com

## Installation

1. Add this repository to your Home Assistant add-on store
2. Install the PiAware add-on
3. Connect your RTL-SDR dongle to your Home Assistant host
4. Configure latitude, longitude, and other options
5. Start the add-on
6. View the SkyAware map from the Home Assistant sidebar

## Configuration

### Option: `feeder_id` (optional)

Your FlightAware feeder UUID. Leave empty on first run and one will be
auto-generated and saved. If you're migrating from another PiAware setup,
enter your existing feeder ID to maintain your statistics.

### Option: `latitude` (required)

Your receiver's latitude in decimal degrees (e.g., `40.7128`).

### Option: `longitude` (required)

Your receiver's longitude in decimal degrees (e.g., `-74.0060`).

### Option: `altitude_ft` (optional)

Your antenna's altitude in feet above mean sea level. Default: `0`.

### Option: `receiver_type` (required)

Type of ADS-B receiver:
- `rtlsdr`: USB RTL-SDR dongle (most common)
- `relay`: Relay data from another dump1090 instance

### Option: `gain` (required)

RTL-SDR gain setting:
- `max`: Maximum gain (good starting point)
- `auto`: Automatic gain control
- Numeric value: Specific gain in dB (e.g., `49.6`)

Start with `max` and reduce if you see too many noise-induced position errors.

### Option: `allow_mlat` (optional)

Enable multilateration (MLAT). When enabled, FlightAware combines your
signal timing data with nearby receivers to calculate positions for aircraft
that don't broadcast ADS-B. Default: `true`.

### Option: `allow_modeac` (optional)

Enable Mode A/C transponder reception. Default: `true`.

### Option: `rtlsdr_ppm` (optional)

Frequency correction in parts per million. Most modern RTL-SDR dongles have
a TCXO and don't need correction. Default: `0`.

### Option: `rtlsdr_device_serial` (optional)

If you have multiple RTL-SDR dongles, specify the serial number of the one
to use for ADS-B reception. Leave empty to use the first available dongle.

## Network Ports

| Port | Protocol | Description |
|------|----------|-------------|
| 8080 | HTTP | SkyAware web map (via ingress) |
| 30003 | SBS | BaseStation format output |
| 30005 | Beast | Beast binary protocol output |
| 30105 | Beast | MLAT results output |

Ports 30003, 30005, and 30105 can be used to feed other flight tracking
services (e.g., ADS-B Exchange, Plane Finder).

## SkyAware Map

The SkyAware aircraft map is accessible through the Home Assistant sidebar.
Click the "SkyAware" panel to view real-time aircraft positions on a map.

## Feeder ID

Your FlightAware feeder ID is automatically generated on first run and saved
to persistent storage. This ensures your feeder statistics are maintained
across add-on restarts and updates.

To find your feeder ID after first run, check the add-on logs or look in
your FlightAware account under "My ADS-B" > "Claim Your Receiver".

## Troubleshooting

### No aircraft showing up

1. Verify your RTL-SDR dongle is connected and recognized
2. Check the add-on logs for errors
3. Ensure your antenna has a clear view of the sky
4. Try adjusting the gain setting

### USB device not found

1. Make sure the RTL-SDR dongle is plugged into the Home Assistant host
2. Check that no other software is using the dongle
3. Try unplugging and replugging the dongle
4. Restart the add-on

### FlightAware not receiving data

1. Verify your internet connection
2. Check the add-on logs for PiAware connection status
3. Ensure your FlightAware account is active

## External Documentation

- [PiAware Documentation](https://www.flightaware.com/adsb/piaware/)
- [FlightAware ADS-B FAQ](https://www.flightaware.com/adsb/faq/)
- [dump1090-fa (GitHub)](https://github.com/flightaware/dump1090)
- [PiAware Builder (GitHub)](https://github.com/flightaware/piaware_builder)
- [FlightAware Forum](https://discussions.flightaware.com/c/ads-b-flight-tracking/piaware/)

## Support

For bugs and feature requests, please open an issue on
[GitHub](https://github.com/jordankurtz/ha-addons/issues).
