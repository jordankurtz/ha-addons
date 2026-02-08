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

## Installation

Add this repository to your Home Assistant add-on store:

```
https://github.com/jordankurtz/ha-addons
```
