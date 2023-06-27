#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Terminate running remote app.
#
# Log messages are stored into file:///var/tmp/go-wrapper.log

set -euo pipefail

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/go-runtime.sh"
xmessage_source "launch-go-staticcheck"

xval XECHO_ENABLED=y
checks=()
if [[ "${STATICCHECK_CHECKS}" != "" ]]; then
	xecho "Running static checks: \"${STATICCHECK_CHECKS}\"."
	checks+=("-checks" "${STATICCHECK_CHECKS}")
else
	xecho "Running default static checks..."
fi

xexec staticcheck "${checks[@]}" "./..."
if [[ "${EXEC_STATUS}" == "0" ]]; then
	xecho "Finished. No issues reported."
fi
xexit
