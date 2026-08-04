#!/usr/bin/env python3
"""Loopback-only simulator for observed reads and explicit fixture-only writes."""

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
SCENARIOS = (
    "normal",
    "expire-once",
    "missing",
    "malformed",
    "timeout",
    "write-denied",
    "write-timeout",
    "write-expire-once",
    "u30-power-success",
    "u30-power-reject",
    "u30-power-timeout-before-apply",
    "u30-power-apply-then-timeout",
    "u30-power-malformed-applied",
    "u30-power-malformed-unapplied",
    "u30-power-empty-applied",
    "u30-power-empty-unapplied",
    "u30-power-delayed-convergence",
    "u30-power-readback-mismatch",
    "u30-power-readback-missing",
    "u30-power-readback-malformed",
    "u30-power-readback-timeout",
    "u30-power-readback-invalid-mode",
)
PROFILES = ("u25s", "u30")
U30_POWER_SCENARIOS = {
    scenario for scenario in SCENARIOS if scenario.startswith("u30-power-")
}
FIXTURE_STATE_PATH = "/fixture/action_state"
FIXTURE_ACTIONS = {
    "FIXTURE_SWITCH_SIM",
    "FIXTURE_SET_APN",
    "FIXTURE_SET_CONNECTION_MODE",
    "FIXTURE_SET_WIFI",
    "FIXTURE_SET_TRAFFIC_PLAN",
    "FIXTURE_RESET_TRAFFIC",
    "FIXTURE_SEND_SMS",
    "FIXTURE_DELETE_SMS",
    "FIXTURE_MARK_SMS_READ",
}
CALIBRATED_SIM_ACTION = "SIM_SWITCH_SIMCARD"
CALIBRATED_SIM_INDEXES = {"0", "1", "2", "3"}
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
    "sms_data_total",
	"network_lte_rsrp",
	"network_rscp",
	"lte_rssi",
	"network_simcard_roam",
	"dial_mode",
	"opms_wan_mode",
	"network_rmcc",
	"network_rmnc",
	"wifi_onoff_state",
	"guest_switch",
	"wifi_chip1_ssid1_ssid",
	"wifi_chip1_ssid1_auth_mode",
	"wifi_chip1_ssid1_access_sta_num",
	"wifi_chip2_ssid1_ssid",
	"wifi_chip2_ssid1_auth_mode",
	"wifi_chip2_ssid1_access_sta_num",
	"hardware_version",
	"web_version",
	"wa_version",
	"device_market_name",
	"new_version_state",
	"current_upgrade_state",
	"wa_inner_version",
	"flux_realtime_tx_thrpt",
	"flux_realtime_rx_thrpt",
	"flux_realtime_tx_bytes",
	"flux_realtime_rx_bytes",
	"flux_realtime_time",
	"flux_monthly_tx_bytes",
	"flux_monthly_rx_bytes",
	"flux_monthly_time",
	"date_month",
	"flux_data_volume_limit_switch",
	"flux_data_volume_limit_unit",
	"flux_data_volume_limit_size",
	"flux_data_volume_alert_percent",
	"flux_auto_clear_flow_data_switch",
	"flux_clear_date",
	"flux_limited_disconnect",
	"ConnectionMode",
	"autoConnectWhenRoaming",
	"network_current_network_mode",
	"network_net_select_mode",
	"RadioOff",
	"SSID1",
	"AuthMode",
	"HideSSID",
	"MAX_Access_num",
	"NoForwarding",
	"m_ssid_enable",
	"m_SSID",
	"m_AuthMode",
	"m_HideSSID",
	"m_MAX_Access_num",
	"m_NoForwarding",
	"WirelessMode",
	"CountryCode",
	"Channel",
	"wifi_11n_cap",
	"wifi_coverage",
	"SleepStatusForSingleChipCpe",
	"Z5g_snr",
	"Z5g_SINR",
	"wan_lte_ca",
	"network_lte_ca_pcell_band",
	"bandwidth",
	"network_lte_ca_scell_band",
	"network_lte_ca_scell_bandwidth",
	"network_lte_ca_pcell_arfcn",
	"lte_ca_scell_arfcn",
	"wan_active_band",
	"apn_pdp_type",
	"apn_ipv6_pdp_type",
	"connectionMode",
	"power_supply_mode",
}


