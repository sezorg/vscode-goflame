#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Terminate running remote app.

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

xperform_build_and_deploy "[ECHO]" "[CHECK]" "Linting $(xdecorate "$TARGET_BIN_NAME")"
