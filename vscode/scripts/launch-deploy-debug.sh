#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Deploy binary to remote host (Delve should run in infinite loop)

set -euo pipefail

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/go-runtime.sh"

# List of services to be stopped
SERVICES_STOP+=(
	#"onvifd"
)

# List of services to be started
SERVICES_START+=()

# List of process names to be stopped
PROCESSES_STOP+=(
	#"$TARGET_BIN_SOURCE"
	#"$TARGET_BIN_NAME"
)

# List of directories to be created
DIRECTORIES_CREATE+=()

# List of files to be copied, "source|target"
COPY_FILES+=(
	"$TARGET_BIN_SOURCE|:$TARGET_BIN_DESTIN"
)

# Advised target scripts that the initial upload deploy is complete.
EXECUTE_COMMANDS+=(
)

xunreferenced \
	"${SERVICES_STOP[@]}" \
	"${PROCESSES_STOP[@]}" \
	"${COPY_FILES[@]}"

xperform_build_and_deploy "[ECHO]" "[BUILD]" "[DEBUG]" \
	"Building & deploying $(xdecorate "$TARGET_BIN_NAME")"
