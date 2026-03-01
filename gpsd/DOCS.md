# gpsd Add-on

Exposes a USB GPS device over the standard gpsd TCP protocol (port 2947) and optionally keeps your Home Assistant home zone updated with your current GPS coordinates.

Other addons (such as PiAware) can connect to gpsd on port 2947 to obtain live position data without requiring manual lat/lon configuration.

## Requirements

- A USB GPS receiver (NMEA 0183 or compatible). Common chipsets: u-blox, SiRF, MTK.
- The device must appear as a serial port (e.g., `/dev/ttyACM0`, `/dev/ttyUSB0`).

## Installation

1. Add this repository to Home Assistant Add-on Store.
2. Install the **gpsd** add-on.
3. Configure options (see below).
4. Start the add-on. Check the logs to confirm the device was detected and gpsd started.

## Configuration

### `gps_device` (optional, default: auto-detect)

Path to the GPS serial device, e.g. `/dev/ttyACM0`. If left empty, the addon probes the following paths in order and uses the first one found:

1. `/dev/ttyACM0`
2. `/dev/ttyUSB0`
3. `/dev/ttyAMA0`
4. `/dev/ttyS0`

The addon will fail to start if no device is found.

### `update_ha_location` (default: `true`)

When enabled, the addon periodically reads a GPS fix and calls the HA `homeassistant.set_location` service to update the **home** zone coordinates. Useful for mobile setups (vehicles, boats, etc.) or for initial setup of a fixed location.

### `location_update_interval` (default: `60`, range: 10–3600 seconds)

How often (in seconds) to read the GPS and push a new location to HA. For fixed installations, a longer interval (e.g., 300–3600) is fine.

### `require_3d_fix` (default: `false`)

When enabled, only a 3D fix (altitude known) is accepted for HA location updates. A 2D fix (lat/lon only) is still sufficient for most use cases.

### `min_satellites` (default: `4`, range: 0–20)

Minimum number of satellites required for a valid fix. This is informational in the current implementation — the fix validity is determined by gpsd's `mode` field. Set to `0` to disable satellite count checking.

## Connecting Other Addons

The gpsd daemon listens on **TCP port 2947** on all interfaces. Other addons (or clients on your LAN) can connect using the gpsd JSON protocol.

From another addon, use `homeassistant.local` (or the HA host IP) as the hostname and port `2947`.

### PiAware Integration

Set the following in the PiAware addon configuration:

```yaml
gps_source: gpsd
gpsd_host: ""       # leave empty to use homeassistant.local
gpsd_port: 2947
```

## Troubleshooting

- **Device not found**: Check `ls /dev/tty*` on the host to confirm the device path. Set `gps_device` explicitly if auto-detection picks the wrong device.
- **No fix**: GPS receivers typically need 1–5 minutes outdoors to acquire a fix. Cold starts (device moved far) can take longer.
- **HA location not updating**: Confirm `homeassistant_api: true` is in the addon config and the addon is running. Check the addon logs for HTTP error codes.
