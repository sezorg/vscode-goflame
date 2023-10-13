#!/bin/bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Git-Gerrit tags
# Requires:
#   https://github.com/fbzhong/git-gerrit

#set -euo pipefail

SSH_FLAGS=(
	-o StrictHostKeyChecking=no
	-o UserKnownHostsFile=/dev/null
	-o ConnectTimeout=5
	-o ConnectionAttempts=1
	-o ServerAliveInterval=1
	-o ServerAliveCountMax=2
)

function gh() {
	echo "gri: git rebase --interactive HEAD~\$1"
	echo "grc: git rebase --continue"
	echo "grm: git rebase --update-refs master"
	echo "grx: git rebase --abort"
	echo "gpc: git cherry-pick --continue"
	echo "gs: git status"
	echo "ga: git add -u"
	echo "gp: git push origin [HEAD:refs/for/master]"
	echo "gt: gerrit-tags [me/all/username/user@mail]"
	echo "ss: ssh root-user@[ip_address]"
	echo "ssd: ssh root-user@[ip_address] dloop"
	echo "sf: sshfs root-user@[ip_address]"
	echo "pi: picocom -b 115200 [/dev/ttyUSB0]"
	echo "jc: jsoncli.py ...arguments"
	echo "xcd: cd [directory]"
	echo "upd: sudo dnf update --refresh"
	return 0
}

function master_branch_lookup() {
	local branches=("master" "main" "ipcam")
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
		target="HEAD:refs/for/$(master_branch_lookup)"
	fi
	git push origin "$target"
}

function gt() {
	"getags.py" "$@"
}

function _error() {
	if [[ "$1" != "" ]]; then
		echo >&2 "ERROR: $1"
	fi
	return 1
}

function _warning() {
	if [[ "$1" != "" ]]; then
		echo >&2 "WARNING: $1"
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
	if [[ "$actual_value" == "" ]]; then
		if [[ -f "$value_path/$value_name" ]]; then
			actual_value=$(cat "$value_path/$value_name")
		fi
	else
		mkdir -p "$value_path" >/dev/null >&2
		echo "$actual_value" >"$value_path/$value_name"
	fi
	if [[ "$actual_value" == "" ]]; then
		if [[ "$default_value" != "" ]]; then
			_warning "$error_message"
			actual_value="$default_value"
		else
			_error "$error_message"
			return 1
		fi
	fi
	echo "$actual_value"
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

function ss() {
	local user="root"
	local pass="root"
	local ip_address
	if ! ip_address=$(_resolve_variable "$1" "" "last_ip_addr" "Target IP address parameter expected"); then
		return 1
	fi
	if [[ "$1" == "" ]]; then
		echo "Connecting to $ip_address"
	fi
	_set_konsole_title "SSH on $user@$ip_address" "SSH on $user@$ip_address"
	sshpass -p "$pass" ssh \
		"${SSH_FLAGS[@]}" "$user@$ip_address" 2> >(grep -E -v '^Warning: Permanently added' >&2)
	_set_konsole_title
}

function ssd() {
	local user="root"
	local pass="root"
	local ip_address
	if ! ip_address=$(_resolve_variable "$1" "" "last_ip_addr" "Target IP address parameter expected"); then
		return 1
	fi
	if [[ "$1" == "" ]]; then
		echo "Connecting to $ip_address"
	fi
	_set_konsole_title "SSH on $user@$ip_address" "SSH on $user@$ip_address"
	sshpass -p "$pass" ssh \
		"${SSH_FLAGS[@]}" "$user@$ip_address" dloop 2> >(grep -E -v '^Warning: Permanently added' >&2)
	_set_konsole_title
}

function run() {
	echo "-- $*"
	"$@"
}

function sf() {
	local user="root"
	local pass="root"
	local ip_address
	if ! ip_address=$(_resolve_variable "$1" "" "last_ip_addr" "Target IP address parameter expected"); then
		return 1
	fi
	if [[ "$1" == "" ]]; then
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
	if ! device_path=$(_resolve_variable "$1" "/dev/ttyUSB0" "tty_device" "TTY device path parameter expected"); then
		return 1
	fi
	if ! sh -c ": >$device_path" >/dev/null 2>/dev/null; then
		_error "TTY device $device_path is not avaliable"
		return 1
	fi
	_set_konsole_title "picocom on $device_path" "picocom on $device_path"
	picocom -b 115200 "$device_path"
	_set_konsole_title
}

function jc() {
	"./jsoncli/jsoncli.sh" "$@"
}

function xcd() {
	local destin
	if ! destin=$(_resolve_variable "$1" "" "last_destin" "Destination directory expected"); then
		return 1
	fi
	echo "Changing directory: $destin"
	cd "$destin" || true
}

function upd() {
	. /etc/os-release
	printf 'Updating %s %s\n' \
		"${REDHAT_SUPPORT_PRODUCT:-$PRETTY_NAME}" \
		"${REDHAT_SUPPORT_PRODUCT_VERSION:-$VERSION_ID}"
	sudo dnf update --refresh
}
