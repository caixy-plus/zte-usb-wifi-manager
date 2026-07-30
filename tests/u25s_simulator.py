#!/usr/bin/env python3
"""Loopback-only simulator for the observed read-only ZTE U25S goform API."""

import argparse
import hashlib
import hmac
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


CHALLENGE = "fixture-challenge"
STATUS_PATH = "/goform/goform_get_cmd_process"
ACTION_PATH = "/goform/goform_set_cmd_process"
SCENARIOS = ("normal", "expire-once", "missing", "malformed", "timeout")
READ_FIELDS = {
    "mc_modem_main_state",
    "network_type",
    "network_signalbar",
    "network_provider_fullname",
    "Z5g_rsrp",
    "ppp_status",
    "simcard_active_slot_temp",
    "usim_esim_type",
    "battery_exist",
    "battery_vol_percent",
    "battery_charging",
    "battery_value",
    "battery_pers",
    "battery_temperature_level",
}


def validate_bind_host(host):
    if host != "127.0.0.1":
        raise ValueError("simulator host must be literal loopback 127.0.0.1")
    return host


class SimulatorState:
    def __init__(self, scenario, login_secret, fixture_path, request_log):
        self.scenario = scenario
        self.login_secret = login_secret
        self.fixture = fixture_path.read_text(encoding="utf-8").strip()
        self.request_log = request_log
        self.request_log.write_text("", encoding="utf-8")
        self.lock = threading.Lock()
        self.sessions = set()
        self.session_counter = 0
        self.expired_once = False

    def expected_digest(self):
        first = hashlib.sha256(self.login_secret.encode("utf-8")).hexdigest()
        return hashlib.sha256((first + CHALLENGE).encode("utf-8")).hexdigest().upper()

    def create_session(self):
        with self.lock:
            self.session_counter += 1
            session_id = f"fixture-session-{self.session_counter}"
            self.sessions.add(session_id)
            return session_id

    def status_session_state(self, session_id):
        with self.lock:
            if session_id not in self.sessions:
                return "invalid"
            if self.scenario == "expire-once" and not self.expired_once:
                self.expired_once = True
                self.sessions.discard(session_id)
                return "expired"
            return "valid"

    def record(self, entry):
        with self.lock:
            with self.request_log.open("a", encoding="utf-8") as stream:
                stream.write(entry + "\n")


class U25SHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, _format, *_args):
        return

    @property
    def state(self):
        return self.server.simulator_state

    def send_payload(self, status, payload, content_type="application/json", headers=None):
        body = payload.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        for name, value in headers or ():
            self.send_header(name, value)
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def session_id(self):
        raw_header = self.headers.get("Cookie", "")
        for part in raw_header.split(";"):
            name, separator, value = part.strip().partition("=")
            if separator and name == "sid":
                return value
        return ""

    def do_GET(self):
        request = urlparse(self.path)
        if request.path != STATUS_PATH:
            self.state.record("GET UNKNOWN 404")
            self.send_payload(404, '{"error":"not_found"}')
            return

        command = parse_qs(request.query).get("cmd", [""])[0]
        if command == "LD":
            if self.state.scenario == "timeout":
                time.sleep(2)
            self.state.record("GET LD 200")
            self.send_payload(200, json.dumps({"LD": CHALLENGE}, separators=(",", ":")))
            return

        requested_fields = command.split(",") if command else []
        if not requested_fields or any(field not in READ_FIELDS for field in requested_fields):
            self.state.record("GET UNKNOWN 404")
            self.send_payload(404, '{"error":"not_found"}')
            return

        session_id = self.session_id()
        if self.state.status_session_state(session_id) != "valid":
            self.state.record("GET STATUS 200")
            self.send_payload(200, "{}")
            return

        self.state.record("GET STATUS 200")
        if self.state.scenario == "malformed":
            self.send_payload(200, "not-json", "text/plain")
        elif self.state.scenario == "missing":
            self.send_payload(
                200,
                '{"network_type":"LTE","battery_exist":"0"}',
            )
        else:
            self.send_payload(200, self.state.fixture)

    def do_POST(self):
        request = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        form = parse_qs(body, keep_blank_values=True)

        if request.path != ACTION_PATH:
            self.state.record("POST UNKNOWN 404")
            self.send_payload(404, '{"error":"not_found"}')
            return

        if form.get("goformId", [""])[0] != "LOGIN":
            self.state.record("POST WRITE 403")
            self.send_payload(403, '{"result":"denied"}')
            return

        supplied_digest = form.get("password", [""])[0]
        if not hmac.compare_digest(supplied_digest, self.state.expected_digest()):
            self.state.record("POST LOGIN 403")
            self.send_payload(403, '{"result":"1"}')
            return

        session_id = self.state.create_session()
        self.state.record("POST LOGIN 200")
        self.send_payload(
            200,
            '{"result":"0"}',
            headers=(("Set-Cookie", f"sid={session_id}; Path=/; HttpOnly; SameSite=Strict"),),
        )


class SimulatorServer(ThreadingHTTPServer):
    daemon_threads = True


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--scenario", choices=SCENARIOS, required=True)
    parser.add_argument("--ready-file", type=Path, required=True)
    parser.add_argument("--request-log", type=Path, required=True)
    parser.add_argument("--login-secret", required=True)
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        host = validate_bind_host(args.host)
    except ValueError as error:
        raise SystemExit(str(error)) from error

    fixture_path = Path(__file__).parent / "fixtures" / "u25s" / "read_ok.json"
    state = SimulatorState(
        args.scenario,
        args.login_secret,
        fixture_path,
        args.request_log,
    )
    server = SimulatorServer((host, args.port), U25SHandler)
    server.simulator_state = state
    args.ready_file.write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()


if __name__ == "__main__":
    main()
