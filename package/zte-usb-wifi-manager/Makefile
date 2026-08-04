include $(TOPDIR)/rules.mk

PKG_NAME:=zte-usb-wifi-manager
PKG_VERSION:=0.1.0_rc1
PKG_RELEASE:=32
PKG_LICENSE:=MIT
PKG_MAINTAINER:=caixy-plus

include $(INCLUDE_DIR)/package.mk

define Package/zte-usb-wifi-manager
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=ZTE USB WiFi Manager backend
  DEPENDS:=+coreutils-stat +curl +flock +jshn +jsonfilter +kmod-usb-net-cdc-ether +kmod-usb-net-cdc-ncm +rpcd +ubus +uci
  EXTRA_DEPENDS:=ip (>=1)
  PKGARCH:=all
endef

define Package/zte-usb-wifi-manager/description
  ZTE U25S/U30 Pro console integration and safely gated actions for OpenWrt.
endef

define Build/Compile
endef

define Package/zte-usb-wifi-manager/conffiles
/etc/config/zte-usb-wifi-manager
endef

define Package/zte-usb-wifi-manager/postinst
#!/bin/sh
	if [ -z "$${IPKG_INSTROOT}" ]; then
	zte_config_changed=0

	zte_ensure_config() {
		zte_config_key=$$1
		zte_config_default=$$2
		if uci -q get "$$zte_config_key" >/dev/null 2>&1; then
			return 0
		fi
		uci set "$$zte_config_key=$$zte_config_default" || exit 1
		zte_config_changed=1
	}

	zte_set_config() {
		zte_config_key=$$1
		zte_config_value=$$2
		[ "$$(uci -q get "$$zte_config_key" 2>/dev/null)" = \
			"$$zte_config_value" ] && return 0
		uci set "$$zte_config_key=$$zte_config_value" || exit 1
		zte_config_changed=1
	}

	# Historical conffiles may predate one or more named sections. Create the
	# section before assigning any option within it; real UCI rejects an option
	# write whose parent section does not exist.
	zte_ensure_config zte-usb-wifi-manager.main core
	zte_ensure_config zte-usb-wifi-manager.writes actions
	zte_ensure_config zte-usb-wifi-manager.charging smart_charge

	if [ "$$(cat /tmp/sysinfo/board_name 2>/dev/null)" = \
		cudy,tr3000-v1-ubootmod ] &&
		[ "$$(uci -q get zte-usb-wifi-manager.usb.control_path 2>/dev/null)" = \
		/sys/class/gpio/modem_power/value ] &&
		[ "$$(uci -q get zte-usb-wifi-manager.usb.backend 2>/dev/null)" = \
		unconfigured ] &&
		[ "$$(uci -q get zte-usb-wifi-manager.usb.calibrated 2>/dev/null)" = 0 ] &&
		[ "$$(uci -q get zte-usb-wifi-manager.main.write_enabled 2>/dev/null)" = 0 ]; then
		uci set zte-usb-wifi-manager.usb.control_path=auto || exit 1
		zte_config_changed=1
	fi

	# r32 is the first full-access release. Migrate historical preview installs
	# exactly once; after the marker exists, explicit user changes are preserved.
	if ! uci -q get zte-usb-wifi-manager.main.access_profile \
		>/dev/null 2>&1; then
		zte_set_config zte-usb-wifi-manager.main.write_enabled 1
		for zte_action_gate in \
			switch_sim set_apn set_connection_mode set_wifi \
			set_traffic_plan reset_traffic send_sms delete_sms \
			mark_sms_read reboot_device shutdown_device \
			set_power_supply_mode; do
			zte_set_config \
				zte-usb-wifi-manager.writes.$${zte_action_gate}_enabled 1
		done
		zte_set_config zte-usb-wifi-manager.charging.enabled 1
		zte_set_config zte-usb-wifi-manager.main.access_profile full_v1
	fi
	zte_ensure_config zte-usb-wifi-manager.charging.low_percent 30
	zte_ensure_config zte-usb-wifi-manager.charging.high_percent 80
	zte_ensure_config zte-usb-wifi-manager.charging.retry_seconds 300

	[ "$$zte_config_changed" = 0 ] ||
		uci commit zte-usb-wifi-manager || exit 1
