#!/usr/bin/env python3
"""Minimal gpsd JSON client — replaces gpspipe for use in containers.

Connects to gpsd via TCP, sends a WATCH command, and prints JSON
messages to stdout (one per line).  Exits after --count messages
or --timeout seconds of silence, whichever comes first.

Usage:
    gpsd_client.py [--host HOST] [--port PORT] [--count N] [--timeout S]
"""

import argparse
import json
import socket
import sys
import time


def main():
    parser = argparse.ArgumentParser(description="Read JSON from gpsd")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=2947)
    parser.add_argument("--count", type=int, default=30,
                        help="Exit after N messages")
    parser.add_argument("--timeout", type=int, default=30,
                        help="Exit after N seconds of silence")
    args = parser.parse_args()

    try:
        sock = socket.create_connection((args.host, args.port), timeout=5)
    except OSError as e:
        print(f"gpsd_client: connect failed: {e}", file=sys.stderr)
        sys.exit(1)

    sock.settimeout(args.timeout)
    sock.sendall(b'?WATCH={"enable":true,"json":true};\r\n')

    buf = b""
    received = 0
    try:
        while received < args.count:
            chunk = sock.recv(4096)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                line = line.strip()
                if line:
                    print(line.decode("utf-8", errors="replace"), flush=True)
                    received += 1
                    if received >= args.count:
                        break
    except socket.timeout:
        pass
    except OSError as e:
        print(f"gpsd_client: read error: {e}", file=sys.stderr)
    finally:
        sock.close()


if __name__ == "__main__":
    main()
