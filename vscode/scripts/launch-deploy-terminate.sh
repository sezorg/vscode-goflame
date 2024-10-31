#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Terminate running remote app.
#
# Log messages are stored into file:///var/tmp/goflame/go-wrapper.log

set -euo pipefail

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/go-runtime.sh"

xresolve_target_config false
xssh rm -f "$DLOOP_RESTART_FILE"
exit "$EXEC_STATUS"
