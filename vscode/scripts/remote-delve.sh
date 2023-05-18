#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Run Delve infinite loop on remote host
#
# Log messages are stored into file:///var/tmp/go-wrapper.log

set -euo pipefail

MESSAGE_SOURCE="remote-delve"

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/go-environment.sh"
xunreferenced_variables "${MESSAGE_SOURCE}"

# List of process names to be stopped
PROCESSES_STOP=("dlv")

# List of processed to be started, executable with args
PROCESSES_START=("2>&1 dloop")

# List of files to be copied, "source|target"
COPY_FILES=(
	".vscode/scripts/dlv-loop.sh|:/usr/bin/dl"
	".vscode/scripts/dlv-stop.sh|:/usr/bin/ds"
	"init/onvifd.conf|:/etc/onvifd.conf"
	)

xunreferenced_variables \
	"${PROCESSES_STOP[@]}" \
	"${PROCESSES_START[@]}" \
	"${COPY_FILES[@]}"

xperform_build_and_deploy "[ECHO]" "[BUILD]" \
	"Building & deploying ${PI}${TARGET_BIN_NAME}${PO} to remote host http://${TARGET_IPADDR}"
