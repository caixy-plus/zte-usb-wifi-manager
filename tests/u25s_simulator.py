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
U30_ACCESS_WA = "U30ProV1.0.0B23"
U30_ACCESS_CR = "MU5358V1.0.0B23"
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
    "u30-power-access-missing-rd",
    "u30-setting-success",
    "u30-setting-reject",
    "u30-setting-timeout-before-apply",
    "u30-setting-apply-then-timeout",
    "u30-setting-malformed-applied",
    "u30-setting-malformed-unapplied",
    "u30-setting-empty-applied",
    "u30-setting-empty-unapplied",
    "u30-action-success",
    "u30-action-reject",
    "u30-action-timeout-before-apply",
    "u30-action-apply-then-timeout",
)
PROFILES = ("u25s", "u30")
U30_POWER_SCENARIOS = {
    scenario for scenario in SCENARIOS if scenario.startswith("u30-power-")
}
U30_SETTING_SCENARIOS = {
    scenario for scenario in SCENARIOS if scenario.startswith("u30-setting-")
}
U30_SETTING_ACTIONS = {
    "SET_CONNECTION_MODE",
    "APN_PROC",
    "setAccessPointInfo",
    "switchWiFiModule",
    "DATA_LIMIT_SETTING",
    "RESET_DATA_COUNTER",
}
U30_SETTING_COMMANDS = {
    "ConnectionMode,autoConnectWhenRoaming",
    "index,profile_name,apn_wan_apn,apn_ppp_auth_mode,apn_ppp_username",
    "wifi_onoff_state,wifi_chip1_ssid1_switch_onoff,wifi_chip1_ssid1_ssid,wifi_chip1_ssid1_auth_mode",
    "flux_data_volume_limit_switch,flux_data_volume_limit_unit,flux_data_volume_limit_size,flux_data_volume_alert_percent,flux_auto_clear_flow_data_switch,flux_clear_date,flux_limited_disconnect",
    "flux_monthly_tx_bytes,flux_monthly_rx_bytes,flux_monthly_time",
}
U30_ACTION_SCENARIOS = {
    scenario for scenario in SCENARIOS if scenario.startswith("u30-action-")
}
U30_ACTIONS = {
    "SEND_SMS",
    "DELETE_SMS",
    "SET_MSG_READ",
    "REBOOT_DEVICE",
    "SHUTDOWN_DEVICE",
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
        allow_u30_setting_writes=False,
        allow_u30_action_writes=False,
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
        self.u30_access_challenge_count = 0
        self.u30_access_challenges = {}
        self.allow_u30_setting_writes = allow_u30_setting_writes
        self.u30_setting_post_count = 0
        self.u30_setting_read_count = 0
        self.u30_settings = {
            "ConnectionMode": "auto_dial",
            "autoConnectWhenRoaming": "off",
            "index": "1",
            "profile_name": "Default",
            "apn_wan_apn": "default",
            "apn_ppp_auth_mode": "none",
            "apn_ppp_username": "",
            "wifi_onoff_state": "1",
            "wifi_chip1_ssid1_switch_onoff": "1",
            "wifi_chip1_ssid1_ssid": "Initial WiFi",
            "wifi_chip1_ssid1_auth_mode": "WPA2PSK",
            "flux_data_volume_limit_switch": "0",
            "flux_data_volume_limit_unit": "data",
            "flux_data_volume_limit_size": "0",
            "flux_data_volume_alert_percent": "0",
            "flux_auto_clear_flow_data_switch": "0",
            "flux_clear_date": "1",
            "flux_limited_disconnect": "0",
            "flux_monthly_tx_bytes": "1024",
            "flux_monthly_rx_bytes": "2048",
            "flux_monthly_time": "60",
        }
        self.allow_u30_action_writes = allow_u30_action_writes
        self.u30_action_post_count = 0
        self.u30_sms_status = {"4": "0", "6": "0"}
        self.u30_messages = {"42": "1"}
        self.u30_device_command = None
        self.u30_device_probe_count = 0
        self.active_sim_slot = str(
            json.loads(self.fixture).get("simcard_active_slot_temp", "")
        )

    def expected_digest(self):
        first = hashlib.sha256(
            self.login_secret.encode("utf-8")
        ).hexdigest().upper()
        return hashlib.sha256((first + CHALLENGE).encode("utf-8")).hexdigest().upper()

    def expected_u30_access_digest(self, rd):
        versions = hashlib.sha256(
            (U30_ACCESS_WA + U30_ACCESS_CR).encode("utf-8")
        ).hexdigest().upper()
        return hashlib.sha256(
            (versions + rd).encode("utf-8")
        ).hexdigest().upper()

    def issue_u30_access_challenge(self, session_id):
        with self.lock:
            self.u30_access_challenge_count += 1
            sequence = self.u30_access_challenge_count
            rd = f"fixture-rd-challenge-{sequence}"
            self.u30_access_challenges[session_id] = rd
            with self.request_log.open("a", encoding="utf-8") as stream:
                stream.write(f"GET U30_ACCESS 200 sequence={sequence}\n")
            return rd

    def consume_u30_access_digest(self, session_id, supplied_digest):
        with self.lock:
            rd = self.u30_access_challenges.pop(session_id, None)
            if rd is None:
                return False
            return supplied_digest == self.expected_u30_access_digest(rd)

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

    def u30_setting_patch(self, action, form):
        """Validate one frozen production form and return its state delta."""
        if any(len(values) != 1 for values in form.values()):
            return None
        if form.get("isTest") != ["false"] or form.get("goformId") != [action]:
            return None

        def value(key):
            return form.get(key, [""])[0]

        if action == "SET_CONNECTION_MODE":
            if set(form) != {
                "isTest", "goformId", "ConnectionMode",
                "dial_roam_setting_option",
            } or value("ConnectionMode") not in {
                "auto_dial", "manual_dial", "on_demand",
            } or value("dial_roam_setting_option") != "off":
                return None
            return {
                "ConnectionMode": value("ConnectionMode"),
                "autoConnectWhenRoaming": "off",
            }

        if action == "APN_PROC":
            expected = {
                "isTest", "goformId", "apn_action", "index", "apn_mode",
                "profile_name", "apn_wan_apn", "dns_mode",
                "prefer_dns_manual", "w_standby_dns_manual",
                "apn_ppp_username", "apn_ppp_passwd", "apn_ppp_auth_mode",
                "apn_select", "apn_wan_dial", "apn_pdp_type",
                "apn_pdp_select", "apn_pdp_addr", "set_default_flag",
            }
            if set(form) != expected or value("apn_action") != "set_default" \
                    or value("index") != self.u30_settings["index"] \
                    or value("profile_name") != self.u30_settings["profile_name"] \
                    or value("apn_mode") != "manual" \
                    or value("dns_mode") != "auto" \
                    or value("apn_select") != "manual" \
                    or value("apn_wan_dial") != "*99#" \
                    or value("apn_pdp_type") != "PPP" \
                    or value("apn_pdp_select") != "auto" \
                    or value("set_default_flag") != "1" \
                    or value("prefer_dns_manual") != "" \
                    or value("w_standby_dns_manual") != "" \
                    or value("apn_pdp_addr") != "" \
                    or value("apn_ppp_auth_mode") not in {
                        "none", "pap", "chap", "pap_chap",
                    }:
                return None
            if value("apn_ppp_auth_mode") == "none" and (
                value("apn_ppp_username") != ""
                or value("apn_ppp_passwd") != ""
            ):
                return None
            return {
                "apn_wan_apn": value("apn_wan_apn"),
                "apn_ppp_auth_mode": value("apn_ppp_auth_mode"),
                "apn_ppp_username": value("apn_ppp_username"),
            }

        if action == "switchWiFiModule":
            if set(form) != {"isTest", "goformId", "SwitchOption"} \
                    or value("SwitchOption") != "0":
                return None
            return {
                "wifi_onoff_state": "0",
                "wifi_chip1_ssid1_switch_onoff": "0",
            }

        if action == "setAccessPointInfo":
            expected = {
                "isTest", "goformId", "ChipIndex", "AccessPointIndex",
                "AccessPointSwitchStatus", "SSID", "ApIsolate", "AuthMode",
                "ApBroadcastDisabled", "EncrypType",
            }
            if set(form) not in (expected, expected | {"Password"}) \
                    or value("ChipIndex") != "0" \
                    or value("AccessPointIndex") != "0" \
                    or value("AccessPointSwitchStatus") != "1" \
                    or value("ApIsolate") != "0" \
                    or value("ApBroadcastDisabled") != "0" \
                    or value("AuthMode") not in {
                        "OPEN", "WPA2PSK", "WPA3PSK", "WPA2PSKWPA3PSK",
                    }:
                return None
            if value("AuthMode") == "OPEN":
                if "Password" in form or value("EncrypType") != "NONE":
                    return None
            elif "Password" not in form or value("EncrypType") != "CCMP":
                return None
            return {
                "wifi_onoff_state": "1",
                "wifi_chip1_ssid1_switch_onoff": "1",
                "wifi_chip1_ssid1_ssid": value("SSID"),
                "wifi_chip1_ssid1_auth_mode": value("AuthMode"),
            }

        if action == "DATA_LIMIT_SETTING":
            if value("flux_data_volume_limit_switch") == "0":
                if set(form) != {
                    "isTest", "goformId", "flux_data_volume_limit_switch",
                    "notify_deviceui_enable",
                } or value("notify_deviceui_enable") != "0":
                    return None
                return {
                    "flux_data_volume_limit_switch": "0",
                    "flux_data_volume_limit_unit": "data",
                    "flux_data_volume_limit_size": "0",
                    "flux_data_volume_alert_percent": "0",
                    "flux_auto_clear_flow_data_switch": "0",
                    "flux_clear_date": "1",
                    "flux_limited_disconnect": "0",
                }
            expected = {
                "isTest", "goformId", "flux_data_volume_limit_unit",
                "flux_data_volume_limit_size", "flux_data_volume_alert_percent",
                "flux_auto_clear_flow_data_switch", "flux_clear_date",
                "flux_limited_disconnect", "flux_data_volume_limit_switch",
                "notify_deviceui_enable",
            }
            if set(form) != expected \
                    or value("flux_data_volume_limit_switch") != "1" \
                    or value("flux_data_volume_limit_unit") != "data" \
                    or value("flux_auto_clear_flow_data_switch") != "1" \
                    or value("notify_deviceui_enable") != "0" \
                    or value("flux_limited_disconnect") not in {"0", "1"}:
                return None
            return {
                key: value(key) for key in (
                    "flux_data_volume_limit_switch",
                    "flux_data_volume_limit_unit",
                    "flux_data_volume_limit_size",
                    "flux_data_volume_alert_percent",
                    "flux_auto_clear_flow_data_switch",
                    "flux_clear_date",
                    "flux_limited_disconnect",
                )
            }

        if action == "RESET_DATA_COUNTER":
            if set(form) != {"isTest", "goformId"}:
                return None
            return {
                "flux_monthly_tx_bytes": "0",
                "flux_monthly_rx_bytes": "0",
                "flux_monthly_time": "0",
            }
        return None

    def record_u30_setting_post(self, action, result, patch=None):
        with self.lock:
            self.u30_setting_post_count += 1
            if patch is not None:
                self.u30_settings.update(patch)
            with self.request_log.open("a", encoding="utf-8") as stream:
                stream.write(
                    f"POST U30_SETTING {action} {result} "
                    f"count={self.u30_setting_post_count}\n"
                )

    def u30_setting_readback(self, command):
        with self.lock:
            self.u30_setting_read_count += 1
            payload = {
                key: self.u30_settings[key]
                for key in command.split(",")
                if key in self.u30_settings
            }
            with self.request_log.open("a", encoding="utf-8") as stream:
                stream.write(
                    f"GET U30_SETTING {command} 200 "
                    f"count={self.u30_setting_read_count}\n"
                )
            return json.dumps(payload, separators=(",", ":"))

    def u30_action_valid(self, action, form):
        if any(len(values) != 1 for values in form.values()):
            return False
        if form.get("isTest") != ["false"] or form.get("goformId") != [action]:
            return False
        value = lambda key: form.get(key, [""])[0]
        if action == "SEND_SMS":
            if set(form) != {
                "isTest", "goformId", "notCallback", "Number", "sms_time",
                "MessageBody", "ID", "encode_type",
            }:
                return False
            number = value("Number")
            return (
                value("notCallback") == "true"
                and number.startswith("+")
                and number[1:].isdigit()
                and value("sms_time") != ""
                and value("MessageBody") != ""
                and all(char in "0123456789ABCDEF" for char in value("MessageBody"))
                and value("ID") == "-1"
                and value("encode_type") in {"GSM7_default", "UNICODE"}
            )
        if action == "DELETE_SMS":
            message_id = value("msg_id")
            return (
                set(form) == {
                    "isTest", "goformId", "msg_id", "notCallback",
                }
                and message_id.endswith(";")
                and message_id[:-1].isdigit()
                and value("notCallback") == "true"
            )
        if action == "SET_MSG_READ":
            message_id = value("msg_id")
            return (
                set(form) == {"isTest", "goformId", "msg_id", "tag"}
                and message_id.endswith(";")
                and message_id[:-1].isdigit()
                and value("tag") == "0"
            )
        if action in {"REBOOT_DEVICE", "SHUTDOWN_DEVICE"}:
            return set(form) == {"isTest", "goformId"}
        return False

    def apply_u30_action(self, action, form):
        with self.lock:
            if action == "SEND_SMS":
                self.u30_sms_status["4"] = "3"
            elif action == "DELETE_SMS":
                message_id = form["msg_id"][0][:-1]
                self.u30_messages.pop(message_id, None)
                self.u30_sms_status["6"] = "3"
            elif action == "SET_MSG_READ":
                message_id = form["msg_id"][0][:-1]
                if message_id in self.u30_messages:
                    self.u30_messages[message_id] = "0"
            elif action == "REBOOT_DEVICE":
                self.u30_device_command = "reboot"
                self.u30_device_probe_count = 0
            elif action == "SHUTDOWN_DEVICE":
                self.u30_device_command = "shutdown"
                self.u30_device_probe_count = 0

    def record_u30_action_post(self, action, result):
        with self.lock:
            self.u30_action_post_count += 1
            with self.request_log.open("a", encoding="utf-8") as stream:
                stream.write(
                    f"POST U30_ACTION {action} {result} "
                    f"count={self.u30_action_post_count}\n"
                )

    def u30_sms_status_payload(self, command):
        with self.lock:
            result = self.u30_sms_status.get(command, "0")
            with self.request_log.open("a", encoding="utf-8") as stream:
                stream.write(f"GET U30_SMS_STATUS command={command} result={result}\n")
            return json.dumps(
                {"sms_cmd_status_result": result}, separators=(",", ":")
            )

    def u30_sms_messages_payload(self):
        with self.lock:
            messages = [
                {"id": message_id, "tag": tag}
                for message_id, tag in sorted(self.u30_messages.items())
            ]
            with self.request_log.open("a", encoding="utf-8") as stream:
                stream.write(f"GET U30_SMS_MESSAGES count={len(messages)}\n")
            return json.dumps({"messages": messages}, separators=(",", ":"))

    def u30_device_probe_payload(self):
        with self.lock:
            if self.u30_device_command is None:
                event = "preflight"
                payload = '{"mc_modem_main_state":"connected"}'
            else:
                self.u30_device_probe_count += 1
                count = self.u30_device_probe_count
                if self.u30_device_command == "reboot" and count >= 3:
                    event = "recovered"
                    payload = '{"mc_modem_main_state":"connected"}'
                elif self.u30_device_command == "reboot" and count == 2:
                    event = "outage-qualified"
                    payload = "{}"
                elif self.u30_device_command == "shutdown" and count >= 4:
                    event = "shutdown-offline"
                    payload = "{}"
                elif count == 2:
                    event = "outage-qualified"
                    payload = "{}"
                else:
                    event = "outage-start"
                    payload = "{}"
            with self.request_log.open("a", encoding="utf-8") as stream:
                stream.write(f"GET U30_DEVICE {event} count={self.u30_device_probe_count}\n")
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

        if self.state.profile == "u30" and command == "wa_inner_version,cr_version,RD":
            query = parse_qs(request.query)
            expected_referer = f"http://{self.headers.get('Host', '')}/"
            if (
                self.headers.get("Referer") != expected_referer
                or query.get("isTest", [""])[0] != "false"
                or query.get("multi_data", [""])[0] != "1"
                or self.state.session_state(self.session_id(), "write") != "valid"
            ):
                self.state.record("GET U30_ACCESS INVALID_REQUEST")
                self.send_payload(400, '{"result":"invalid_request"}')
                return
            rd = self.state.issue_u30_access_challenge(self.session_id())
            payload = {
                "wa_inner_version": U30_ACCESS_WA,
                "cr_version": U30_ACCESS_CR,
                "RD": rd,
            }
            if self.state.scenario == "u30-power-access-missing-rd":
                payload.pop("RD")
            self.send_payload(200, json.dumps(payload, separators=(",", ":")))
            return

        requested_fields = command.split(",") if command else []
        if not requested_fields or (
            command not in U30_SETTING_COMMANDS
            and command != "sms_cmd_status_info"
            and any(field not in READ_FIELDS for field in requested_fields)
        ):
            self.state.record("GET UNKNOWN 404")
            self.send_payload(404, '{"error":"not_found"}')
            return


        if self.state.profile == "u30":
            query = parse_qs(request.query)
            if self.state.scenario in U30_ACTION_SCENARIOS:
                expected_referer = f"http://{self.headers.get('Host', '')}/"
                if (
                    self.headers.get("Referer") != expected_referer
                    or query.get("isTest", [""])[0] != "false"
                ):
                    self.state.record("GET U30_ACTION INVALID_REQUEST")
                    self.send_payload(400, '{"result":"invalid_request"}')
                    return
                if command == "sms_cmd_status_info":
                    sms_command = query.get("sms_cmd", [""])[0]
                    if sms_command not in {"1", "2", "3", "4", "5", "6"}:
                        self.send_payload(400, '{"result":"invalid_request"}')
                        return
                    self.send_payload(
                        200, self.state.u30_sms_status_payload(sms_command)
                    )
                    return
                if command == "sms_data_total":
                    self.send_payload(200, self.state.u30_sms_messages_payload())
                    return
                if command == "mc_modem_main_state":
                    self.send_payload(200, self.state.u30_device_probe_payload())
                    return
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
                self.state.scenario in U30_SETTING_SCENARIOS
                and command in U30_SETTING_COMMANDS
            ):
                expected_referer = f"http://{self.headers.get('Host', '')}/"
                if (
                    self.headers.get("Referer") != expected_referer
                    or query.get("isTest", [""])[0] != "false"
                    or query.get("multi_data", [""])[0] != "1"
                ):
                    self.state.record("GET U30_SETTING INVALID_REQUEST")
                    self.send_payload(400, '{"result":"invalid_request"}')
                    return
                self.send_payload(200, self.state.u30_setting_readback(command))
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
            expected_origin = expected_referer.rstrip("/")
            if (
                self.state.scenario not in U30_POWER_SCENARIOS
                or mode not in {"0", "1"}
                or form.get("isTest", [""])[0] != "false"
                or self.headers.get("Referer") != expected_referer
                or self.headers.get("Origin") != expected_origin
                or self.headers.get("X-Requested-With") != "XMLHttpRequest"
                or self.headers.get("Content-Type")
                != "application/x-www-form-urlencoded; charset=UTF-8"
                or set(form)
                != {"isTest", "goformId", "power_supply_mode", "AD"}
                or any(len(values) != 1 for values in form.values())
            ):
                self.state.record_u30_power_post(safe_mode, "400")
                self.send_payload(400, '{"result":"invalid_request"}')
                return
            if self.state.session_state(self.session_id(), "write") != "valid":
                self.state.record_u30_power_post(mode, "401")
                self.send_payload(401, '{"result":"session_expired"}')
                return
            if not self.state.consume_u30_access_digest(
                self.session_id(), form.get("AD", [""])[0]
            ):
                self.state.record_u30_power_post(mode, "400")
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

        if self.state.profile == "u30" and action in U30_SETTING_ACTIONS:
            expected_referer = f"http://{self.headers.get('Host', '')}/"
            expected_origin = expected_referer.rstrip("/")
            patch = self.state.u30_setting_patch(action, form)
            if not self.state.allow_u30_setting_writes:
                self.state.record_u30_setting_post(action, "403")
                self.send_payload(403, '{"result":"denied"}')
                return
            if (
                self.state.scenario not in U30_SETTING_SCENARIOS
                or patch is None
                or self.headers.get("Referer") != expected_referer
                or self.headers.get("Origin") != expected_origin
                or self.headers.get("X-Requested-With") != "XMLHttpRequest"
                or self.headers.get("Content-Type")
                != "application/x-www-form-urlencoded; charset=UTF-8"
            ):
                self.state.record_u30_setting_post(action, "400")
                self.send_payload(400, '{"result":"invalid_request"}')
                return
            if self.state.session_state(self.session_id(), "write") != "valid":
                self.state.record_u30_setting_post(action, "401")
                self.send_payload(401, '{"result":"session_expired"}')
                return

            scenario = self.state.scenario
            if scenario == "u30-setting-reject":
                self.state.record_u30_setting_post(action, "403")
                self.send_payload(403, '{"result":"denied"}')
                return
            if scenario == "u30-setting-timeout-before-apply":
                self.state.record_u30_setting_post(action, "TIMEOUT_BEFORE_APPLY")
                time.sleep(2)
                self.send_payload(200, '{"result":"success"}')
                return
            if scenario == "u30-setting-apply-then-timeout":
                self.state.record_u30_setting_post(
                    action, "APPLY_THEN_TIMEOUT", patch
                )
                time.sleep(2)
                self.send_payload(200, '{"result":"success"}')
                return

            applied = scenario not in {
                "u30-setting-malformed-unapplied",
                "u30-setting-empty-unapplied",
            }
            self.state.record_u30_setting_post(
                action, "200", patch if applied else None
            )
            if scenario in {
                "u30-setting-malformed-applied",
                "u30-setting-malformed-unapplied",
            }:
                self.send_payload(200, "not-json", "text/plain")
            elif scenario in {
                "u30-setting-empty-applied",
                "u30-setting-empty-unapplied",
            }:
                self.send_payload(200, "")
            else:
                self.send_payload(200, '{"result":"success"}')
            return

        if self.state.profile == "u30" and action in U30_ACTIONS:
            expected_referer = f"http://{self.headers.get('Host', '')}/"
            expected_origin = expected_referer.rstrip("/")
            if not self.state.allow_u30_action_writes:
                self.state.record_u30_action_post(action, "403")
                self.send_payload(403, '{"result":"denied"}')
                return
            if (
                self.state.scenario not in U30_ACTION_SCENARIOS
                or not self.state.u30_action_valid(action, form)
                or self.headers.get("Referer") != expected_referer
                or self.headers.get("Origin") != expected_origin
                or self.headers.get("X-Requested-With") != "XMLHttpRequest"
                or self.headers.get("Content-Type")
                != "application/x-www-form-urlencoded; charset=UTF-8"
            ):
                self.state.record_u30_action_post(action, "400")
                self.send_payload(400, '{"result":"invalid_request"}')
                return
            if self.state.session_state(self.session_id(), "write") != "valid":
                self.state.record_u30_action_post(action, "401")
                self.send_payload(401, '{"result":"session_expired"}')
                return

            scenario = self.state.scenario
            if scenario == "u30-action-reject":
                self.state.record_u30_action_post(action, "403")
                self.send_payload(403, '{"result":"denied"}')
                return
            if scenario == "u30-action-timeout-before-apply":
                self.state.record_u30_action_post(action, "TIMEOUT_BEFORE_APPLY")
                time.sleep(2)
                self.send_payload(200, '{"result":"success"}')
                return
            self.state.apply_u30_action(action, form)
            if scenario == "u30-action-apply-then-timeout":
                self.state.record_u30_action_post(action, "APPLY_THEN_TIMEOUT")
                time.sleep(2)
                self.send_payload(200, '{"result":"success"}')
                return
            self.state.record_u30_action_post(action, "200")
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

        if self.state.profile == "u30":
            expected_referer = f"http://{self.headers.get('Host', '')}/"
            expected_origin = expected_referer.rstrip("/")
            if (
                self.headers.get("Referer") != expected_referer
                or self.headers.get("Origin") != expected_origin
                or self.headers.get("X-Requested-With") != "XMLHttpRequest"
                or self.headers.get("Content-Type")
                != "application/x-www-form-urlencoded; charset=UTF-8"
            ):
                self.state.record("POST LOGIN 400")
                self.send_payload(400, '{"result":"invalid_request"}')
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
    parser.add_argument("--allow-u30-setting-writes", action="store_true")
    parser.add_argument("--allow-u30-action-writes", action="store_true")
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
        args.allow_u30_setting_writes,
        args.allow_u30_action_writes,
    )
    server = SimulatorServer((host, args.port), U25SHandler)
    server.simulator_state = state
    args.ready_file.write_text(str(server.server_address[1]), encoding="ascii")
    server.serve_forever()


if __name__ == "__main__":
    main()
