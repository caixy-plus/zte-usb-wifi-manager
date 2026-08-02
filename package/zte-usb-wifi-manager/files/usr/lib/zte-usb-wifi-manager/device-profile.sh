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

zte_device_profile_id() { printf '%s\n' "$ZTE_DEVICE_PROFILE_ID"; }
zte_device_profile_model() { printf '%s\n' "$ZTE_DEVICE_PROFILE_MODEL"; }
zte_device_profile_scheme() { printf '%s\n' "$ZTE_DEVICE_PROFILE_SCHEME"; }
zte_device_profile_tls_insecure() { printf '%s\n' "$ZTE_DEVICE_PROFILE_TLS_INSECURE"; }
zte_device_profile_login_required() { printf '%s\n' "$ZTE_DEVICE_PROFILE_LOGIN_REQUIRED"; }
zte_device_profile_driver() { printf '%s\n' "$ZTE_DEVICE_PROFILE_DRIVER"; }
