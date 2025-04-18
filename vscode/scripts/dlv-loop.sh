#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Run Delve in infinite DAP loop with local console capture
# To terminate use `ds' command

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
DLOOP_STATUS_FILE="__DLOOP_STATUS_FILE__"

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

SUPPRESS_LIST=()
# -- Application startup messages
SUPPRESS_LIST+=("warning layer=rpc Listening for remote connections")
#SUPPRESS_LIST+=("concrete subprogram without address range at")
#SUPPRESS_LIST+=("inlined call without address range at")
SUPPRESS_LIST+=(" without address range at ")
SUPPRESS_LIST+=("debug layer=debugger")
SUPPRESS_LIST+=("info layer=debugger created breakpoint:")
SUPPRESS_LIST+=("info layer=debugger cleared breakpoint:")
# -- Interactive debugger related messages
SUPPRESS_LIST+=("Failed to execute cursor closing: ERROR: cursor")
# --- Annoying application messages
SUPPRESS_LIST+=(__TARGET_SUPPRESS_MSSGS__)

SUPPRESS_PATTERN="$(printf "\n%s" "${SUPPRESS_LIST[@]}")"
SUPPRESS_PATTERN="${SUPPRESS_PATTERN:1}"

IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' |
	grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')

function unused() { :; }
unused "$RED" "$GREEN" "$YELLOW" "$BLUE" "$GRAY" "$NC"

function cleanup() {
	if [[ -f "$DLOOP_STATUS_FILE" ]]; then
		dlv_pid="$(cat "$DLOOP_STATUS_FILE")"
		nohup pkill -P "$dlv_pid" >/dev/null 2>&1 &
		nohup kill -9 "$dlv_pid" >/dev/null 2>&1 &
		rm -f "$DLOOP_STATUS_FILE" >/dev/null 2>&1
		unset dlv_pid
	fi
}

trap cleanup EXIT

cleanup

function safe() {
	local exit_status
	set +e
	eval "$1"
	exit_status="$?"
	set -e
	return $exit_status
}

function digest() {
	if [[ -f "$1" ]]; then
		date -r "$1" "+%m-%d-%Y %H:%M:%S"
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

s1=$(digest "$0")
first_time_run="1"
additional_sleep=
while :; do
	if [[ "$first_time_run" == "" ]]; then
		log " "
		log " "
		log " "
	fi

	self_test
	if [[ ! -f "$DLOOP_ENABLE_FILE" ]]; then
		additional_sleep=1
		log "${YELLOW}The device to be debugged has been rebooted and is now in a non-determined" \
			"state.$NC"
		log "${YELLOW}Please run $BLUE\"Go: Build Workspace\"$YELLOW before continue. Waiting for" \
			"completion...$NC"
		while [[ ! -f "$DLOOP_ENABLE_FILE" ]]; do
			self_test
			sleep 1
		done
	fi

	dlv_binary=""
	safe dlv_binary="$(which dlv)"
	if [[ "$dlv_binary" == "" ]] || [[ ! -f "$0" ]]; then
		additional_sleep=1
		if [[ "$first_time_run" != "" ]]; then
			log "${YELLOW}Unable to locate Delve/DLV binary.$YELLOW"
			log "${YELLOW}Please run $BLUE\"Go: Build Workspace\"$YELLOW before continue." \
				"Waiting for deploy...$NC"
		else
			log "Waiting for the Build&Deploy process to complete..."
		fi
		while [[ "$dlv_binary" == "" ]] || [[ ! -f "$0" ]]; do
			self_test
			sleep 1
			safe dlv_binary="$(which dlv)"
		done
		continue
	fi

	if ! safe "dlv_version='$("$dlv_binary" "version")'"; then
		sleep 1
		continue
	fi

	if [[ "$additional_sleep" != "" ]]; then
		additional_sleep=
		sleep 2
		continue
	fi

	self_test
	log "Starting Delve headless server loop in DAP mode. Host: ${GRAY}http://$IP"
	colors="TERM=xterm-256color"
	dap_args="--listen=:__TARGET_PORT__ --api-version=2 --check-go-version=false --log"
	sh -c "$colors $dlv_binary dap $dap_args 2>&1 | stdbuf -o0 grep -v \"$SUPPRESS_PATTERN\"" &
	dlv_pid="$!"

	echo "$dlv_pid" >"$DLOOP_STATUS_FILE"
	wait "$dlv_pid" >/dev/null 2>&1
	dlv_status=$?
	if [[ $dlv_status -ne 0 ]]; then
		log "Delve exited with status: $dlv_status"
		killall "$(basename -- "$dlv_binary")" >/dev/null 2>&1
	fi

	count="5"
	while [[ "$count" != "0" ]]; do
		count=$((count - 1))
		if [[ ! -f "$DLOOP_STATUS_FILE" ]]; then
			exit "0"
		fi
		sleep 0.2
	done

	first_time_run=""
done
