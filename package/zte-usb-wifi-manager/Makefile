include $(TOPDIR)/rules.mk

PKG_NAME:=zte-usb-wifi-manager
PKG_VERSION:=0.1.0_rc1
PKG_RELEASE:=34
PKG_LICENSE:=MIT
PKG_MAINTAINER:=caixy-plus

include $(INCLUDE_DIR)/package.mk

define Package/zte-usb-wifi-manager
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=ZTE U30 smart charge manager backend
  DEPENDS:=+coreutils-stat +curl +flock +jshn +jsonfilter +kmod-usb-net-cdc-ncm +rpcd +ubus +uci
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
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d
	$(INSTALL_CONF) ./files/etc/config/zte-usb-wifi-manager \
		$(1)/etc/config/zte-usb-wifi-manager
	$(INSTALL_BIN) ./files/etc/init.d/zte-usb-wifi-manager \
		$(1)/etc/init.d/zte-usb-wifi-manager

	$(INSTALL_DIR) $(1)/usr/lib/zte-usb-wifi-manager
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/validation.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/validation.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/json.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/json.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/http.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/http.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/credentials.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/credentials.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/session.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/session.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/smart-charge-policy.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/smart-charge-policy.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/smart-charge-state.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/smart-charge-state.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/event-log.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/event-log.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/charging-transaction.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/charging-transaction.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/actions.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/actions.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/action-executor.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/action-executor.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/snapshot.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/snapshot.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/netifd-adapter.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/netifd-adapter.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/device-profile.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/device-profile.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s-metadata.sh
	$(INSTALL_DATA) ./files/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh \
		$(1)/usr/lib/zte-usb-wifi-manager/adapter-zte-u25s.sh

	$(INSTALL_DIR) $(1)/usr/libexec/rpcd $(1)/usr/sbin
	$(INSTALL_BIN) ./files/usr/libexec/rpcd/zte_usb_wifi \
		$(1)/usr/libexec/rpcd/zte_usb_wifi
	$(INSTALL_BIN) ./files/usr/sbin/zte-usb-wifi-managerd \
		$(1)/usr/sbin/zte-usb-wifi-managerd
endef

$(eval $(call BuildPackage,zte-usb-wifi-manager))
