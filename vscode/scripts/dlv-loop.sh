#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Run Delve in inifinite DAP loop with local console capture
# To terminate use `ds' command

set -euo pipefail
#set "-x"

PATTERN="TARGET_IPPORT"
if [[ "{TARGET_IPPORT}" == "{$PATTERN}" ]]; then
	echo "IP port number is not set. Do not run this script directly."
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

DLOOP_STATUS_FILE="/tmp/dlv-loop-status"
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

while :; do
	echo "Starting Delve headless server loop in DAP mode. To stop use: \$ ds"
	#echo "Ignore pattern: ${PRINT_PATTERNS}"

	function safe() {
		set +e
		eval "$1"
		set -e
	}

	dlv_binary=""
	safe dlv_binary="$(which dlv)"
	if [[ "${dlv_binary}" == "" ]]; then
		echo "Unable to locate Delve/DLV binary. Waiting for deploy..."
		while [[ "${dlv_binary}" == "" ]]; do
			sleep 1
			safe dlv_binary="$(which dlv)"
		done
	fi

	sh -c "${dlv_binary} dap --listen=:{TARGET_IPPORT} --api-version=2 --log 2>&1 | grep -v \"${IGNORE_PATTERN}\"" &
	dlv_pid="$!"
	unset dlv_binary

	echo "${dlv_pid}" >"${DLOOP_STATUS_FILE}"
	wait "${dlv_pid}" >/dev/null 2>&1
	unset dlv_pid

	count="5"
	while [[ "${count}" != "0" ]]; do
		count=$((count - 1))
		if [[ ! -f "${DLOOP_STATUS_FILE}" ]]; then
			exit "0"
		fi
		sleep 0.2
	done
	unset count

	echo
	echo
	echo
done
