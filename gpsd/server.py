#!/usr/bin/env python3
"""Minimal HTTP server for the gpsd addon status UI."""

import http.server
import json
import os
import subprocess

INDEX_PATH = "/usr/share/gpsd-ui/index.html"


class GPSHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # suppress per-request access logs
        pass

    def do_GET(self):
        if self.path == "/api/status":
            self._serve_status()
        elif self.path == "/api/messages":
            self._serve_messages()
        else:
            self._serve_index()

    def _serve_status(self):
        try:
            result = subprocess.run(
                ["gpspipe", "-w", "-n", "30", "-t", "10"],
                capture_output=True,
                text=True,
                timeout=12,
            )
            tpv = None
            sky = None
            for line in result.stdout.splitlines():
                try:
                    msg = json.loads(line)
                    cls = msg.get("class")
                    if cls == "TPV":
                        tpv = msg
                    elif cls == "SKY":
                        sky = msg
                except (json.JSONDecodeError, AttributeError):
                    pass

            status = {"fix": False, "mode": 0}

            if tpv:
                mode = tpv.get("mode", 0)
                status.update(
                    {
                        "fix": mode >= 2,
                        "mode": mode,
                        "lat": tpv.get("lat"),
                        "lon": tpv.get("lon"),
                        "alt": tpv.get("alt"),
                        "speed": tpv.get("speed"),
                        "track": tpv.get("track"),
                        "climb": tpv.get("climb"),
                        "epx": tpv.get("epx"),
                        "epy": tpv.get("epy"),
                        "epv": tpv.get("epv"),
                    }
                )

            if sky:
                sats = sky.get("satellites") or []
                status["satellites_used"] = sum(1 for s in sats if s.get("used"))
                status["satellites_visible"] = len(sats)
                status["hdop"] = sky.get("hdop")
                status["pdop"] = sky.get("pdop")
                status["vdop"] = sky.get("vdop")

            body = json.dumps(status).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        except Exception as exc:
            error = json.dumps({"error": str(exc)}).encode()
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(error)))
            self.end_headers()
            self.wfile.write(error)

    def _serve_messages(self):
        try:
            result = subprocess.run(
                ["gpspipe", "-w", "-n", "30", "-t", "10"],
                capture_output=True,
                text=True,
                timeout=12,
            )
            messages = []
            for line in result.stdout.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                    messages.append(msg)
                except (json.JSONDecodeError, AttributeError):
                    pass

            body = json.dumps(messages).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        except Exception as exc:
            error = json.dumps({"error": str(exc)}).encode()
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(error)))
            self.end_headers()
            self.wfile.write(error)

    def _serve_index(self):
        try:
            with open(INDEX_PATH, "rb") as f:
                body = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except FileNotFoundError:
            self.send_response(404)
            self.end_headers()


if __name__ == "__main__":
    port = int(os.environ.get("UI_PORT", 8080))
    server = http.server.HTTPServer(("0.0.0.0", port), GPSHandler)
    print(f"gpsd UI listening on port {port}", flush=True)
    server.serve_forever()
