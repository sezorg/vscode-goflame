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

XECHO_ENABLED=true
GOLANGCI_LINT_ENABLE=true
STATICCHECK_ENABLE=true
GO_VET_ENABLE=true
LLENCHECK_ENABLE=true
PRECOMMIT_ENABLE=true
CLEAN_GOCACHE=true

xcheck_project true
xexit
