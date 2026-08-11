include $(TOPDIR)/rules.mk

PKG_NAME:=zte-usb-wifi-manager
PKG_VERSION:=0.1.0_rc1
PKG_RELEASE:=33
PKG_LICENSE:=MIT
PKG_MAINTAINER:=caixy-plus

include $(INCLUDE_DIR)/package.mk

define Package/zte-usb-wifi-manager
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=ZTE U30 smart charge manager backend
  DEPENDS:=+coreutils-stat +curl +flock +jshn +jsonfilter +kmod-usb-net-cdc-ether +kmod-usb-net-cdc-ncm +rpcd +ubus +uci
  EXTRA_DEPENDS:=ip (>=1)
  PKGARCH:=all
endef

define Package/zte-usb-wifi-manager/description
  ZTE U30 Pro smart charging and read-only device status for OpenWrt.
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

	zte_ensure_config zte-usb-wifi-manager.main core
	zte_ensure_config zte-usb-wifi-manager.writes actions
	zte_ensure_config zte-usb-wifi-manager.charging smart_charge
	zte_ensure_config zte-usb-wifi-manager.zte device

	# charge_v1: smart-charge product only. Migrate once from full console
	# installs; later explicit user changes are preserved.
	if [ "$$(uci -q get zte-usb-wifi-manager.main.access_profile 2>/dev/null)" != \
		charge_v1 ]; then
		zte_set_config zte-usb-wifi-manager.main.write_enabled 1
		zte_set_config zte-usb-wifi-manager.writes.set_power_supply_mode_enabled 1
		for zte_action_gate in \
			switch_sim set_apn set_connection_mode set_wifi \
			set_traffic_plan reset_traffic send_sms delete_sms \
			mark_sms_read reboot_device shutdown_device; do
			if uci -q get \
				"zte-usb-wifi-manager.writes.$${zte_action_gate}_enabled" \
				>/dev/null 2>&1; then
				zte_set_config \
					"zte-usb-wifi-manager.writes.$${zte_action_gate}_enabled" 0
			fi
		done
		zte_set_config zte-usb-wifi-manager.charging.enabled 1
		zte_set_config zte-usb-wifi-manager.zte.adapter zte_u30
		zte_set_config zte-usb-wifi-manager.main.access_profile charge_v1
	fi
	zte_ensure_config zte-usb-wifi-manager.charging.low_percent 30
	zte_ensure_config zte-usb-wifi-manager.charging.high_percent 80
	zte_ensure_config zte-usb-wifi-manager.charging.retry_seconds 300
	zte_ensure_config zte-usb-wifi-manager.writes.set_power_supply_mode_enabled 1

	[ "$$zte_config_changed" = 0 ] ||
		uci commit zte-usb-wifi-manager || exit 1
fi
exit 0
endef

define Package/zte-usb-wifi-manager/prerm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	/etc/init.d/zte-usb-wifi-manager stop >/dev/null 2>&1 || :
	stop_attempt=0
	while /etc/init.d/zte-usb-wifi-manager running \
		>/dev/null 2>&1; do
		[ "$${stop_attempt}" -lt 10 ] || exit 1
		sleep 1
		stop_attempt=$$((stop_attempt + 1))
	done
	for pid_file in \
		/var/run/zte-usb-wifi-manager/manager.pid; do
		[ -s "$${pid_file}" ] || continue
		pid=$$(cat "$${pid_file}" 2>/dev/null) || exit 1
		case "$${pid}" in
			''|*[!0-9]*) exit 1 ;;
		esac
		kill -0 "$${pid}" 2>/dev/null && exit 1
	done
fi
exit 0
endef

define Package/zte-usb-wifi-manager/postrm
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ]; then
	rm -rf /var/run/zte-usb-wifi-manager
fi
exit 0
endef

define Package/zte-usb-wifi-manager/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,zte-usb-wifi-manager))
