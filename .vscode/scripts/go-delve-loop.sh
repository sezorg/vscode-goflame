#!/usr/bin/env bash
# Copyright 2025 RnD Center "ELVEES", JSC
#
# Run Delve in infinite DAP loop with local console capture
# To terminate use `ds' command

set -euo pipefail

function unused() { :; }

function is_true() {
	[[ "${1^^}" =~ ^(1|T|TRUE|Y|YES)$ ]]
}

function is_false() {
	[[ ! "${1^^}" =~ ^(1|T|TRUE|Y|YES)$ ]]
}

CIN=$(printf "\e")
RED=$(printf "\e[31m") GREEN=$(printf "\e[32m") YELLOW=$(printf "\e[33m")
BLUE=$(printf "\e[34m") GRAY=$(printf "\e[90m") NC=$(printf "\e[0m")
unused "$RED" "$GREEN" "$YELLOW" "$BLUE" "$GRAY" "$NC"

P_SCRIPT_PATH="$0"
P_SCRIPT_NAME=$(basename -- "$P_SCRIPT_PATH")
P_SCRIPT_NAME="${P_SCRIPT_NAME%.*}"
P_SCRIPT_PID="$$"

P_LOG_FILE="/var/tmp/dl.log"

P_DEBUG_PREFIX="Init: "

function logcho() {
	local filter="s/$CIN\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g"
	echo "$P_SCRIPT_PID: $*" | sed -r "$filter" >>"$P_LOG_FILE"
}

function errcho() {
	echo "$@" 1>&2
}

function debug() {
	if is_true "false"; then
		local message="$*"
		if [[ "$message" != "" ]]; then
			message="${GREEN}DEBUG: $P_DEBUG_PREFIX$message$NC"
			logcho "$message"
			errcho "$message"
		fi
	fi
}

function log() {
	local message="$*"
	if [[ "$message" != "" ]]; then
		message="$BLUE|| $message$NC" >&2
		logcho "$message"
		errcho "$message"
	fi
}

function error() {
	local message="$*"
	if [[ "$message" != "" ]]; then
		message="$RED*** ERROR: $message$NC" >&2
		logcho "$message"
		errcho "$message"
	fi
}

function fatal() {
	local message="$*"
	if [[ "$message" == "" ]]; then
		message="Fatal error"
	fi
	error "$message"
	exit 1
}

P_DLOOP_ENABLE_FILE="__DLOOP_ENABLE_FILE__"
P_DLOOP_RESTART_FILE="__DLOOP_RESTART_FILE__"
P_TARGET_PORT="__TARGET_PORT__"
P_TARGET_BINARY_NAME="__TARGET_BINARY_NAME__"
P_TARGET_BINARY_PATH="__TARGET_BINARY_PATH__"
P_TARGET_BINARY_ARGS=(__TARGET_BINARY_ARGS__)

P_SUPPRESS_LIST=(__TARGET_SUPPRESS_MSSGS__)
P_SUPPRESS_PATTERN="$(printf "\n%s" "${P_SUPPRESS_LIST[@]}")"
P_SUPPRESS_PATTERN="${P_SUPPRESS_PATTERN:1}"

P_DELVE_NAME="dlv"
P_DELVE_PID=""
P_TARGET_PID=""
P_EXIT_STATUS_RELOAD=155
P_EXIT_FULL_CLEANUP=true
P_SCRIPT_LOCK_FD=""
P_SCRIPT_LOCK_FILE="/run/lock/$P_SCRIPT_NAME-lock.lock"
P_GUARD_PID_FILE="/run/lock/$P_SCRIPT_NAME-guard.pid"
P_SCRIPT_PID_FILE="/run/lock/$P_SCRIPT_NAME-main.pid"
P_DELVE_PID_FILE="/run/lock/$P_SCRIPT_NAME-delve.pid"
P_TARGET_PID_FILE="/run/lock/$P_SCRIPT_NAME-$P_TARGET_BINARY_NAME.pid"

P_RUN_STDOUT=""
P_RUN_STDERR=""
P_RUN_STATUS=""

