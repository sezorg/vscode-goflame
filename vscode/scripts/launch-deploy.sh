#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Deploy binary to remote host (Delve should run in infinite loop)

set -euo pipefail

WRAPPER_TYPE="launch-deploy"

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/env.sh"
xunreferenced_variables "${WRAPPER_TYPE}"

# List of services to be stopped
SERVICES_STOP=(
	"onvifd" 
#	"onvifd-debug"
)

# List of process names to be stopped
PROCESSES_STOP=("${TARGET_BIN_SOURCE}" "${TARGET_BIN_NAME}")

# List of files to be copied, "source|target"
COPY_FILES=(
	".vscode/scripts/dlv-loop.sh|:/usr/bin/dloop"
	".vscode/scripts/dlv-stop.sh|:/usr/bin/dstop"
	"${TARGET_BIN_SOURCE}|:${TARGET_BIN_DESTIN}")

xunreferenced_variables \
	"${SERVICES_STOP[@]}" \
	"${PROCESSES_STOP[@]}" \
	"${COPY_FILES[@]}"

xval XECHO_ENABLED=y
clear
xbuild
xecho "Deploying ${PI}${TARGET_BIN_NAME}${PO} to remote host ${PI}${TARGET_USER}@${TARGET_IPADDR}${PO}"
xsstop
xpstop
xfcopy
