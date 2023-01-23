#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Deploy binary to remote host (Delve should run in infinite loop)

set -euo pipefail

WRAPPER_TYPE="launch-deploy"

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/env.sh"
xunreferenced_variables "${WRAPPER_TYPE}"

# List of services to be stopped
SERVICES_STOP=(
	"onvifd" 
#	"onvifd-debug"
)

# List of process names to be stopped
PROCESSES_STOP=("${TARGET_BIN_SOURCE}" "${TARGET_BIN_NAME}")

# List of files to be copied, "source|target"
COPY_FILES=(
	".vscode/scripts/dlv-loop.sh|:/usr/bin/dloop"
	".vscode/scripts/dlv-stop.sh|:/usr/bin/dstop"
	"${TARGET_BIN_SOURCE}|:${TARGET_BIN_DESTIN}")

xunreferenced_variables \
	"${SERVICES_STOP[@]}" \
	"${PROCESSES_STOP[@]}" \
	"${COPY_FILES[@]}"

xval XECHO_ENABLED=y
clear
xbuild
xecho "Deploying ${PI}${TARGET_BIN_NAME}${PO} to remote host ${PI}${TARGET_USER}@${TARGET_IPADDR}${PO}"
xsstop
xpstop
xfcopy

exit 0

DLOOP_STATUS_FILE="/tmp/dlv-loop-status"
DLOOP_RESULT_FILE="/tmp/dlv-loop-current"

if [ -f "${DLOOP_RESULT_FILE}" ]; then
	rm -f "${DLOOP_RESULT_FILE}"
fi

xfcopy "[CANFAIL]" ":${DLOOP_STATUS_FILE}|${DLOOP_RESULT_FILE}"

function nh { nohup "$@" &>/dev/null & }

if [ ! -f "${DLOOP_RESULT_FILE}" ]; then
	KDE_KONSOLE="$(which konsole)"
	if [ "${KDE_KONSOLE}" != "" ]; then
	xecho "Starting dloop"
		set -x
		#"${KDE_KONSOLE}" -e "$SHELL" --rcfile <(echo "sshpass -p \"${TARGET_PASS}\" ssh -o StrictHostKeyChecking=no ${TARGET_USER}@${TARGET_IPADDR} dloop ;ls;echo hi")
		#"${KDE_KONSOLE}" -e "$SHELL" --rcfile <(echo "sshpass -p \"${TARGET_PASS}\" ssh -o StrictHostKeyChecking=no ${TARGET_USER}@${TARGET_IPADDR} dloop ;ls;echo hi") &>/dev/null 
		"${KDE_KONSOLE}" -e "$SHELL" --rcfile <(echo "cd /;ls;echo hi") &>/dev/null &
		#nohup "${KDE_KONSOLE}" -e "$SHELL" --rcfile <(echo "cd /;ls;echo hi") &>/dev/null &
		#nohup "${KDE_KONSOLE}" -e "$SHELL" --rcfile <(sshpass -p "${TARGET_PASS}" ssh -o StrictHostKeyChecking=no ${TARGET_USER}@${TARGET_IPADDR}; echo "cd /;ls;echo hi") &> /dev/null
		#nohup "\"${KDE_KONSOLE}\" -e \"$SHELL\" --rcfile <(echo \"cd /;ls;echo hi\")" &>/dev/null &
	fi
fi

#xssh "if [ -f \"${DLOOP_STATUS_FILE}\" ]; then echo 1; else echo 
