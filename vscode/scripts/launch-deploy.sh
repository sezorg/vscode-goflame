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

DEPLOY_DELVE=n
DEPLOY_NGINX=n
DEPLOY_MEDIAD=n

# List of services to be stopped
SERVICES_STOP=(
#	"onvifd" 
)

# List of services to be started
SERVICES_START=()

# List of process names to be stopped
PROCESSES_STOP=(
#	"${TARGET_BIN_SOURCE}" 
#	"${TARGET_BIN_NAME}"
)

# List of directories to be created
DIRECTORIES_CREATE=()

# List of files to be copied, "source|target"
COPY_FILES=(
	"init/onvifd.conf|:/etc/onvifd.conf"
	"${TARGET_BIN_SOURCE}|:${TARGET_BIN_DESTIN}"
)

if [[ "${DEPLOY_DELVE}" == "y" ]]; then
	COPY_FILES+=(
		".vscode/scripts/dlv-loop.sh|:/usr/bin/dloop"
		".vscode/scripts/dlv-stop.sh|:/usr/bin/dstop"
		"${BUILDROOT_TARGET_DIR}/usr/bin/dlv|:/usr/bin/dlv"
	)
fi

if [[ "${DEPLOY_NGINX}" == "y" ]]; then
	SERVICES_STOP+=("nginx") 
	SERVICES_START+=("nginx") 
	COPY_FILES+=(
		"${BUILDROOT_TARGET_DIR}/usr/sbin/nginx|:/usr/sbin/nginx"
		"init/ipcam.conf|:/etc/nginx/ipcam.conf"
		"init/ipcam.tmpl|:/var/lib/onvifd/ipcam.tmpl"
		"?init/users.digest|:/var/lib/onvifd/users.digest"
	)

fi

if [ "${DEPLOY_MEDIAD}" == "y" ]; then
	SERVICES_STOP+=("mediad") 
	SERVICES_START+=("mediad") 
	COPY_FILES+=("${HOME}/Workspace/elvees/work/ecam03_rel0/buildroot/output/target/usr/bin/mediad|:/usr/bin/mediad")
	:
fi

xunreferenced_variables \
	"${SERVICES_STOP[@]}" \
	"${PROCESSES_STOP[@]}" \
	"${COPY_FILES[@]}"

xval XECHO_ENABLED=y
clear
xbuild
xecho "Building & deploying ${PI}${TARGET_BIN_NAME}${PO} to remote host http://${TARGET_IPADDR}"
xsstop
xpstop
xmkdirs
xfcopy
xsstart
xflash
