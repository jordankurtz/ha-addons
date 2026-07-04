# Jordan's Home Assistant Add-ons

[![License](https://img.shields.io/github/license/jordankurtz/ha-addons.svg)](LICENSE)

## Add-ons

### Pi-hole

Network-wide ad blocking via your own DNS server. Pi-hole v6 with FTL DNS
engine, web admin interface through Home Assistant ingress, DNSSEC support,
and persistent configuration.

[Documentation](pihole/DOCS.md)

### Unbound

Recursive DNS resolver with DNSSEC validation. Unbound resolves queries
directly from root DNS servers without relying on any third-party DNS
provider, providing maximum privacy. Pairs with Pi-hole for ad blocking
with recursive resolution behind it.

[Documentation](unbound/DOCS.md)

### PiAware

Full ADS-B receiver stack with PiAware (FlightAware feeder), dump1090-fa
(ADS-B decoder), and SkyAware (web-based aircraft map). Includes MLAT
support, Beast/SBS output, and automatic feeder ID persistence.

[Documentation](piaware/DOCS.md)

## Versioning

Each add-on has two version numbers that track different things:

- **Add-on version** (`config.yaml`) — the packaging/integration layer:
  Dockerfile, Home Assistant config schema, ingress UI, startup scripts.
  Bumped on every change to the add-on itself, including automated
  dependency-only bumps (patch-level).
- **Bundled component version** (`build.yaml`, documented per-addon in each
  `DOCS.md`) — the pinned version of the actual upstream service the add-on
  wraps (Pi-hole, gpsd, dump1090, readsb, etc).

These are intentionally decoupled rather than mirrored 1:1: several add-ons
bundle more than one versioned service (PiAware wraps both dump1090 and
piaware_builder; Ultrafeeder wraps four), so there's no single upstream
version an add-on version could mirror. The nightly `check-updates` workflow
keeps both in sync automatically — when it bumps a pinned component version,
it also bumps that add-on's own version and updates the component-version
table in its `DOCS.md`, so the two never drift apart from each other even
though they don't match each other numerically.

## Installation

Add this repository to your Home Assistant add-on store:

```
https://github.com/jordankurtz/ha-addons
```