def validate_bind_host(host):
    if host != "127.0.0.1":
        raise ValueError("simulator host must be literal loopback 127.0.0.1")
    return host


def validate_profile(profile):
    if profile not in PROFILES:
        raise ValueError(f"unsupported simulator profile: {profile}")
    return profile


class SimulatorState:
    def __init__(
        self,
        scenario,
        login_secret,
        fixture_path,
        request_log,
        allow_fixture_writes=False,
        profile="u25s",
        allow_u30_power_writes=False,
        u30_power_mode=None,
    ):
        self.scenario = scenario
        self.login_secret = login_secret
        self.fixture = fixture_path.read_text(encoding="utf-8").strip()
        self.request_log = request_log
        self.request_log.write_text("", encoding="utf-8")
        self.lock = threading.Lock()
        self.sessions = set()
        self.session_counter = 0
        self.expired_once = False
        self.allow_fixture_writes = allow_fixture_writes
        self.profile = validate_profile(profile)
        self.last_action = None
        self.allow_u30_power_writes = allow_u30_power_writes
        self.u30_power_mode = (
            str(u30_power_mode)
            if u30_power_mode is not None
            else str(json.loads(self.fixture).get("power_supply_mode", "0"))
        )
        self.u30_power_pending_mode = None
        self.u30_power_post_count = 0
        self.u30_power_read_count = 0
        self.active_sim_slot = str(
            json.loads(self.fixture).get("simcard_active_slot_temp", "")
        )

    def expected_digest(self):
        first = hashlib.sha256(
            self.login_secret.encode("utf-8")
        ).hexdigest().upper()
        return hashlib.sha256((first + CHALLENGE).encode("utf-8")).hexdigest().upper()

    def create_session(self):
        with self.lock:
            self.session_counter += 1
            session_id = f"fixture-session-{self.session_counter}"
            self.sessions.add(session_id)
            return session_id

    def session_state(self, session_id, channel):
        with self.lock:
            if session_id not in self.sessions:
                return "invalid"
            expires_here = (
                self.scenario == "expire-once" and channel == "status"
            ) or (
                self.scenario == "write-expire-once" and channel == "write"
            )
            if expires_here and not self.expired_once:
                self.expired_once = True
                self.sessions.discard(session_id)
                return "expired"
            return "valid"

    def status_session_state(self, session_id):
        return self.session_state(session_id, "status")

    def apply_fixture_action(self, action, value):
        with self.lock:
            self.last_action = {"action": action, "value": value}

    def fixture_action_state(self):
        with self.lock:
            return self.last_action

    def apply_sim_switch(self, index):
        with self.lock:
            self.active_sim_slot = index

    def record_u30_power_post(self, mode, result, apply=False, delayed=False):
        with self.lock:
            self.u30_power_post_count += 1
            if delayed:
                self.u30_power_pending_mode = mode
            elif apply:
                self.u30_power_mode = mode
            with self.request_log.open("a", encoding="utf-8") as stream:
                stream.write(
                    f"POST U30_POWER {result} requested={mode} "
                    f"count={self.u30_power_post_count}\n"
                )

    def u30_power_readback(self):
        with self.lock:
            self.u30_power_read_count += 1
            if (
                self.scenario == "u30-power-delayed-convergence"
                and self.u30_power_pending_mode is not None
                and self.u30_power_read_count >= 3
            ):
                self.u30_power_mode = self.u30_power_pending_mode
                self.u30_power_pending_mode = None

            if self.scenario == "u30-power-readback-missing":
                payload = "{}"
                result = "MISSING"
            elif self.scenario == "u30-power-readback-malformed":
                payload = "not-json"
                result = "MALFORMED"
            elif self.scenario == "u30-power-readback-invalid-mode":
                payload = '{"power_supply_mode":"2"}'
                result = "INVALID_MODE"
            else:
                mode = self.u30_power_mode
                if self.scenario == "u30-power-readback-mismatch":
                    mode = "0" if mode == "1" else "1"
                payload = json.dumps(
                    {"power_supply_mode": mode}, separators=(",", ":")
                )
                result = f"200 mode={mode}"
            with self.request_log.open("a", encoding="utf-8") as stream:
                stream.write(
                    f"GET U30_POWER {result} count={self.u30_power_read_count}\n"
                )
            return payload

    def status_payload(self):
        with self.lock:
            payload = json.loads(self.fixture)
            if "simcard_active_slot_temp" in payload:
                payload["simcard_active_slot_temp"] = self.active_sim_slot
            return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))

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
        if request.path == FIXTURE_STATE_PATH:
            if not self.state.allow_fixture_writes:
                self.state.record("GET FIXTURE_STATE 404")
                self.send_payload(404, '{"error":"not_found"}')
                return
            if self.state.session_state(self.session_id(), "readback") != "valid":
                self.state.record("GET FIXTURE_STATE 401")
                self.send_payload(401, '{"error":"session_expired"}')
                return
            current = self.state.fixture_action_state()
            self.state.record("GET FIXTURE_STATE 200")
            self.send_payload(
                200,
                json.dumps(current or {}, separators=(",", ":")),
            )
            return
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


        if self.state.profile == "u30":
            query = parse_qs(request.query)
            if (
                self.state.scenario in U30_POWER_SCENARIOS
                and command == "power_supply_mode"
            ):
                expected_referer = f"http://{self.headers.get('Host', '')}/"
                if (
                    self.headers.get("Referer") != expected_referer
                    or query.get("isTest", [""])[0] != "false"
                    or "multi_data" in query
                ):
                    self.state.record("GET U30_POWER INVALID_REQUEST")
                    self.send_payload(400, '{"result":"invalid_request"}')
                    return
                payload = self.state.u30_power_readback()
                if self.state.scenario == "u30-power-readback-timeout":
                    time.sleep(2)
                content_type = (
                    "text/plain"
                    if self.state.scenario == "u30-power-readback-malformed"
                    else "application/json"
                )
                self.send_payload(200, payload, content_type)
                return
            if (
                self.headers.get("Referer") != "https://192.168.0.1/"
                or query.get("isTest", [""])[0] != "false"
                or query.get("multi_data", [""])[0] != "1"
            ):
                self.state.record("GET U30_STATUS SECURE_REQUIRED")
                self.send_payload(200, '{"Error":"none secure connection"}')
                return
            self.state.record("GET U30_STATUS 200")
            self.send_payload(200, self.state.status_payload())
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
            self.send_payload(200, self.state.status_payload())

    def do_POST(self):
        request = urlparse(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        form = parse_qs(body, keep_blank_values=True)

        if request.path != ACTION_PATH:
            self.state.record("POST UNKNOWN 404")
            self.send_payload(404, '{"error":"not_found"}')
            return

        action = form.get("goformId", [""])[0]
        if self.state.profile == "u30" and action == "POWER_SUPPLY_SETTING":
            mode_values = form.get("power_supply_mode", [""])
            mode = mode_values[0]
            safe_mode = (
                mode if mode in {"0", "1"} and len(mode_values) == 1
                else "<invalid>"
            )
            if not self.state.allow_u30_power_writes:
                self.state.record(f"POST U30_POWER 403 requested={safe_mode}")
                self.send_payload(403, '{"result":"denied"}')
                return
            expected_referer = f"http://{self.headers.get('Host', '')}/"
            if (
                self.state.scenario not in U30_POWER_SCENARIOS
                or mode not in {"0", "1"}
                or form.get("isTest", [""])[0] != "false"
                or self.headers.get("Referer") != expected_referer
                or self.headers.get("X-Requested-With") != "XMLHttpRequest"
                or self.headers.get("Content-Type")
                != "application/x-www-form-urlencoded"
                or set(form)
                != {"isTest", "goformId", "power_supply_mode"}
                or any(len(values) != 1 for values in form.values())
            ):
                self.state.record_u30_power_post(safe_mode, "400")
                self.send_payload(400, '{"result":"invalid_request"}')
                return

            scenario = self.state.scenario
            if scenario == "u30-power-reject":
                self.state.record_u30_power_post(mode, "403")
                self.send_payload(403, '{"result":"denied"}')
                return
            if scenario == "u30-power-timeout-before-apply":
                self.state.record_u30_power_post(mode, "TIMEOUT_BEFORE_APPLY")
                time.sleep(2)
                self.send_payload(200, '{"result":"success"}')
                return
            if scenario == "u30-power-apply-then-timeout":
                self.state.record_u30_power_post(
                    mode, "APPLY_THEN_TIMEOUT", apply=True
                )
                time.sleep(2)
                self.send_payload(200, '{"result":"success"}')
                return

            applied = scenario not in {
                "u30-power-malformed-unapplied",
                "u30-power-empty-unapplied",
            }
            delayed = scenario == "u30-power-delayed-convergence"
            self.state.record_u30_power_post(
                mode, "200", apply=applied and not delayed, delayed=delayed
            )
            if scenario in {
                "u30-power-malformed-applied",
                "u30-power-malformed-unapplied",
            }:
                self.send_payload(200, "not-json", "text/plain")
            elif scenario in {
                "u30-power-empty-applied",
                "u30-power-empty-unapplied",
            }:
                self.send_payload(200, "")
            else:
                self.send_payload(200, '{"result":"success"}')
            return

        if action != "LOGIN":
            if not self.state.allow_fixture_writes:
                self.state.record("POST WRITE 403")
                self.send_payload(403, '{"result":"denied"}')
                return
            if self.state.session_state(self.session_id(), "write") != "valid":
                event = (
                    f"POST {CALIBRATED_SIM_ACTION} 401"
                    if action == CALIBRATED_SIM_ACTION
                    else "POST FIXTURE_WRITE 401"
                )
                self.state.record(event)
                self.send_payload(401, '{"result":"session_expired"}')
                return
            if self.state.scenario == "write-denied":
                self.state.record("POST FIXTURE_WRITE 403")
                self.send_payload(403, '{"result":"denied"}')
                return
            if self.state.scenario == "write-timeout":
                time.sleep(2)
            if action == CALIBRATED_SIM_ACTION:
                index = form.get("card_index", [""])[0]
                if (
                    index not in CALIBRATED_SIM_INDEXES
                    or form.get("isTest", [""])[0] != "false"
                    or set(form) != {"isTest", "goformId", "card_index"}
                ):
                    self.state.record(f"POST {CALIBRATED_SIM_ACTION} 400")
                    self.send_payload(400, '{"result":"invalid_request"}')
                    return
                self.state.apply_sim_switch(index)
                self.state.record(f"POST {CALIBRATED_SIM_ACTION} 200")
                self.send_payload(200, '{"result":"success"}')
                return
            if action not in FIXTURE_ACTIONS:
                self.state.record("POST WRITE 403")
                self.send_payload(403, '{"result":"denied"}')
                return
            value = form.get("fixture_value", [""])[0]
            if not value or len(form) != 2:
                self.state.record("POST FIXTURE_WRITE 400")
                self.send_payload(400, '{"result":"invalid_fixture_request"}')
                return
            self.state.apply_fixture_action(action, value)
            self.state.record(f"POST {action} 200")
            self.send_payload(200, '{"result":"0"}')
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
    parser.add_argument("--profile", choices=PROFILES, default="u25s")
    parser.add_argument("--ready-file", type=Path, required=True)
    parser.add_argument("--request-log", type=Path, required=True)
    parser.add_argument("--login-secret", required=True)
    parser.add_argument("--allow-fixture-writes", action="store_true")
    parser.add_argument("--allow-u30-power-writes", action="store_true")
    parser.add_argument("--u30-power-mode", choices=("0", "1"))
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        host = validate_bind_host(args.host)
    except ValueError as error:
        raise SystemExit(str(error)) from error

    fixture_path = (
        Path(__file__).parent / "fixtures" / args.profile / "status.json"
        if args.profile == "u30"
        else Path(__file__).parent / "fixtures" / "u25s" / "read_ok.json"
    )
    state = SimulatorState(
        args.scenario,
        args.login_secret,
        fixture_path,
        args.request_log,
        args.allow_fixture_writes,
        args.profile,
        args.allow_u30_power_writes,
        args.u30_power_mode,
    )
    server = SimulatorServer((host, args.port), U25SHandler)
    server.simulator_state = state
    args.ready_file.write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()


if __name__ == "__main__":
    main()
