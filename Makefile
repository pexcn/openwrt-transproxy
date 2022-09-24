include $(TOPDIR)/rules.mk

PKG_NAME:=transproxy
PKG_VERSION:=0.2.11
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/pexcn/transproxy.git
PKG_SOURCE_VERSION:=9033be107229e437ab5585e92b2b2059114c9d5a
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION)-$(PKG_SOURCE_VERSION).tar.gz
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)-$(PKG_SOURCE_VERSION)
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)/$(PKG_SOURCE_SUBDIR)

PKG_LICENSE:=GPL-3.0
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=pexcn <i@pexcn.me>

include $(INCLUDE_DIR)/package.mk

define Package/transproxy
	SECTION:=net
	CATEGORY:=Network
	TITLE:=A bridge of openwrt and transparent proxy.
	URL:=https://github.com/pexcn/transproxy
	DEPENDS:=+!ip:ip-tiny +ipset +iptables +ip6tables +iptables-mod-tproxy
endef

define Package/transproxy/description
A bridge of openwrt and transparent proxy.
endef

define Package/transproxy/conffiles
/etc/config/transproxy
/etc/transproxy/src-direct.txt
/etc/transproxy/src-proxy.txt
/etc/transproxy/src-normal.txt
/etc/transproxy/dst-direct.txt
/etc/transproxy/dst-proxy.txt
/etc/transproxy/src-direct6.txt
/etc/transproxy/src-proxy6.txt
/etc/transproxy/src-normal6.txt
/etc/transproxy/dst-direct6.txt
/etc/transproxy/dst-proxy6.txt
/etc/transproxy/chnroute.txt
/etc/transproxy/chnroute6.txt
endef

define Build/Compile
	true
endef

define Package/transproxy/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/transproxy $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/transproxy6 $(1)/usr/bin
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) files/transproxy.init $(1)/etc/init.d/transproxy
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) files/transproxy.config $(1)/etc/config/transproxy
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) files/transproxy.defaults $(1)/etc/uci-defaults/99-transproxy
	$(INSTALL_DIR) $(1)/usr/share/transproxy
	$(INSTALL_DATA) files/transproxy.firewall $(1)/usr/share/transproxy/firewall.include
	$(INSTALL_DIR) $(1)/etc/sysctl.d
	$(INSTALL_DATA) files/transproxy.sysctl $(1)/etc/sysctl.d/99-transproxy.conf
	$(INSTALL_DIR) $(1)/etc/transproxy
	$(INSTALL_DATA) files/rules/src-direct.txt $(1)/etc/transproxy
	$(INSTALL_DATA) files/rules/src-proxy.txt $(1)/etc/transproxy
	$(INSTALL_DATA) files/rules/src-normal.txt $(1)/etc/transproxy
	$(INSTALL_DATA) files/rules/dst-direct.txt $(1)/etc/transproxy
	$(INSTALL_DATA) files/rules/dst-proxy.txt $(1)/etc/transproxy
	$(INSTALL_DATA) files/rules/src-direct6.txt $(1)/etc/transproxy
	$(INSTALL_DATA) files/rules/src-proxy6.txt $(1)/etc/transproxy
	$(INSTALL_DATA) files/rules/src-normal6.txt $(1)/etc/transproxy
	$(INSTALL_DATA) files/rules/dst-direct6.txt $(1)/etc/transproxy
	$(INSTALL_DATA) files/rules/dst-proxy6.txt $(1)/etc/transproxy
	$(INSTALL_DATA) files/rules/chnroute.txt $(1)/etc/transproxy
	$(INSTALL_DATA) files/rules/chnroute6.txt $(1)/etc/transproxy
endef

define Package/transproxy/postrm
#!/bin/sh
rmdir --ignore-fail-on-non-empty /etc/transproxy /usr/share/transproxy
uci -q delete firewall.transproxy
uci commit firewall
exit 0
endef

$(eval $(call BuildPackage,transproxy))
