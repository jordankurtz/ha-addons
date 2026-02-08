# Unbound Recursive DNS

Unbound is a validating, recursive, and caching DNS resolver. It resolves DNS
queries directly from the authoritative root servers, eliminating the need for
a third-party DNS provider. This provides maximum privacy since no external
DNS service sees your queries.

## How It Works

### Recursive Mode (Default)

In recursive mode, Unbound resolves DNS queries by starting at the root DNS
servers and walking the delegation chain to find the authoritative answer.
No third-party DNS provider is involved.

### Forwarding Mode

In forwarding mode, Unbound sends queries to upstream DNS servers (e.g.,
Google DNS, Cloudflare) instead of resolving recursively. This can be faster
but involves a third-party provider. DNS-over-TLS can be enabled for encrypted
forwarding.

### DNSSEC

DNSSEC (DNS Security Extensions) is enabled by default. Unbound validates
cryptographic signatures on DNS responses to prevent spoofing and
cache poisoning. Queries for domains with invalid DNSSEC signatures will
return SERVFAIL.

## Configuration

### `query_logging` (default: `false`)

Log every DNS query and reply to the add-on log. Useful for debugging and
monitoring which domains are being resolved. Disabled by default to reduce
log volume.

### `dnssec` (default: `true`)

Enable DNSSEC validation. When enabled, Unbound verifies the authenticity of
DNS responses using cryptographic signatures.

### `verbosity` (default: `1`)

Log verbosity level:
- `0` — Errors and warnings only
- `1` — Operational information
- `2` — Detailed operational information
- `3`-`5` — Debug-level output (very verbose)

### `num_threads` (default: `1`)

Number of worker threads. For most home setups, 1 thread is sufficient. Match
to the number of CPU cores for higher query volumes.

### `msg_cache_size` (default: `"8m"`)

Size of the message cache. Stores DNS response metadata for faster repeated
lookups.

### `rrset_cache_size` (default: `"16m"`)

Size of the RRset (resource record set) cache. Should be approximately twice
the message cache size.

### `forwarding_enabled` (default: `false`)

Set to `true` to forward queries to upstream DNS servers instead of resolving
recursively.

### `forward_tls` (default: `false`)

Use DNS-over-TLS when forwarding to upstream servers. Only applies when
`forwarding_enabled` is `true`.

### `forward_servers` (default: `["8.8.8.8", "8.8.4.4"]`)

List of upstream DNS servers used when forwarding mode is enabled.

For standard forwarding:
```
- "8.8.8.8"
- "1.1.1.1"
```

For DNS-over-TLS, use `IP@port#hostname` format:
```
- "8.8.8.8@853#dns.google"
- "1.1.1.1@853#cloudflare-dns.com"
```

### `access_control` (default: `["0.0.0.0/0 allow"]`)

Network access control rules. Each entry is a subnet followed by an action:
- `allow` — Allow queries
- `deny` — Silently drop queries
- `refuse` — Reply with REFUSED

Examples:
```
- "192.168.1.0/24 allow"
- "10.0.0.0/8 allow"
- "0.0.0.0/0 refuse"
```

### `listen_port` (default: `53`)

Port for Unbound to listen on. Change to `5335` when running behind Pi-hole
(see pairing instructions below).

### `custom_server_config` (default: `""`)

Raw configuration lines appended to the Unbound `server:` block. For advanced
users who need settings not exposed as standard options. Lines are inserted
verbatim; use Unbound's configuration syntax.

Example:
```
    local-zone: "example.lan." static
    local-data: "nas.example.lan. A 192.168.1.100"
```

## Pairing with Pi-hole

A common setup is Pi-hole for ad blocking with Unbound behind it for recursive
DNS resolution. This gives you both ad blocking and full DNS privacy.

### Setup

1. Install and start the Unbound add-on with these settings:
   - `listen_port`: `5335`
   - All other settings at defaults (recursive mode, DNSSEC enabled)

2. In the Pi-hole add-on configuration, set:
   - `dns1`: `127.0.0.1#5335`
   - `dns2`: (leave empty)
   - `dnssec`: `false` (Unbound handles DNSSEC; enabling it in both causes issues)

3. Restart both add-ons.

### How It Works

```
Client → Pi-hole (:53) → Unbound (:5335) → Root Servers
              ↓
        Ad blocking          Recursive resolution
                             DNSSEC validation
```

Pi-hole handles ad filtering and query logging. Queries that pass the blocklist
are forwarded to Unbound, which resolves them recursively from root servers with
DNSSEC validation.

## DNS-over-TLS Forwarding

To use DNS-over-TLS with forwarding mode:

1. Set `forwarding_enabled` to `true`
2. Set `forward_tls` to `true`
3. Configure `forward_servers` with TLS-compatible entries:

```yaml
forward_servers:
  - "8.8.8.8@853#dns.google"
  - "8.8.4.4@853#dns.google"
  - "1.1.1.1@853#cloudflare-dns.com"
  - "1.0.0.1@853#cloudflare-dns.com"
```

## Testing

Verify Unbound is working with `dig`:

```bash
# Basic query (replace <ha-ip> with your Home Assistant IP)
dig @<ha-ip> example.com

# Test DNSSEC validation (should succeed)
dig @<ha-ip> sigok.verteiltesysteme.net

# Test DNSSEC failure detection (should return SERVFAIL)
dig @<ha-ip> sigfail.verteiltesysteme.net

# Test on non-standard port
dig @<ha-ip> -p 5335 example.com
```
