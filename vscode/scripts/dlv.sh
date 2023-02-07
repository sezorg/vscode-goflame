#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# GO Delve debugger wrapper.

set -euo pipefail

WRAPPER_TYPE="dlv"

# Include Golang environment  
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "${SCRIPT_DIR}/env.sh"
xunreferenced_variables "${WRAPPER_TYPE}"

xflash
xexec "${LOCAL_DLVBIN}" "$@"
xexit
