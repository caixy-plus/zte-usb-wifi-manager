include $(TOPDIR)/rules.mk

PKG_NAME:=zte-usb-wifi-manager
PKG_VERSION:=0.1.0_rc1
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=caixy-plus

include $(INCLUDE_DIR)/package.mk

define Package/zte-usb-wifi-manager
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=ZTE USB WiFi Manager backend
  DEPENDS:=+coreutils-stat +curl +ip-tiny +jshn +rpcd +ubus +uci
  PKGARCH:=all
endef

define Package/zte-usb-wifi-manager/description
  Read-only framework and policy service for managing a ZTE U25S connected
  to OpenWrt over USB.
endef

define Build/Compile
endef

define Package/zte-usb-wifi-manager/conffiles
/etc/config/zte-usb-wifi-manager
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
