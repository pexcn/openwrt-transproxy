#!/bin/sh -e
#
# Copyright (C) 2021 pexcn <i@pexcn.me>
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#

log() {
  # 1:alert, 2:crit, 3:err, 4:warn, 5:notice, 6:info, 7:debug, 8:emerg
  logger -st tp-rules[$$] -p $1 $2
}

gen_ignore_ip_list() {
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
}

flush_rules() {
}

ipset_init() {
}

iptables_nat() {
}

iptables_mangle() {
}

parse_args() {
  while getopts ":r" arg; do
    case "$arg" in
      s)
        server=
  done
}

while getopts ":s:l:S:L:B:b:W:w:I:d:a:e:oOuUfh" arg; do
	case "$arg" in
		s)
			server=$(for ip in $OPTARG; do echo $ip; done)
			;;
		l)
			local_port=$OPTARG
			;;
		S)
			SERVER=$(for ip in $OPTARG; do echo $ip; done)
			;;
		L)
			LOCAL_PORT=$OPTARG
			;;
		B)
			WAN_BP_LIST=$OPTARG
			;;
		b)
			WAN_BP_IP=$OPTARG
			;;
		W)
			WAN_FW_LIST=$OPTARG
			;;
		w)
			WAN_FW_IP=$OPTARG
			;;
		I)
			IFNAMES=$OPTARG
			;;
		d)
			LAN_TARGET=$OPTARG
			;;
		a)
			LAN_HOSTS=$OPTARG
			;;
		e)
			EXT_ARGS=$OPTARG
			;;
		o)
			OUTPUT=SS_SPEC_WAN_AC
			;;
		O)
			OUTPUT=SS_SPEC_WAN_FW
			;;
		u)
			TPROXY=1
			;;
		U)
			TPROXY=2
			;;
		f)
			flush_rules
			exit 0
			;;
		h)
			usage 0
			;;
	esac
done


main() {
  parse_args
	flush_rules && ipset_init && iptables_nat && iptables_mangle
	RET=$?
	[ "$RET" = 0 ] ||  log 3 "Start failed!"
	exit $RET
}

main
