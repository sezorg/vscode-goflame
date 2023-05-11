#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Deploy binary & start delve in DAP mode

set -euo pipefail

WRAPPER_TYPE="launch-delve"

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/env.sh"
xunreferenced_variables "${WRAPPER_TYPE}"

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

xval XECHO_ENABLED=y
xecho "Building & deploying ${PI}${TARGET_BIN_NAME}${PO} to remote host ${PI}${TARGET_USER}@${TARGET_IPADDR}${PO}"
xbuild
xsstop
xpstop
xfcopy
xecho "Starting Delve on remote host..."
xpstart
xflash
