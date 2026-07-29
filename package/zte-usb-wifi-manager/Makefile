include $(TOPDIR)/rules.mk

PKG_NAME:=zte-usb-wifi-manager
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=caixy-plus

include $(INCLUDE_DIR)/package.mk

define Package/zte-usb-wifi-manager
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=ZTE USB WiFi Manager backend
  DEPENDS:=+curl +jshn +rpcd +ubus +uci
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

define Package/zte-usb-wifi-manager/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,zte-usb-wifi-manager))
