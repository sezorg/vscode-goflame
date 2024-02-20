#!/usr/bin/env bash
# Copyright 2024 RnD Center "ELVEES", JSC
#
# Prepare debugging environment on x86_64 platform.
#
# Log messages are stored into file:///var/tmp/goflame/go-wrapper.log

set -euo pipefail

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/go-runtime.sh"

XECHO_ENABLED=true
xrm ".vscode/launch/lib/onvifd/state.toml"
