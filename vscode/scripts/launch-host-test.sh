#!/usr/bin/env bash
# Copyright 2024 RnD Center "ELVEES", JSC
#
# Prepare debugging environment on x86_64 platform.
#
# Log messages are stored into file:///var/tmp/goflame/go-wrapper.log

set -euo pipefail

TARGET_ARCH="host"

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/go-runtime.sh"

XECHO_ENABLED=true
#xrm ".vscode/launch/lib/onvifd/state.toml"
xexec mkdir -p ".vscode/launch/lib/onvifd/keystore"

TARGET_BUILD_GOFLAGS=(
	"-C" "$PWD" # -C flag must be first flag on command line
	"-o" "./onvifd"
	"${TARGET_BUILD_GOFLAGS[@]}"
)

TARGET_BUILD_LDFLAGS=(
	"-X main.currentVersion=custom"
	"-X main.sysConfDir=./.vscode/launch"
	"-X main.localStateDir=./.vscode/launch"
)

xperform_build_and_deploy "[ECHO]" "[BUILD]" "[TEST]" \
	"Building & deploying $(xdecorate "$TARGET_BIN_NAME")"
