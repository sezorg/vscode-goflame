#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Run Delve infinite loop on remote host

set -euo pipefail

WRAPPER_TYPE="remote-delve"

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/env.sh"
xunreferenced_variables "${WRAPPER_TYPE}"

# List of process names to be stopped
PROCESSES_STOP=("dlv")

# List of processed to be started, executable with args
PROCESSES_START=("2>&1 dloop")

# List of files to be copied, "source|target"
COPY_FILES=(
	".vscode/scripts/dlv-loop.sh|:/usr/bin/dloop"
	".vscode/scripts/dlv-stop.sh|:/usr/bin/dstop")

xunreferenced_variables \
	"${PROCESSES_STOP[@]}" \
	"${PROCESSES_START[@]}" \
	"${COPY_FILES[@]}"

xval XECHO_ENABLED=y
xpstop
xfcopy
xecho "Starting Delve loop on remote host..."
xpstart
