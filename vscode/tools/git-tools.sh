#!/bin/bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Git-Gerrit tags
# Requires:
#   https://github.com/fbzhong/git-gerrit

#set -euo pipefail
#set -x

SSH_FLAGS=(
	-o StrictHostKeyChecking=no
	-o UserKnownHostsFile=/dev/null
	-o ConnectTimeout=5
	-o ConnectionAttempts=1
	-o ServerAliveInterval=1
	-o ServerAliveCountMax=2
)

function gh() {
	echo "gri:  git rebase --interactive HEAD~\$1"
	echo "grc:  git rebase --continue"
	echo "grm:  git rebase --update-refs master"
	echo "grx:  git rebase --abort"
	echo "gpc:  git cherry-pick --continue"
	echo "gs:   git status"
	echo "ga:   git add -u"
	echo "gp:   git push origin [<master> >>> HEAD:refs/for/master]"
	echo "gt:   gerrit-tags [me/all/username/user@mail]"
	echo "ss:   ssh root-user@[ip_address]"
	echo "so:   xdg-open http://[ip_address]"
	echo "sf:   sshfs root-user@[ip_address]"
	echo "pi:   picocom -b 115200 [/dev/ttyUSB0]"
	echo "jc:   jsoncli.py ...arguments"
	echo "xcd:  cd [directory]"
	echo "upd:  sudo dnf update --refresh"
	echo "sd:   dnf search <args>"
	echo "di:   sudo dnf install <args>"
	return 0
}

function master_branch_lookup() {
	local branches=("master" "main" "ipcam" "ecam02" "ecam03")
	for branch in "${branches[@]}"; do
		if (git rev-parse --verify "$branch" >/dev/null 2>&1); then
			echo "$branch"
			return 0
		fi
	done
	echo "unknown-master-branch"
	return 1
}

function gri() {
	git config rebase.abbreviateCommands true
	git rebase --interactive "HEAD~$1"
}

function grc() {
	git rebase --continue
}

function grm() {
	git rebase --update-refs "$(master_branch_lookup)"
}

function grx() {
	git rebase --abort
}

function gpc() {
	git cherry-pick --continue
}

function gs() {
	git status
}

function ga() {
	git add -u
}

function gp() {
	local target="$1"
	if [[ "$target" == "" ]]; then
		target="$(master_branch_lookup)"
	fi
	git push origin "HEAD:refs/for/$target"
}

function gt() {
	"getags.py" "$@"
}

function _error() {
	if [[ "$1" != "" ]]; then
		echo >&2 "ERROR: $1"
	fi
}

#p_base_pid="$$"

function _fatal() {
	if [[ "$1" != "" ]]; then
		echo >&2 "FATAL: $1"
	fi
	#if [[ "$p_base_pid" != "$$" ]]; then
	#	echo "kill $$"
	#fi
	#exit 1
}

function _warning() {
	if [[ "$1" != "" ]]; then
		echo >&2 "WARNING: $1"
	fi
}

_debug_en=false

function _debug() {
	if ! $_debug_en; then
		return 0
	fi
	if [[ "$1" != "" ]]; then
		echo >&2 "DEBUG: $1"
	fi
	return 0
}

function _readvar() {
	# call like this: readvar filename variable
	while read -r line; do
		# you could do some validation here
		echo "$line"
	done <"$1"
	echo "${!2}"
}

function _resolve_variable() {
	local actual_value="$1"
	local default_value="$2"
	local value_name="$3"
	local error_message="$4"
	local value_path="$HOME/.config/sshcache"
	if [[ "$actual_value" == "x" ]]; then
		local last_config="/var/tmp/goflame/config-vscode.ini"
		if [[ "$value_name" == "last_ip_addr" ]] &&
			[[ -f "$last_config" ]]; then
			# shellcheck disable=SC1090
			source "$last_config"
			actual_value="$TARGET_IPADDR"
		fi
	elif [[ "$actual_value" == "" ]]; then
		if [[ -f "$value_path/$value_name" ]]; then
			actual_value=$(cat "$value_path/$value_name")
		fi
	fi
	mkdir -p "$value_path" >/dev/null >&2
	echo "$actual_value" >"$value_path/$value_name"
	if [[ "$actual_value" == "" ]]; then
		if [[ "$default_value" != "" ]]; then
			_warning "$error_message"
			actual_value="$default_value"
		else
			_fatal "$error_message"
		fi
	fi
	echo "$actual_value"
}

function _is_empty_argument() {
	[[ "$1" == "" ]] || [[ "$1" == "x" ]]
}

function _set_konsole_tab_title_type() {
	local title="$1"
	local type=${2:-0}
	if [[ -z "$title" ]] ||
		[[ -z "$KONSOLE_DBUS_SERVICE" ]] ||
		[[ -z "$KONSOLE_DBUS_SESSION" ]]; then
		return 0
	fi
	qdbus >/dev/null "$KONSOLE_DBUS_SERVICE" "$KONSOLE_DBUS_SESSION" setTabTitleFormat "$type" "$title"
}

