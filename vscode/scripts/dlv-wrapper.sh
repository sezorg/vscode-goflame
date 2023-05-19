#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# GO Delve debugger wrapper.
#
# Log messages are stored into file:///var/tmp/go-wrapper.log

set -euo pipefail

MESSAGE_SOURCE="dlv-wrapper"

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/go-environment.sh"
xunreferenced_variables "${MESSAGE_SOURCE}"

xdebug "Dlv Args: $*"

xflash_pending_commands
xexec "${LOCAL_DLVBIN}" "$@"
xexit
