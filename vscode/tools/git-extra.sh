#!/bin/bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Git-Gerrit tags
# Requires:
#   https://github.com/fbzhong/git-gerrit

set -euo pipefail

function _error() {
	if [[ "$1" != "" ]]; then
		echo >&2 "ERROR: $1"
	fi
	return 1
}

function _debug() {
	if [[ "$1" != "" ]]; then
		echo >&2 "DEBUG: $1"
	fi
	return 0
}

TTY_PORT=""
TTY_SPEED="115200"
TTY_PICOCOM="picocom"
TTY_LOGIN="root"
TTY_PASS="root"
TTY_DELAY="200" # milliseconds
TTY_TX_TEXT=""
TTY_RX_TEXT=""

function _tty_resolve_port() {
	if [[ "$TTY_PORT" == "" ]]; then
		TTY_PORT="$(find /dev -name "ttyUSB*" -print -quit)"
		if [[ "$TTY_PORT" == "" ]]; then
			_fatal "Unable to find USB TTY port"
		fi
	fi
}

function _tty_shell() {
	_tty_resolve_port
	local format=""
	for ((i = 0; i <= $#; i++)); do
		format="$format%s\r"
	done
	# shellcheck disable=SC2059
	TTY_TX_TEXT="$(printf "$format" "$@")"
	_debug "TTY: send: -->$TTY_TX_TEXT<--"
	TTY_RX_TEXT=$("$TTY_PICOCOM" -qrb "$TTY_SPEED" -x "$TTY_DELAY" "$TTY_PORT" -t "$TTY_TX_TEXT" 2>&1)
	_debug "TTY: recv: -->$TTY_RX_TEXT<--"
	echo "$TTY_RX_TEXT"
}

function _tty_promt() {
	_tty_resolve_port
	local format=""
	for ((i = 0; i <= $#; i++)); do
		format="$format%s\r"
	done
	# shellcheck disable=SC2059
	TTY_TX_TEXT="$(printf "$format" "$@")"
	_debug "TTY: send: -->$TTY_TX_TEXT<--"
	"$TTY_PICOCOM" -qrb "$TTY_SPEED" "$TTY_PORT" -t "$TTY_TX_TEXT"
	#TTY_RX_TEXT=$("$TTY_PICOCOM" -qrb "$TTY_SPEED" -x "$TTY_DELAY" "$TTY_PORT" -t "$TTY_TX_TEXT" 2>&1)
}

function _tty_exchange() {
	[[ "$(_tty_shell "$1")" == *"$2"* ]]
}

function _tty_last() {
	[[ "$TTY_RX_TEXT" == *"$1"* ]]
}

function _tty_logout() {
	if _tty_exchange "" "#"; then
		if _tty_exchange "exit" "exit not allowed"; then
			_debug "TTY: Booting u-boot"
			_tty_shell "boot" >/dev/null 2>&1
		else
			_debug "TTY: Logging out"
			_tty_shell "" >/dev/null 2>&1
		fi
	fi
}

function _tty_try_login() {
	case $(_tty_shell "") in
	*"login:"*)
		_debug "TTY: got login prompt"
		if _tty_exchange "$TTY_LOGIN" "Password:"; then
			_debug "TTY: got password prompt"
			_tty_exchange "$TTY_PASS" "#"
			return 0
		fi
		;;
	*"#"*)
		_debug "TTY: got command prompt"
		return 0
		;;
	*) return 1 ;;
	esac
	return 1
}

function _tty_login() {
	if _tty_try_login; then
		return 0
	fi
	_tty_logout
	if _tty_try_login; then
		return 0
	fi
	return 1
}

function _tty_peek_ip() {
	if ! _tty_login; then
		return 1
	fi
	local oldifs text lines=() line match
	${IFS+"false"} && unset oldifs || oldifs="$IFS"
	# shellcheck disable=SC2207
	IFS=$'\r' lines=($(_tty_shell "ifconfig | grep 'inet addr:' | grep 'Bcast:'"))
	${oldifs+"false"} && unset IFS || IFS="$oldifs"
	for line in "${lines[@]}"; do
		match=$(echo "$line" | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | awk 'NR==1{print $1}')
		if [[ "$match" != "" ]]; then
			eval "$1"="$match"
			return 0
		fi
	done
	return 1
}

function _tty_resolve_ip() {
	local start_time current_time elapsed_time ip="$1" timeout="$2"
	if [[ "$timeout" == "" ]] || [[ "$timeout" -le "0" ]]; then
		timeout="10"
	fi
	start_time=$(date +%s)
	while true; do
		if _tty_peek_ip "$ip"; then
			return 0
		fi
		sleep 0.5
		current_time=$(date +%s)
		elapsed_time=$((current_time - start_time))
		if [[ "$elapsed_time" -ge "$timeout" ]]; then
			return 1
		fi
	done
}

function _tty_go() {
	if ! _tty_login; then
		_fatal "Can't login to TTY"
	fi
	_tty_promt "ifconfig"
}

SSH_FLAGS=(
	-o StrictHostKeyChecking=no
	-o UserKnownHostsFile=/dev/null
	-o ConnectTimeout=5
	-o ConnectionAttempts=1
	-o ServerAliveInterval=1
	-o ServerAliveCountMax=2
	-o Compression=no
	#-o CompressionLevel=9
	-o Ciphers="aes128-ctr,aes192-ctr,aes256-ctr"
	-o MACs="hmac-sha1"
	-o ControlMaster=auto
	-o ControlPersist=600
	-o ControlPath=/var/tmp/ssh-%r@%h-%p
	-o ForwardAgent=yes
	-o PreferredAuthentications="password"
)

#konsole -e /bin/bash --rcfile <(echo "sshpass -p root ssh -t root@10.113.11.156 ifconfig")
command="sshpass -p root ssh -tt ${SSH_FLAGS[*]} root@10.113.11.156 dl"
#--new-tab
konsole -e /bin/bash --rcfile <(echo "$command")
