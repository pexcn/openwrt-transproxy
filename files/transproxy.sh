#!/bin/sh
#
# Copyright (C) 2021-2022 Sing Yu Chan <i@pexcn.me>
#
# The design idea was derived from ss-rules by Jian Chang <aa65535@live.com> and Yousong Zhou <yszhou4tech@gmail.com>
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#

_add_prefix() {
  sed "s/^/$1/"
}

_remove_empty() {
  sed '/^[[:space:]]*$/d'
}

_remove_comment() {
  sed '/^#/ d'
}

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

#log() {
#  # 1:alert, 2:crit, 3:err, 4:warn, 5:notice, 6:info, 7:debug, 8:emerg
#  logger -st transproxy[$$] -p $1 $2
#}

print_usage() {
  echo "TODO..."
}

flush_transproxy() {
  iptables-save --counters | grep -v "TRANSPROXY_" | iptables-restore --counters

  ip rule del fwmark 1 lookup 100 2>/dev/null || true
  ip route del local default dev lo table 100 2>/dev/null || true
  ip route flush table 100 2>/dev/null || true

  for name in $(ipset -n list | grep "transproxy_"); do
    ipset flush $name 2>/dev/null || true
    ipset destroy $name 2>/dev/null || true
  done
}

init_ipset() {
  ipset -exist restore <<- EOF
	create transproxy_src_direct hash:ip hashsize 64 family inet
	create transproxy_src_proxy hash:ip hashsize 64 family inet
	create transproxy_src_checkdst hash:ip hashsize 64 family inet
	create transproxy_dst_direct hash:net hashsize 64 family inet
	create transproxy_dst_proxy hash:net hashsize 64 family inet
	create transproxy_dst_special hash:net hashsize 64 family inet
	$(cat /etc/transproxy/src-direct.txt | _remove_empty | _remove_comment | _add_prefix 'add transproxy_src_direct ')
	$(cat /etc/transproxy/src-proxy.txt | _remove_empty | _remove_comment | _add_prefix 'add transproxy_src_proxy ')
	$(cat /etc/transproxy/src-checkdst.txt | _remove_empty | _remove_comment | _add_prefix 'add transproxy_src_checkdst ')
	$(cat /etc/transproxy/dst-direct.txt | _remove_empty | _remove_comment | _add_prefix 'add transproxy_dst_direct ')
	$(cat /etc/transproxy/dst-proxy.txt | _remove_empty | _remove_comment | _add_prefix 'add transproxy_dst_proxy ')
	$(_get_reserved_ipv4 | _add_prefix 'add transproxy_dst_special ')
	EOF
}

apply_iptables_rules() {
  local table="$1"
  local proto="$2"

  iptables-restore -n <<- EOF
	*$table

	:TRANSPROXY_SRC_PREPARE - [0:0]
	:TRANSPROXY_SRC_AC - [0:0]
	:TRANSPROXY_DST_AC - [0:0]
	:TRANSPROXY_DST_FORWARD - [0:0]

	# PREPARE
	-A TRANSPROXY_SRC_PREPARE -m set --match-set transproxy_dst_special dst -j RETURN
	-A TRANSPROXY_SRC_PREPARE -p $proto $IPTABLES_EXTRA_ARGS -j TRANSPROXY_SRC_AC

	# SRC
	-A TRANSPROXY_SRC_AC -m set --match-set transproxy_src_direct src -j RETURN
	-A TRANSPROXY_SRC_AC -m set --match-set transproxy_src_proxy src -j TRANSPROXY_DST_FORWARD
	-A TRANSPROXY_SRC_AC -m set --match-set transproxy_src_checkdst src -j TRANSPROXY_DST_AC
	-A TRANSPROXY_SRC_AC -j $SRC_DEFAULT_TARGET

	# DST
	-A TRANSPROXY_DST_AC -m set --match-set transproxy_dst_direct dst -j RETURN
	-A TRANSPROXY_DST_AC -m set --match-set transproxy_dst_proxy dst -j TRANSPROXY_DST_FORWARD
	-A TRANSPROXY_DST_AC -j $DST_DEFAULT_TARGET

	$(gen_prerouting_rules $proto)

	COMMIT
	EOF
}

