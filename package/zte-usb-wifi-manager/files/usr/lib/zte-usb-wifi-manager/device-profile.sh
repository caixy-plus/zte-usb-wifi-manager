#!/bin/sh

zte_device_profile_clear() {
	ZTE_DEVICE_PROFILE_ID=
	ZTE_DEVICE_PROFILE_MODEL=
	ZTE_DEVICE_PROFILE_SCHEME=
	ZTE_DEVICE_PROFILE_TLS_INSECURE=
	ZTE_DEVICE_PROFILE_LOGIN_REQUIRED=
	ZTE_DEVICE_PROFILE_DRIVER=
}

zte_device_profile_set_u25s() {
	ZTE_DEVICE_PROFILE_ID=zte_u25s
	ZTE_DEVICE_PROFILE_MODEL=U25S
	ZTE_DEVICE_PROFILE_SCHEME=http
	ZTE_DEVICE_PROFILE_TLS_INSECURE=0
	ZTE_DEVICE_PROFILE_LOGIN_REQUIRED=1
	ZTE_DEVICE_PROFILE_DRIVER=kmod-usb-net-cdc-ether
}

zte_device_profile_set_u30() {
	ZTE_DEVICE_PROFILE_ID=zte_u30
	ZTE_DEVICE_PROFILE_MODEL='U30 Pro'
	ZTE_DEVICE_PROFILE_SCHEME=https
	ZTE_DEVICE_PROFILE_TLS_INSECURE=1
	ZTE_DEVICE_PROFILE_LOGIN_REQUIRED=0
	ZTE_DEVICE_PROFILE_DRIVER=kmod-usb-net-cdc-ncm
}

zte_device_profile_select_named() {
	zte_device_profile_clear
	case ${1-} in
		zte_u25s) zte_device_profile_set_u25s ;;
		zte_u30) zte_device_profile_set_u30 ;;
		*) return 1 ;;
	esac
}

zte_device_profile_select() {
	zte_device_profile_clear
	case ${1-}:${2-}:${3-} in
		19d2:1354:'U30 Pro') zte_device_profile_set_u30 ;;
		*) return 1 ;;
	esac
}

# Select a profile from an exact USB sysfs identity. Unknown or incomplete
# devices are never guessed from a product-name substring.
zte_device_profile_detect() {
	_zte_profile_sysfs=${1-/sys/bus/usb/devices}
	zte_device_profile_clear
	[ -d "$_zte_profile_sysfs" ] || return 1
	for _zte_profile_device in "$_zte_profile_sysfs"/*; do
		[ -f "$_zte_profile_device/idVendor" ] || continue
		[ -f "$_zte_profile_device/idProduct" ] || continue
		[ -f "$_zte_profile_device/product" ] || continue
		_zte_profile_vendor=$(cat "$_zte_profile_device/idVendor" 2>/dev/null) ||
			continue
		_zte_profile_product_id=$(cat \
			"$_zte_profile_device/idProduct" 2>/dev/null) || continue
		_zte_profile_product=$(cat "$_zte_profile_device/product" 2>/dev/null) ||
			continue
		if zte_device_profile_select \
			"$_zte_profile_vendor" "$_zte_profile_product_id" \
			"$_zte_profile_product"; then
			return 0
		fi
	done
	zte_device_profile_clear
	return 1
}

# Select the USB identity that owns one specific network interface. netifd's
# configured device, not an unrelated matching modem elsewhere on the bus,
# is the authority for enabling the product profile.
zte_device_profile_detect_netdev() {
	_zte_profile_net_root=${1-/sys/class/net}
	_zte_profile_netdev=${2-}
	zte_device_profile_clear
	case $_zte_profile_netdev in
		''|*[!A-Za-z0-9_.:-]*) return 1 ;;
	esac
	_zte_profile_net_link=$_zte_profile_net_root/$_zte_profile_netdev/device
	[ -e "$_zte_profile_net_link" ] || return 1
	_zte_profile_net_path=$(
		cd -P "$_zte_profile_net_link" 2>/dev/null && pwd -P
	) || return 1

	while [ -n "$_zte_profile_net_path" ] &&
		[ "$_zte_profile_net_path" != / ]; do
		if [ -f "$_zte_profile_net_path/idVendor" ] &&
			[ -f "$_zte_profile_net_path/idProduct" ] &&
			[ -f "$_zte_profile_net_path/product" ]; then
			_zte_profile_vendor=$(cat \
				"$_zte_profile_net_path/idVendor" 2>/dev/null) || break
			_zte_profile_product_id=$(cat \
				"$_zte_profile_net_path/idProduct" 2>/dev/null) || break
			_zte_profile_product=$(cat \
				"$_zte_profile_net_path/product" 2>/dev/null) || break
			if zte_device_profile_select \
				"$_zte_profile_vendor" "$_zte_profile_product_id" \
				"$_zte_profile_product"; then
				return 0
			fi
			break
		fi
		_zte_profile_parent=${_zte_profile_net_path%/*}
		[ "$_zte_profile_parent" != "$_zte_profile_net_path" ] || break
		_zte_profile_net_path=$_zte_profile_parent
	done
	zte_device_profile_clear
	return 1
}

zte_device_profile_id() { printf '%s\n' "$ZTE_DEVICE_PROFILE_ID"; }
zte_device_profile_model() { printf '%s\n' "$ZTE_DEVICE_PROFILE_MODEL"; }
zte_device_profile_scheme() { printf '%s\n' "$ZTE_DEVICE_PROFILE_SCHEME"; }
zte_device_profile_tls_insecure() { printf '%s\n' "$ZTE_DEVICE_PROFILE_TLS_INSECURE"; }
zte_device_profile_login_required() { printf '%s\n' "$ZTE_DEVICE_PROFILE_LOGIN_REQUIRED"; }
zte_device_profile_driver() { printf '%s\n' "$ZTE_DEVICE_PROFILE_DRIVER"; }
