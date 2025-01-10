#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Deploy binary to remote host (Delve should run in infinite loop)

set -euo pipefail

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/go-runtime.sh"

# List of files to be copied, "source|target"
COPY_FILES+=(
	"$TARGET_BIN_SOURCE|:$TARGET_BIN_DESTIN"
)

EXECUTE_STUB_PATH="$P_TEMP_DIR"
EXECUTE_STUB_NAME="$EXECUTE_STUB_PATH/go-exec-stub"
if [[ ! -f "$EXECUTE_STUB_NAME" ]]; then
	xexec mkdir -p "$EXECUTE_STUB_PATH"
	xexec go build -o "$EXECUTE_STUB_NAME" \
		"$PWD/.vscode/scripts/go-exec-stub.go"
fi

xunreferenced \
	"${SERVICES_STOP[@]}" \
	"${PROCESSES_STOP[@]}" \
	"${COPY_FILES[@]}"

xprepare_runtime_scripts
xperform_build_and_deploy "[ECHO]" "[BUILD]" "[EXEC]" \
	"Building & executing $(xdecorate "$TARGET_BIN_NAME")"
