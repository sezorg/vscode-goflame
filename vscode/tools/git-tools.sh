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
	echo "gp: git push origin [<master> >>> HEAD:refs/for/master]"
	echo "gt: gerrit-tags [me/all/username/user@mail]"
	echo "ss: ssh root-user@[ip_address]"
	echo "so: xdg-open http://[ip_address]"
	echo "sf: sshfs root-user@[ip_address]"
	echo "pi: picocom -b 115200 [/dev/ttyUSB0]"
	echo "jc: jsoncli.py ...arguments"
	echo "xcd: cd [directory]"
	echo "upd: sudo dnf update --refresh"
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
			_error "$error_message"
			exit 1
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

function ss() {
	local user="root" pass="root" ip_address
	ip_address=$(_resolve_variable "$1" "" "last_ip_addr" "Target IP address parameter expected")
	if _is_empty_argument "$1"; then
		echo "Connecting to $ip_address"
	fi
	_set_konsole_title "SSH on $user@$ip_address" "SSH on $user@$ip_address"
	sshpass -p "$pass" ssh \
		"${SSH_FLAGS[@]}" "$user@$ip_address" 2> >(grep -E -v '^Warning: Permanently added' >&2)
	_set_konsole_title
}

function so() {
	local ip_address
	ip_address=$(_resolve_variable "$1" "" "last_ip_addr" "Target IP address parameter expected")
	if _is_empty_argument "$1"; then
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
	ip_address=$(_resolve_variable "$1" "" "last_ip_addr" "Target IP address parameter expected")
	if _is_empty_argument "$1"; then
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
		_resolve_variable "$1" "/dev/ttyUSB0" "tty_device" "TTY device path parameter expected"
	)
	if ! sh -c ": >$device_path" >/dev/null 2>/dev/null; then
		_error "TTY device $device_path is not avaliable"
		return 1
	fi
	_set_konsole_title "picocom on $device_path" "picocom on $device_path"
	self_ip=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
	baud_rate="115200"
	session_file="/var/tmp/picocom_session_startup"
	session_lines=(
		"# Automatically generated: $(date +"%A, %B %d, %Y, %I:%M:%S %p")"
		"from_ip=\"$self_ip\""
		"blue=\\\$(printf '\'\"e[34m\") nc=\\\$(printf '\'\"e[0m\")"
		"ip=\\\$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')"
		"echo \"\\\${nc}Device IP: \\\${blue}\\\$ip\\\${nc} Link: \\\${blue}http://\\\$ip\\\${nc}\""
		"ip --color addr show eth0 | grep -v valid_lft"
		"# cat \"$session_file\""
		"# rm \"$session_file\""
	)
	session_outer=">"
	session_text=""
	for session_line in "${session_lines[@]}"; do
		session_line="echo \"${session_line//\"/\\\"}\" $session_outer\"$session_file\""
		session_text="$session_text && $session_line"
		session_outer=">>"
	done
	session_text="${session_text:4}"
	session_text="${session_text} && chmod +x \"$session_file\""
	#echo "$session_text"
	session_text=$(printf "\r%s\r%s\r%s\r" "root" "root" "$session_text")
	echo "$session_text" | picocom -rqb "$baud_rate" "$device_path" >/dev/null 2>&1
	sleep 0.3
	yellow=$(printf "\e[33m") nc=$(printf "\e[0m")
	echo -n "$yellow"
	picocom -qrb "$baud_rate" "$device_path" -t "$(echo -ne "sh $session_file"'\r')"
	echo -n "$nc"
	_set_konsole_title
}

function jc() {
	"./jsoncli/jsoncli.sh" "$@"
}

function xcd() {
	local destin
	destin=$(_resolve_variable "$1" "" "last_destin" "Destination directory expected")
	echo "Changing directory: $destin"
	cd "$destin" || true
}

function upd() {
	. /etc/os-release
	printf 'Updating %s %s\n' \
		"${REDHAT_SUPPORT_PRODUCT:-$PRETTY_NAME}" \
		"${REDHAT_SUPPORT_PRODUCT_VERSION:-$VERSION_ID}"
	sudo dnf update --refresh $*
}
