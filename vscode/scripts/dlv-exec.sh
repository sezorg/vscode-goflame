#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Execute binary on the targets which does not support Delve debugging.

set -euo pipefail

RED=$(printf "\e[31m")
GREEN=$(printf "\e[32m")
YELLOW=$(printf "\e[33m")
BLUE=$(printf "\e[34m")
GRAY=$(printf "\e[90m")
NC=$(printf "\e[0m")

function log() {
	echo "$BLUE|| $*$NC"
}

function error() {
	echo "$RED*** ERROR: $*$NC"
}

DLOOP_ENABLE_FILE="__DLOOP_ENABLE_FILE__"
DLOOP_RESTART_FILE="__DLOOP_RESTART_FILE__"

PATTERN="TARGET_PORT"
if [[ "__TARGET_PORT__" == "__${PATTERN}__" ]]; then
	log "${RED}IP port number is not set. Do not run this script directly.$NC"
	exit "1"
fi

status_reload=155
if [[ ! -v "instance_guard" ]] || [[ "$instance_guard" == "" ]]; then
	export instance_guard="root"
	while true; do
		if [[ -f "$0" ]]; then
			set +e
			"$0"
			status="$?"
			set -e
			if [[ "$status" != "$status_reload" ]]; then
				if [[ "$status" != "0" ]]; then
					error "Script exit status $status"
				fi
				exit "$status"
			fi
			count="20"
			while [[ "$count" != "0" ]]; do
				count=$((count - 1))
				if [[ -f "$DLOOP_ENABLE_FILE" ]]; then
					break
				fi
				usleep 500000
			done
		else
			usleep 500000
		fi
	done
fi

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

function unused() { :; }
unused "$RED" "$GREEN" "$YELLOW" "$BLUE" "$GRAY" "$NC"

EXEC_BINARY_PATH="__TARGET_BINARY_PATH__"
EXEC_BINARY_ARGS=(__TARGET_BINARY_ARGS__)
EXEC_SUPPRESS_MSSGS=(__TARGET_SUPPRESS_MSSGS__)

PATTERN="TARGET_BINARY_PATH"
if [[ "$EXEC_BINARY_PATH" == "__${PATTERN}__" ]]; then
	log "${RED}Target binary path is not set. Do not run this script directly.$NC"
	exit "1"
fi

EXE_PROCESS_PID=""

function cleanup() {
	set +e
	local processes running
	processes=$(ps -a)
	running=$(awk "{if(\$3==\"$EXEC_BINARY_PATH\"){print \$3;exit}}" <<<"$processes")
	if [[ "$running" != "" ]]; then
		#log "Terminating $EXEC_BINARY_PATH..."
		killall "$(basename -- "$EXEC_BINARY_PATH")" >/dev/null 2>&1
	fi
	if [[ "$EXE_PROCESS_PID" != "" ]]; then
		kill "$EXE_PROCESS_PID" >/dev/null 2>&1
		wait "$EXE_PROCESS_PID" >/dev/null 2>&1
		EXE_PROCESS_PID=""
	fi
	set -e
}

trap cleanup EXIT

function digest() {
	if [[ -f "$1" ]]; then
		date -r "$1" "+%m-%d-%Y %H:%M:%S" 2>&1
	else
		echo "no-file"
	fi
}

function self_test() {
	s2=$(digest "$0")
	if [[ "$s1" != "$s2" ]]; then
		log "${GREEN}INFORMATION: The script has been updated via external upload. Restarting...$NC"
		exit "$status_reload"
	fi
}

SUPPRESS_PATTERN="$(printf "\n%s" "${EXEC_SUPPRESS_MSSGS[@]}")"
SUPPRESS_PATTERN="${SUPPRESS_PATTERN:1}"

s1=$(digest "$0")
first_time_run="1"
additional_sleep=""
while true; do
	if [[ "$first_time_run" == "" ]]; then
		log " "
		log " "
		log " "
	fi

	self_test
	if [[ ! -f "$DLOOP_ENABLE_FILE" ]]; then
		additional_sleep="1"
		log "${YELLOW}The device to be debugged has been rebooted and is now in a non-determined" \
			"state.$NC"
		log "${YELLOW}Please run $BLUE\"Go: Build Workspace\"$YELLOW before continue. Waiting for" \
			"completion...$NC"
		while [[ ! -f "$DLOOP_ENABLE_FILE" ]]; do
			self_test
			usleep 500000
		done
	fi

	if [[ "$first_time_run" != "" ]]; then
		first_time_run=""
		log "Beginning $EXEC_BINARY_PATH execution loop..."
	fi

	if [[ ! -f "$DLOOP_RESTART_FILE" ]]; then
		log "Waiting for application to be started (Run/Start Debugging)..."
		while [[ ! -f "$DLOOP_RESTART_FILE" ]]; do
			self_test
			usleep 100000
		done
	fi

	if [[ ! -f "$EXEC_BINARY_PATH" ]]; then
		additional_sleep="1"
		log "${YELLOW}Unable to run application: target binary file $EXEC_BINARY_PATH not found.$NC"
		log "${YELLOW}Please run $BLUE\"Go: Build Workspace\"$YELLOW before continue. Waiting for" \
			"completion...$NC"
		while [[ ! -f "$EXEC_BINARY_PATH" ]]; do
			self_test
			usleep 500000
		done
	fi

	if [[ "$additional_sleep" != "" ]]; then
		additional_sleep=""
		usleep 2000000
		continue
	fi

	while [[ -f "$EXEC_BINARY_PATH" ]] && [[ ! -r "$EXEC_BINARY_PATH" ]]; do
		self_test
		usleep 100000
	done

	t1=$(digest "$DLOOP_RESTART_FILE")
	m1=$(digest "$EXEC_BINARY_PATH")
	status=$?
	if [[ $status -ne 0 ]]; then
		usleep 1000000
		continue
	fi

	cleanup
	log "Starting $EXEC_BINARY_PATH [${EXEC_BINARY_ARGS[*]}]"
	command="TERM=xterm-256color \"$EXEC_BINARY_PATH\" ${EXEC_BINARY_ARGS[*]} 2>&1"
	# sh -c "$command | stdbuf -o0 grep -v \"$SUPPRESS_PATTERN\"" &
	sh -c "$command | grep -v \"$SUPPRESS_PATTERN\"" &

	EXE_PROCESS_PID="$!"

	while true; do
		self_test
		usleep 100000
		if [ ! -f "/proc/$EXE_PROCESS_PID/status" ]; then
			break
		fi
		if [[ "$t1" != "$(digest "$DLOOP_RESTART_FILE")" ]]; then
			echo "|| Restart file missing..."
			break
		fi
		if [[ "$m1" != "$(digest "$EXEC_BINARY_PATH")" ]]; then
			echo "|| Configuration changed..."
			break
		fi
	done
	rm -f "$DLOOP_RESTART_FILE"
	cleanup
	sleep 1
done