function run_ex() {
	local canfail="$1"
	shift 1
	local command="$*"
	set "+e"
	{
		P_RUN_STDOUT=$(chmod u+w /dev/fd/888 && eval "$command" 2>/dev/fd/888)
		P_RUN_STATUS=$?
		P_RUN_STDERR=$(cat <&888)
	} 888<<EOF
EOF
	set "-e"
	if [[ "$P_RUN_STATUS" != "0" ]] && [[ "$canfail" == "" ]]; then
		if [[ "$P_RUN_STDOUT" != "" ]]; then
			error "STDOUT: $P_RUN_STDOUT"
		fi
		if [[ "$P_RUN_STDERR" != "" ]]; then
			error "STDERR: $P_RUN_STDERR"
		fi
		error "STATUS: $P_RUN_STATUS"
		fatal "Failed to execute: $command"
	elif false; then
		if [[ "$P_RUN_STDOUT" != "" ]]; then
			debug "Run STDOUT: $P_RUN_STDOUT"
		fi
		if [[ "$P_RUN_STDERR" != "" ]]; then
			debug "Run STDERR: $P_RUN_STDERR"
		fi
	fi
}

function run() {
	run_ex "true" "$@"
}

function run_stdout() {
	local -n stdout="$1"
	shift
	run_ex "true" "$@"
	# shellcheck disable=SC2034
	stdout="$P_RUN_STDOUT"
}

function process_active_by_pid() {
	run kill -0 "$1"
	[[ "$P_RUN_STATUS" == "0" ]]
}

function kill_by_pid() {
	if [[ "$2" != "" ]] && process_active_by_pid "$2"; then
		debug "Killing $1 PID $2"
		run pkill -P "$2"
		run kill -9 "$2"
		run timeout --kill-after=1 1 wait "$2"
	fi
}

function kill_by_file() {
	run cat "$1"
	kill_by_pid "$1" "$P_RUN_STDOUT"
	run rm -f "$1"
}

function cleanup() {
	debug "Cleaning up at $1..."
	kill_by_pid "delve" "$P_DELVE_PID"
	kill_by_pid "target" "$P_TARGET_PID"
	P_DELVE_PID=""
	P_TARGET_PID=""
	kill_by_file "$P_DELVE_PID_FILE"
	kill_by_file "$P_TARGET_PID_FILE"
	if is_true "$2"; then
		kill_by_file "$P_SCRIPT_PID_FILE"
	fi
	debug "Cleaning up at $1: done"
}

P_ARG_CHECK_ACTIVE=false

function parse_arguments() {
	local result=()
	for this_item in "$@"; do
		debug "Arg: $this_item"
		local skip_item=true
		case "$this_item" in
		"-C" | "--check-active")
			P_ARG_CHECK_ACTIVE=true
			;;
		*)
			skip_item=false
			;;
		esac
		if is_false "$skip_item"; then
			result+=("$this_item")
		fi
	done
}

P_DEBUG_PREFIX="Init: "
parse_arguments "$@"

if is_true "$P_ARG_CHECK_ACTIVE"; then
	if [[ ! -f "$P_SCRIPT_LOCK_FILE" ]]; then
		echo "inactive"
	else
		touch "$P_SCRIPT_LOCK_FILE"
		exec {P_SCRIPT_LOCK_FD}<>"$P_SCRIPT_LOCK_FILE"
		if ! flock --exclusive --timeout 0.1 "$P_SCRIPT_LOCK_FD"; then
			echo "active"
		else
			echo "inactive"
		fi
	fi
	exit 0
fi

