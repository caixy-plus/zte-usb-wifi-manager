include $(TOPDIR)/rules.mk

PKG_NAME:=zte-usb-wifi-manager
PKG_VERSION:=0.1.0_rc1
PKG_RELEASE:=10
PKG_LICENSE:=MIT
PKG_MAINTAINER:=caixy-plus

include $(INCLUDE_DIR)/package.mk

define Package/zte-usb-wifi-manager
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=ZTE USB WiFi Manager backend
  DEPENDS:=+coreutils-stat +curl +jshn +rpcd +ubus +uci
  EXTRA_DEPENDS:=ip (>=1)
  PKGARCH:=all
endef

define Package/zte-usb-wifi-manager/description
  Safety-gated monitoring, device actions, and battery policy service for a
  ZTE U25S connected to OpenWrt over USB.
endef

define Build/Compile
endef

define Package/zte-usb-wifi-manager/conffiles
/etc/config/zte-usb-wifi-manager
endef

define Package/zte-usb-wifi-manager/postinst
#!/bin/sh
if [ -z "$${IPKG_INSTROOT}" ] &&
	[ "$$(cat /tmp/sysinfo/board_name 2>/dev/null)" = \
		cudy,tr3000-v1-ubootmod ] &&
	[ "$$(uci -q get zte-usb-wifi-manager.usb.control_path 2>/dev/null)" = \
		/sys/class/gpio/modem_power/value ] &&
	[ "$$(uci -q get zte-usb-wifi-manager.usb.backend 2>/dev/null)" = \
		unconfigured ] &&
	[ "$$(uci -q get zte-usb-wifi-manager.usb.calibrated 2>/dev/null)" = 0 ] &&
	[ "$$(uci -q get zte-usb-wifi-manager.main.write_enabled 2>/dev/null)" = 0 ]; then
	uci set zte-usb-wifi-manager.usb.control_path=auto || exit 1
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
