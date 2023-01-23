#!/usr/bin/env bash/c/tools/onvifd/+/34834/12/pkg/configuration/configuration.go
# Copyright 2022 RnD RnD Center "ELVEES", JSC
#
# Stop Delve loop started with `dstart'

set -euo pipefail
#set "-x"

DLOOP_STATUS_FILE="/tmp/dlv-loop-status"
if [ -f "${DLOOP_STATUS_FILE}" ]; then
	dlv_pid="$(cat "${DLOOP_STATUS_FILE}")"
	rm -f "${DLOOP_STATUS_FILE}"
	function xnull() { return 0; }
	xnull "$(pkill -P "${dlv_pid}")"
	xnull "$(kill "${dlv_pid}")"
	unset dlv_pid
fi
