#!/bin/sh -e
#
# Copyright (C) 2021 pexcn <i@pexcn.me>
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#

# LAN_DG
# LAN_AC
# WAN_AC
# WAN_FW
# WAN_DG

_get_reserved_ipv4() {
  cat <<- EOF
	0.0.0.0/8
	10.0.0.0/8
	100.64.0.0/10
	127.0.0.0/8
	169.254.0.0/16
	172.16.0.0/12
	192.0.0.0/24
	192.0.2.0/24
	192.31.196.0/24
	192.52.193.0/24
	192.88.99.0/24
	192.168.0.0/16
	192.175.48.0/24
	198.18.0.0/15
	198.51.100.0/24
	203.0.113.0/24
	224.0.0.0/3
	EOF
}

_get_reserved_ipv6() {
  # TODO: redo
  cat <<- EOF
	::/127
	::ffff:0:0/96
	::ffff:0:0:0/96
	64:ff9b::/96
	100::/64
	2001::/32
	2001:20::/28
	2001:db8::/32
	2002::/16
	fc00::/7
	fe80::/10
	ff00::/8
	EOF
}

_add_prefix() {
  sed "s/^/$1/"
}

_remove_empty() {
  sed '/^[[:space:]]*$/d'
}

_remove_comment() {
  sed '/^#/ d'
}

_exist_var() {
  [ -n "$1" ]
}

_ipset_execute() {
  ipset -exist restore <<- EOF
	$@
	EOF
}

PREFIX_CHAIN="TRANSPROXY_"

log() {
  # 1:alert, 2:crit, 3:err, 4:warn, 5:notice, 6:info, 7:debug, 8:emerg
  logger -st transproxy[$$] -p $1 $2
}

print_usage() {

}

flush_rules() {
  # iptables
  iptables-save --counters | grep -v "$PREFIX_CHAIN" | iptables-restore --counters

  # route
  ip rule del fwmark 1 lookup 100 2>/dev/null || true
  ip route del local default dev lo table 100 2>/dev/null || true
  ip route flush table 100 2>/dev/null || true

  # ipset
  for name in $(ipset -n list | grep "$PREFIX_CHAIN"); do
    ipset flush $name 2>/dev/null || true
    ipset destroy $name 2>/dev/null || true
  done
}

init_ipset() {
  # TODO: use one line
  # create
  _ipset_execute create transproxy_src_direct hash:ip hashsize 64 family inet
  _ipset_execute create transproxy_src_global hash:ip hashsize 64 family inet
  _ipset_execute create transproxy_src_control hash:ip hashsize 64 family inet
  _ipset_execute create transproxy_dst_special hash:net hashsize 64 family inet
  _ipset_execute create transproxy_dst_direct hash:net hashsize 64 family inet
  _ipset_execute create transproxy_dst_normal hash:net hashsize 64 family inet

  # special
  _ipset_execute "$(_get_reserved_ipv4 | _add_prefix 'add transproxy_dst_direct ')"

  # src sets
  _ipset_execute "$(cat /etc/transproxy/src-direct.txt | _remove_empty | _remove_comment | _add_prefix 'add transproxy_src_direct ')"
  _ipset_execute "$(cat /etc/transproxy/src-global.txt | _remove_empty | _remove_comment | _add_prefix 'add transproxy_src_global ')"
  _ipset_execute "$(cat /etc/transproxy/src-normal.txt | _remove_empty | _remove_comment | _add_prefix 'add transproxy_src_normal ')"

  # dst sets
  _ipset_execute "$(cat /etc/transproxy/dst-global.txt | _remove_empty | _remove_comment | _add_prefix 'add transproxy_dst_reserved ')"
  _ipset_execute "$(cat /etc/transproxy/dst-direct.txt | _remove_empty | _remove_comment | _add_prefix 'add transproxy_dst_direct ')"
  _ipset_execute "$(cat /etc/transproxy/dst-normal.txt | _remove_empty | _remove_comment | _add_prefix 'add transproxy_dst_normal ')"
}

gen_prerouting_rules() {
  local proto="$1"
  if _exist_var "$INTERFACES"; then
    for interface in $INTERFACES; do
      echo -I PREROUTING 1 -i $interface -p $proto -j SS_SPEC_LAN_DG
    done
  else
    echo -I PREROUTING 1 -p $proto -j SS_SPEC_LAN_DG
  fi
}

iptables_nat() {
  local table="$1"
  local proto="$2"

  iptables-restore -n <<- EOF
	*$table

	:TRANSPROXY_LAN_PREPARE - [0:0]
	:TRANSPROXY_LAN_CONTROL - [0:0]
	:TRANSPROXY_WAN_CONTROL - [0:0]
	:TRANSPROXY_WAN_FORWARD - [0:0]

	# PREPARE
	-A TRANSPROXY_LAN_PREPARE -m set --match-set transproxy_dst_special dst -j RETURN
	-A TRANSPROXY_LAN_PREPARE -p $proto $IPTABLES_EXTRA_ARGS -j TRANSPROXY_LAN_CONTROL

	# LAN
	-A TRANSPROXY_LAN_CONTROL -m set --match-set transproxy_src_direct src -j RETURN
	-A TRANSPROXY_LAN_CONTROL -m set --match-set transproxy_src_forward src -j TRANSPROXY_WAN_FORWARD
	-A TRANSPROXY_LAN_CONTROL -m set --match-set transproxy_src_control src -j TRANSPROXY_WAN_CONTROL
	-A TRANSPROXY_LAN_CONTROL -j $LAN_DEFAULT_TARGET

	# WAN
	-A TRANSPROXY_WAN_CONTROL -m set --match-set transproxy_dst_direct dst -j RETURN
	-A TRANSPROXY_WAN_CONTROL -m set --match-set transproxy_dst_global dst -j TRANSPROXY_WAN_FORWARD
	-A TRANSPROXY_WAN_CONTROL -j $WAN_DEFAULT_TARGET

	COMMIT
	EOF
}

iptables_mangle() {
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -r|--remote)
        REMOTE_ADDR="$2"
        shift 2
        ;;
      -p|--port)
        REMOTE_PORT="$2"
        shift 2
        ;;
      --dst-forward-recentrst)
        DST=1
        shift 1
        ;;
      -h|--help)
        print_usage
        exit 0
        ;;
      *)
        echo "unknown option $1"
        return 1
        ;;
    esac
  done
}

main() {
	flush_rules && ipset_init && iptables_nat && iptables_mangle
	RET=$?
	[ "$RET" = 0 ] ||  log 3 "Start failed!"
	exit $RET
}

parse_args "$@"
flush_rules
init_ipset
