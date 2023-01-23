#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Run Delve in inifinite DAP loop with local console capture
# To terminate use `dstop' command

set -euo pipefail
#set "-x"

IGNORE_LIST=(
	# -- Application startup messages
	"warning layer=rpc Listening for remote connections"
	#"concrete subprogram without address range at"
	#"inlined call without address range at"
	" without address range at "
	"debug layer=debugger"
	"info layer=debugger created breakpoint:"
	"info layer=debugger cleared breakpoint:"
	# -- Interactive debuger related messages
	"Failed to execute cursor closing: ERROR: cursor"
)

IGNORE_PATTERN="$(printf "\n%s" "${IGNORE_LIST[@]}")"
IGNORE_PATTERN="${IGNORE_PATTERN:1}"
PRINT_PATTERNS="$(printf ",\"%s\"" "${IGNORE_LIST[@]}")"
PRINT_PATTERNS="${PRINT_PATTERNS:1}"

DLOOP_STATUS_FILE="/tmp/dlv-loop-status"
function cleanup() {
	rm -f "${DLOOP_STATUS_FILE}"
}
trap cleanup EXIT

if [ -f "${DLOOP_STATUS_FILE}" ]; then
	dlv_pid="$(cat "${DLOOP_STATUS_FILE}")"
	rm -f "${DLOOP_STATUS_FILE}"
	function xnull() { return 0; }
	xnull "$(pkill -P "${dlv_pid} >/dev/null")"
	xnull "$(kill "${dlv_pid} >/dev/null")"
	unset dlv_pid
fi

while :; do
	echo "Starting Delve headless server loop in DAP mode. To stop use: \$ dstop"
	#echo "Ignore pattern: ${PRINT_PATTERNS}"

	sh -c "dlv dap --listen=:2345 --api-version=2 --log 2>&1 | grep -v \"${IGNORE_PATTERN}\"" &
	dlv_pid="$!"
	echo "${dlv_pid}" >"${DLOOP_STATUS_FILE}"
	wait "${dlv_pid}" >/dev/null 2>&1
	unset dlv_pid

	count="10"
	while [ "${count}" != "0" ]; do
		count=$((count - 1))
		if [ ! -f "${DLOOP_STATUS_FILE}" ]; then
			exit 0
		fi
		sleep 0.1
	done
	unset count

	echo
	echo
	echo
done