function _set_konsole_title() {
	local titleLocal=${1:-%d : %n}
	local titleRemote=${2:-(%u) %H}
	_set_konsole_tab_title_type "$titleLocal" &&
		_set_konsole_tab_title_type "$titleRemote" 1
}

TTY_PORT=""
TTY_SPEED="115200"
TTY_PICOCOM="picocom"
TTY_LOGIN="root"
TTY_PASS="root"
TTY_DELAY="100" # milliseconds

function _tty_resolve_port() {
	if [[ "$TTY_PORT" == "" ]] || [[ "$TTY_PORT" == "x" ]]; then
		TTY_PORT="$(find /dev -name "ttyUSB*" -print -quit)"
		if [[ "$TTY_PORT" == "" ]]; then
			_fatal "Unable to find USB TTY port"
		fi
	fi
	_debug "TTY: port $TTY_PORT"
}

function _tty_shell() {
	_tty_resolve_port
	local format="" text
	for ((i = 0; i <= $#; i++)); do
		format="$format%s\r"
	done
	# shellcheck disable=SC2059
	text="$(printf "$format" "$@")"
	_debug "TTY: send: -->$text<--"
	if ! text=$("$TTY_PICOCOM" -qrb "$TTY_SPEED" -x "$TTY_DELAY" "$TTY_PORT" -t "$text" 2>&1); then
		text=$(echo "$text" | xargs)
		_fatal "Unable to communicate with TTY '$TTY_PORT': $text"
	fi
	_debug "TTY: recv: -->$text<--"
	echo "$text"
}

function _tty_promt() {
	_tty_resolve_port
	local format="" text
	for ((i = 0; i <= $#; i++)); do
		format="$format%s\r"
	done
	# shellcheck disable=SC2059
	text="$(printf "$format" "$@")"
	_debug "TTY: send: -->$text<--"
	if ! "$TTY_PICOCOM" -qrb "$TTY_SPEED" "$TTY_PORT" -t "$text"; then
		_fatal "Unable to communicate with TTY '$TTY_PORT'"
	fi
}

function _tty_exchange() {
	[[ "$(_tty_shell "$1")" == *"$2"* ]]
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

function ss() {
	local user="root" pass="root" ip_address
	ip_address=$(_resolve_variable "$*" "" "last_ip_addr" "Target IP address parameter expected")
	if _is_empty_argument "$*"; then
		echo "Connecting to $ip_address"
	fi
	_set_konsole_title "SSH on $user@$ip_address" "SSH on $user@$ip_address"
	sshpass -p "$pass" ssh \
		"${SSH_FLAGS[@]}" "$user@$ip_address" 2> >(grep -E -v '^Warning: Permanently added' >&2)
	_set_konsole_title
}

function so() {
	local ip_address
	ip_address=$(_resolve_variable "$*" "" "last_ip_addr" "Target IP address parameter expected")
	if _is_empty_argument "$*"; then
		echo "Opening http://$ip_address"
	fi
	xdg-open "http://$ip_address"
}

function run() {
	echo "-- $*"
	"$@"
}

function sf() {
	local user="root" pass="root" ip_address
	ip_address=$(_resolve_variable "$*" "" "last_ip_addr" "Target IP address parameter expected")
	if _is_empty_argument "$*"; then
		echo "Mounting FS of $ip_address"
	fi
	local mount_point="$HOME/Devices/$ip_address"
	mkdir -p "$mount_point"
	fusermount -u "$mount_point" >/dev/null 2>&1
	echo $pass | sshfs "${SSH_FLAGS[@]}" "$user@$ip_address:/" "$mount_point" -o workaround=rename -o password_stdin
	echo "Done. Mounted to: $mount_point"
	if [[ -x "$(command -v dolphin)" ]]; then
		dolphin "$mount_point"
	elif [[ -x "$(command -v nautilus)" ]]; then
		nautilus "$mount_point"
	fi
}

function pi() {
	local device_path
	device_path=$(
		_resolve_variable "$*" "/dev/ttyUSB0" "tty_device" "TTY device path parameter expected"
	)
	TTY_PORT="$device_path"
	_tty_resolve_port
	if ! _tty_login; then
		_fatal "Can not login to TTY $TTY_PORT"
	fi
	_set_konsole_title "TTY on $TTY_PORT" "TTY on $TTY_PORT"
	_tty_promt "ifconfig"
	_set_konsole_title
}

function jc() {
	"./jsoncli/jsoncli.sh" "$@"
}

function xcd() {
	local destin
	destin=$(_resolve_variable "$*" "" "last_destin" "Destination directory expected")
	echo "Changing directory: $destin"
	cd "$destin" || true
}

function upd() {
	. /etc/os-release
	printf 'Updating %s %s\n' \
		"${REDHAT_SUPPORT_PRODUCT:-$PRETTY_NAME}" \
		"${REDHAT_SUPPORT_PRODUCT_VERSION:-$VERSION_ID}"
	sudo dnf update --refresh "$@"
}

function ds() {
	dnf search "$@"
}

function di() {
	sudo dnf install "$@"
}
