#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# GO Delve debugger wrapper.

set -euo pipefail

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/go-runtime.sh"

xdebug "Dlv Args: $*"
xflash_pending_commands
xexec "$LOCAL_DLVBIN" "$@"
xexec_exit
