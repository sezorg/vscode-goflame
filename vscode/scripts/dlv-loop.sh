#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Run Delve in inifinite DAP loop with local console capture
# To terminate use `ds' command

if [[ "$instance_guard" == "" ]]; then
	export instance_guard="root"
	while true; do
		if [[ -f "$0" ]]; then
			"$0"
		else
			sleep 1
		fi
	done
fi

set -euo pipefail
#set -x

DLOOP_ENABLE_FILE="/tmp/dlv-loop-enable"
DLOOP_STATUS_FILE="/tmp/dlv-loop-status"

RED=$(printf "\e[31m")
GREEN=$(printf "\e[32m")
YELLOW=$(printf "\e[33m")
BLUE=$(printf "\e[34m")
GRAY=$(printf "\e[90m")
NC=$(printf "\e[0m")

function unused() { :; }
unused "$RED" "$GREEN" "$YELLOW" "$BLUE" "$GRAY" "$NC"

PATTERN="TARGET_IPPORT"
if [[ "[[TARGET_IPPORT]]" == "[[$PATTERN]]" ]]; then
	echo "${RED}IP port number is not set. Do not run this script directly.${NC}"
	exit "1"
fi

IGNORE_LIST=()
# -- Application startup messages
IGNORE_LIST+=("warning layer=rpc Listening for remote connections")
#IGNORE_LIST+=("concrete subprogram without address range at")
#IGNORE_LIST+=("inlined call without address range at")
IGNORE_LIST+=(" without address range at ")
IGNORE_LIST+=("debug layer=debugger")
IGNORE_LIST+=("info layer=debugger created breakpoint:")
IGNORE_LIST+=("info layer=debugger cleared breakpoint:")
# -- Interactive debuger related messages
IGNORE_LIST+=("Failed to execute cursor closing: ERROR: cursor")

IGNORE_PATTERN="$(printf "\n%s" "${IGNORE_LIST[@]}")"
IGNORE_PATTERN="${IGNORE_PATTERN:1}"
PRINT_PATTERNS="$(printf ",\"%s\"" "${IGNORE_LIST[@]}")"
PRINT_PATTERNS="${PRINT_PATTERNS:1}"

function cleanup() {
	if [[ -f "${DLOOP_STATUS_FILE}" ]]; then
		rm -f "${DLOOP_STATUS_FILE}"
	fi
}
trap cleanup EXIT

if [[ -f "${DLOOP_STATUS_FILE}" ]]; then
	dlv_pid="$(cat "${DLOOP_STATUS_FILE}")"
	rm -f "${DLOOP_STATUS_FILE}"
	function xnull() { return 0; }
	xnull "$(pkill -P "${dlv_pid} >/dev/null")"
	xnull "$(kill "${dlv_pid} >/dev/null")"
	unset dlv_pid
fi

function safe() {
	local exit_status
	set +e
	eval "$1"
	exit_status="$?"
	set -e
	return $exit_status
}

function digest() {
	if [[ -f "${1}" ]]; then
		echo "$(md5sum "${1}")$(date -r "${1}" "+%m-%d-%Y %H:%M:%S")"
	else
		echo "no-file"
	fi
}

function seltest() {
	s2=$(digest "$0")
	if [[ "${s1}" != "${s2}" ]]; then
		echo "${RED}WARNING: The script has been updated via external upload.${NC}"
		echo "${RED}WARNING: Exiting.... Please restart this script.${NC}"
		exit 1
	fi
}

s1=$(digest "$0")
first_time_run="1"
additional_sleep=
while :; do

	if [[ ! -f "${DLOOP_ENABLE_FILE}" ]]; then
		additional_sleep=1
		echo "${YELLOW}The device to be debugged has been rebooted and is now in a non-determined state.${NC}"
		echo "${YELLOW}Please run ${BLUE}\"Go: Build Workspace\"${YELLOW} befor continue. Waiting for completion...${NC}"
		while [[ ! -f "${DLOOP_ENABLE_FILE}" ]]; do
			seltest
			sleep 1
		done
	fi

	dlv_binary=""
	safe dlv_binary="$(which dlv)"
	if [[ "${dlv_binary}" == "" ]] || [[ ! -f "$0" ]]; then
		additional_sleep=1
		if [[ "${first_time_run}" != "" ]]; then
			echo "${YELLOW}Unable to locate Delve/DLV binary.${YELLOW}"
			echo "${YELLOW}Please run ${BLUE}\"Go: Build Workspace\"${YELLOW} befor continue. Waiting for deploy...${NC}"
		else
			echo "Waiting for the Build&Deploy process to complete..."
		fi
		while [[ "${dlv_binary}" == "" ]] || [[ ! -f "$0" ]]; do
			seltest
			sleep 1
			safe dlv_binary="$(which dlv)"
		done
		continue
	fi

	if ! safe "dlv_version='$("${dlv_binary}" "version")'"; then
		sleep 1
		continue
	fi

	if [[ "${additional_sleep}" != "" ]]; then
		additional_sleep=
		sleep 2
		continue
	fi

	seltest
	echo "Starting Delve headless server loop in DAP mode."
	#echo "${GREEN}Ignore pattern: ${PRINT_PATTERNS}${NC}"
	sh -c "${dlv_binary} dap --listen=:[[TARGET_IPPORT]] --api-version=2 --log 2>&1 | grep -v \"${IGNORE_PATTERN}\"" &
	dlv_pid="$!"

	echo "${dlv_pid}" >"${DLOOP_STATUS_FILE}"
	wait "${dlv_pid}" >/dev/null 2>&1

	count="5"
	while [[ "${count}" != "0" ]]; do
		count=$((count - 1))
		if [[ ! -f "${DLOOP_STATUS_FILE}" ]]; then
			exit "0"
		fi
		sleep 0.2
	done

	echo " "
	echo " "
	echo " "
	first_time_run=""
done
