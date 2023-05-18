#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Deploy binary & start delve in DAP mode
#
# Log messages are stored into file:///var/tmp/go-wrapper.log

set -euo pipefail

MESSAGE_SOURCE="launch-remote-delve"

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/go-environment.sh"
xunreferenced_variables "${MESSAGE_SOURCE}"

# List of services to be stopped
SERVICES_STOP=("onvifd" "onvifd-debug")

# List of process names to be stopped
PROCESSES_STOP=("dlv" "${TARGET_BIN_SOURCE}" "${TARGET_BIN_NAME}")

# List of processed to be started, executable with args
PROCESSES_START=("nohup dlv dap --listen=:2345 --api-version=2 --log >/dev/null 2>&1 &")

# List of files to be copied, "source|target"
COPY_FILES=("${TARGET_BIN_SOURCE}|:${TARGET_BIN_DESTIN}")

xunreferenced_variables \
	"${SERVICES_STOP[@]}" \
	"${PROCESSES_STOP[@]}" \
	"${PROCESSES_START[@]}" \
	"${COPY_FILES[@]}"

xperform_build_and_deploy "[ECHO]" "[BUILD]" \
	"Building & deploying ${PI}${TARGET_BIN_NAME}${PO} to remote host http://${TARGET_IPADDR}"