function guard_loop() {
	local pattern="TARGET_PORT"
	if [[ "$P_TARGET_PORT" == "__${pattern}__" ]]; then
		fatal "Variables are not substituted. Do not run this script directly.$NC"
	fi

	if [[ -v "P_INSTANCE_GUARD" ]] && [[ "$P_INSTANCE_GUARD" != "" ]]; then
		debug "Guard loop seems to be already running"
		return
	fi

	debug "Entering guard loop, guard PID $P_SCRIPT_PID"
	cleanup "guard" true
	kill_by_file "$P_GUARD_PID_FILE"
	kill_by_file "$P_SCRIPT_PID_FILE"

	touch "$P_SCRIPT_LOCK_FILE"
	exec {P_SCRIPT_LOCK_FD}<>"$P_SCRIPT_LOCK_FILE"
	flock --exclusive --timeout 0.1 "$P_SCRIPT_LOCK_FD" ||
		fatal "Another instance of \"$0\" seems to be already running."

	export P_INSTANCE_GUARD="active"
	echo "$P_SCRIPT_PID" >"$P_GUARD_PID_FILE"

	while true; do
		debug "Iterating guard loop..."
		if [[ -f "$0" ]]; then
			set +e
			debug "Running guarded script: $0"
			"$0"
			status="$?"
			set -e
			if [[ "$status" != "$P_EXIT_STATUS_RELOAD" ]]; then
				case "$status" in
				"0") ;;
				"130" | "137")
					log "Terminated (exit status $status)"
					;;
				*)
					error "Script exit status $status"
					;;
				esac
				debug "Exiting guard loop, guard PID $P_SCRIPT_PID"
				exit "1"
			fi
			count="20"
			while [[ "$count" != "0" ]]; do
				count=$((count - 1))
				if [[ -f "$P_DLOOP_ENABLE_FILE" ]]; then
					break
				fi
				usleep 500000
			done
		else
			usleep 500000
		fi
	done
}

P_DEBUG_PREFIX="Guard: "
# TODO: Use guard_loop 2>&1 | stdbuf -o0 grep -v "$0" and preserve original exit stratus
guard_loop

function at_error() {
	set +u
	local parent_lineno="$1"
	local message="$2"
	local code="${3:-1}"
	error "Error on or near line $parent_lineno"
	if [[ -n "$message" ]]; then
		error "$message"
	fi
	error "Exiting with status $code"
	exit "$code"
}

trap 'at_error $LINENO' ERR

function at_exit() {
	cleanup "exit" "$P_EXIT_FULL_CLEANUP"
}

trap 'at_exit' SIGINT SIGTERM EXIT

cleanup "startup" false

function file_digest() {
	if [[ -f "$1" ]]; then
		date -r "$1" "+%m-%d-%Y %H:%M:%S" 2>&1
	else
		echo "no-file"
	fi
}

function self_digest() {
	file_digest "$P_SCRIPT_PATH"
}

function get_restart_digest() {
	file_digest "$P_DLOOP_RESTART_FILE"
}

P_SELF_DIGEST="$(self_digest)"
P_CURRENT_IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' |
	grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')

function self_test() {
	if [[ ! -f "$P_DLOOP_ENABLE_FILE" ]] || [[ "$P_SELF_DIGEST" != "$(self_digest)" ]]; then
		log "${GREEN}INFORMATION: The script has been updated via external upload. Restarting...$NC"
		P_EXIT_FULL_CLEANUP=false
		exit "$P_EXIT_STATUS_RELOAD"
	fi
}

function sleep_milliseconds() {
	local useconds="$1" period=$((100 * 1000))
	self_test
	useconds=$((useconds * 1000))
	while ((useconds > 0)); do
		useconds=$((useconds - period))
		usleep "$period"
		self_test
	done
}