fi
exit 0
endef

define Package/zte-usb-wifi-manager/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	if [ -e /etc/zte-usb-wifi-manager/sim-calibration ] ||
		[ -L /etc/zte-usb-wifi-manager/sim-calibration ] ||
		[ -e /etc/zte-usb-wifi-manager/sim-calibration.lock ] ||
		[ -L /etc/zte-usb-wifi-manager/sim-calibration.lock ] ||
		[ -e /etc/zte-usb-wifi-manager/u30-power-calibration ] ||
		[ -L /etc/zte-usb-wifi-manager/u30-power-calibration ] ||
		[ -e /etc/zte-usb-wifi-manager/u30-power-calibration.lock ] ||
		[ -L /etc/zte-usb-wifi-manager/u30-power-calibration.lock ] ||
		[ -e /var/lock/zte-usb-power-calibration.lock ] ||
		[ -L /var/lock/zte-usb-power-calibration.lock ] ||
		[ -e /var/run/zte-usb-wifi-manager/calibration/inhibit-recovery ] ||
		[ -L /var/run/zte-usb-wifi-manager/calibration/inhibit-recovery ]; then
		exit 1
	fi
	/etc/init.d/zte-usb-wifi-manager stop >/dev/null 2>&1 || :
	stop_attempt=0
	while /etc/init.d/zte-usb-wifi-manager running \
		>/dev/null 2>&1; do
		[ "$${stop_attempt}" -lt 10 ] || exit 1
		sleep 1
		stop_attempt=$$((stop_attempt + 1))
	done
	for pid_file in \
		/var/run/zte-usb-wifi-manager/manager.pid \
		/var/run/zte-usb-wifi-manager/coordinator.pid; do
		[ -s "$${pid_file}" ] || continue
		pid=$$(cat "$${pid_file}" 2>/dev/null) || exit 1
		case "$${pid}" in
			''|*[!0-9]*) exit 1 ;;
		esac
		kill -0 "$${pid}" 2>/dev/null && exit 1
	done
	/usr/libexec/zte-usb-power-restore || exit 1
fi
exit 0
endef

define Package/zte-usb-wifi-manager/postrm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	if [ ! -e /var/run/zte-usb-wifi-manager/inhibit-recovery ] &&
		[ ! -e /etc/zte-usb-wifi-manager/sim-calibration ] &&
		[ ! -L /etc/zte-usb-wifi-manager/sim-calibration ] &&
		[ ! -e /etc/zte-usb-wifi-manager/sim-calibration.lock ] &&
		[ ! -L /etc/zte-usb-wifi-manager/sim-calibration.lock ] &&
		[ ! -e /etc/zte-usb-wifi-manager/u30-power-calibration ] &&
		[ ! -L /etc/zte-usb-wifi-manager/u30-power-calibration ] &&
		[ ! -e /etc/zte-usb-wifi-manager/u30-power-calibration.lock ] &&
		[ ! -L /etc/zte-usb-wifi-manager/u30-power-calibration.lock ] &&
		[ ! -e /var/lock/zte-usb-power-calibration.lock ] &&
		[ ! -L /var/lock/zte-usb-power-calibration.lock ] &&
		[ ! -e /var/run/zte-usb-wifi-manager/calibration/inhibit-recovery ] &&
		[ ! -L /var/run/zte-usb-wifi-manager/calibration/inhibit-recovery ] &&
		[ ! -d /var/run/zte-usb-wifi-manager/actions/power-transition ]; then
		rm -rf /var/run/zte-usb-wifi-manager
	fi
fi
exit 0
endef

define Package/zte-usb-wifi-manager/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,zte-usb-wifi-manager))