gen_prerouting_rules() {
  local proto="$1"
  if [ -z "$INTERFACES" ]; then
    echo -I PREROUTING 1 -p $proto -j TRANSPROXY_SRC_PREPARE
  else
    for interface in $INTERFACES; do
      echo -I PREROUTING 1 -i $interface -p $proto -j TRANSPROXY_SRC_PREPARE
    done
  fi
}

init_iptables_tcp() {
  apply_iptables_rules nat tcp
  iptables -t nat -A TRANSPROXY_DST_FORWARD -p tcp -j REDIRECT --to-ports $REMOTE_PORT || return 1

  # TODO: refine by https://github.com/openwrt/packages/blob/e60310eb2ebf256efb60c6fb6841c3edb30467dc/net/shadowsocks-libev/files/ss-rules
  if [ "$SELF_PROXY" = 1 ]; then
    iptables -t nat -N TRANSPROXY_DST_PREPARE
    iptables -t nat -A TRANSPROXY_DST_PREPARE -m set --match-set transproxy_dst_special dst -j RETURN
    iptables -t nat -A TRANSPROXY_DST_PREPARE -p tcp $IPTABLES_EXTRA_ARGS -j $DST_DEFAULT_TARGET
    iptables -t nat -I OUTPUT 1 -p tcp -j TRANSPROXY_DST_PREPARE
  fi
  return $?
}

init_iptables_udp() {
  ip rule add fwmark 1 lookup 100
  ip route add local default dev lo table 100
  apply_iptables_rules mangle udp
  iptables -t mangle -A TRANSPROXY_DST_FORWARD -p udp -j TPROXY --on-ip $UDP_REMOTE_ADDR --on-port $UDP_REMOTE_PORT --tproxy-mark 1

  # TODO: refine by https://github.com/openwrt/packages/blob/e60310eb2ebf256efb60c6fb6841c3edb30467dc/net/shadowsocks-libev/files/ss-rules
  if [ "$SELF_PROXY" = 1 ]; then
    iptables -t mangle -N TRANSPROXY_DST_PREPARE
    iptables -t mangle -A TRANSPROXY_DST_PREPARE -m set --match-set transproxy_dst_special -j RETURN
    iptables -t mangle -A TRANSPROXY_DST_PREPARE -m set --match-set transproxy_dst_proxy dst -j MARK --set-mark 1
    if [ "$DST_DEFAULT_TARGET" = "TRANSPROXY_DST_AC" ]; then
      iptables -t mangle -A TRANSPROXY_DST_PREPARE -m set --match-set transproxy_dst_direct dst -j RETURN
    fi
    iptables -t mangle -A TRANSPROXY_DST_PREPARE -p udp $IPTABLES_EXTRA_ARGS -j MARK --set-mark 1
    iptables -t mangle -I OUTPUT 1 -p udp -j TRANSPROXY_DST_PREPARE
  fi
  return $?
}

parse_args() {
  SRC_DEFAULT_TARGET=TRANSPROXY_DST_AC
  DST_DEFAULT_TARGET=TRANSPROXY_DST_FORWARD


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
      -R|--udp-remote)
        UDP_REMOTE_ADDR="$2"
        shift 2
        ;;
      -P|--udp-port)
        UDP_REMOTE_PORT="$2"
        shift 2
        ;;
      --self-proxy)
        SELF_PROXY=1;
        shift 1
        ;;
#      --ipv4-only)
#        IPV4_ONLY=1
#        shift 1
#        ;;
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

parse_args "$@"
flush_transproxy
init_ipset
init_iptables_tcp
init_iptables_udp