function main_loop() {
	local print_delimiter=false loop_mode=""

	while :; do
		debug "Iterating main loop"
		if is_true "$print_delimiter"; then
			log " "
			log " "
			log " "
		fi

		run_stdout loop_mode cat "$P_DLOOP_ENABLE_FILE"
		if [[ "$loop_mode" == "" ]]; then
			log "${YELLOW}The device to be debugged has been rebooted and" \
				" is now in a non-determined state."
			log "${YELLOW}Please run $BLUE\"Go: Build Workspace\"$YELLOW before continue." \
				"Waiting for completion..."
			while [[ "$loop_mode" == "" ]]; do
				sleep_milliseconds 200
				run_stdout loop_mode cat "$P_DLOOP_ENABLE_FILE"
			done
		fi

		local dlv_binary dlv_version
		if [[ "$loop_mode" == "debug" ]]; then
			run_stdout dlv_binary which "$P_DELVE_NAME"
			run_stdout dlv_version "$dlv_binary" "version"
			if [[ "$dlv_version" == "" ]]; then
				log "${YELLOW}Unable to locate Delve/DLV binary.$YELLOW"
				loop_mode="exec"
				echo "$loop_mode" >"$P_DLOOP_ENABLE_FILE"
			fi
		fi

		print_delimiter=true
		if [[ "$loop_mode" == "debug" ]]; then
			log "Starting Delve headless server in DAP mode. Host: ${GRAY}http://$P_CURRENT_IP"
			local dap_env="TERM=xterm-256color"
			local dap_args="--listen=:$P_TARGET_PORT --api-version=2 --check-go-version=false --log"
			local dap_grep="stdbuf -o0 grep -v \"$P_SUPPRESS_PATTERN\""
			sh -c "$dap_env $dlv_binary dap $dap_args 2>&1 | $dap_grep" &
			P_DELVE_PID="$!"
			echo "$P_DELVE_PID" >"$P_DELVE_PID_FILE"
			while true; do
				sleep_milliseconds 200
				if ! process_active_by_pid "$P_DELVE_PID"; then
					debug "Debugger '$P_DELVE_NAME' PID $P_DELVE_PID has been exited"
					break
				fi
				run_stdout loop_mode cat "$P_DLOOP_ENABLE_FILE"
				if [[ $loop_mode != "debug" ]]; then
					debug "Terminating '$P_DELVE_NAME' due to mode '$loop_mode'"
					break
				fi
			done
		elif [[ "$loop_mode" == "exec" ]]; then
			local binary="$P_TARGET_BINARY_PATH/$P_TARGET_BINARY_NAME"
			if [[ ! -f "$P_DLOOP_RESTART_FILE" ]] || [[ ! -f "$binary" ]]; then
				local restart=false
				log "Waiting for application to be started (Run/Start Debugging)..."
				while [[ ! -f "$P_DLOOP_RESTART_FILE" ]] || [[ ! -f "$binary" ]]; do
					sleep_milliseconds 200
					run_stdout loop_mode cat "$P_DLOOP_ENABLE_FILE"
					if [[ "$loop_mode" != "exec" ]]; then
						restart=true
						break
					fi
				done
				if is_true "$restart"; then
					continue
				fi
			fi
			local command target_digest cur_digest new_digest
			cur_digest="$(get_restart_digest)"
			log "Starting $P_TARGET_BINARY_NAME [${P_TARGET_BINARY_ARGS[*]}]"
			target_digest="$(file_digest "$binary")"
			command="TERM=xterm-256color \"$binary\" ${P_TARGET_BINARY_ARGS[*]} 2>&1"
			sh -c "$command | stdbuf -o0  grep -v \"$P_SUPPRESS_PATTERN\"" &

			P_TARGET_PID="$!"
			echo "$P_TARGET_PID" >"$P_TARGET_PID_FILE"

			while true; do
				sleep_milliseconds 200
				if ! process_active_by_pid "$P_TARGET_PID"; then
					debug "Debugger '$P_TARGET_BINARY_NAME' PID $P_TARGET_PID has been exited"
					break
				fi
				new_digest="$(get_restart_digest)"
				if [[ "$cur_digest" != "$new_digest" ]]; then
					debug "Restart file missing: $cur_digest!=$new_digest"
					break
				fi
				if [[ "$target_digest" != "$(file_digest "$binary")" ]]; then
					debug "Target binary file changed..."
					break
				fi
				run_stdout loop_mode cat "$P_DLOOP_ENABLE_FILE"
				if [[ "$loop_mode" != "exec" ]]; then
					debug "Exec mode changed to '$loop_mode'..."
					break
				fi
			done
			run rm -rf "$P_DLOOP_RESTART_FILE"
		else
			log "Ready. Waiting for Run/Debug interaction (after $loop_mode)..."
			local current_mode="$loop_mode"
			while [[ "$loop_mode" == "$current_mode" ]]; do
				sleep_milliseconds 200
				run_stdout loop_mode cat "$P_DLOOP_ENABLE_FILE"
			done
			print_delimiter=false
		fi

		cleanup "mail loop" false
	done

}

P_DEBUG_PREFIX="Main: "
echo "$P_SCRIPT_PID" >"$P_SCRIPT_PID_FILE"
debug "Starting main loop, main PID $P_SCRIPT_PID"
main_loop
debug "Exiting main loop, main PID $P_SCRIPT_PID"
