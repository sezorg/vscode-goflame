#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Deploy binary to remote host (Delve should run in infinite loop)
#
# Log messages are stored into file:///var/tmp/goflame/go-wrapper.log

set -euo pipefail

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/go-runtime.sh"

DEPLOY_DELVE=n
DEPLOY_NGINX=n
DEPLOY_MEDIAD=n

# List of services to be stopped
SERVICES_STOP+=(
	#"onvifd"
)

# List of services to be started
SERVICES_START+=()

# List of process names to be stopped
PROCESSES_STOP+=(
	#"$TARGET_BIN_SOURCE"
	#"$TARGET_BIN_NAME"
)

# List of directories to be created
DIRECTORIES_CREATE+=()

# List of files to be copied, "source|target"
COPY_FILES+=(
	"$TARGET_BIN_SOURCE|:$TARGET_BIN_DESTIN"
)

if xis_true "$DEPLOY_DELVE"; then
	COPY_FILES+=(
		"$BUILDROOT_TARGET_DIR/usr/bin/dlv|:/usr/bin/dlv"
	)
fi

# Advised target stripts that the initial upload deploy is complete.
EXECUTE_COMMANDS+=(
)

if xis_true "$DEPLOY_NGINX"; then
	SERVICES_STOP+=("nginx")
	SERVICES_START+=("nginx")
	COPY_FILES+=(
		"$BUILDROOT_TARGET_DIR/usr/sbin/nginx|:/usr/sbin/nginx"
		"init/ipcam.conf|:/etc/nginx/ipcam.conf"
		"init/ipcam.tmpl|:/var/lib/onvifd/ipcam.tmpl"
		"?init/users.digest|:/var/lib/onvifd/users.digest"
	)

fi

if xis_true "$DEPLOY_MEDIAD"; then
	SERVICES_STOP+=("mediad")
	SERVICES_START+=("mediad")
	COPY_FILES+=("$BUILDROOT_TARGET_DIR/usr/bin/mediad|:/usr/bin/mediad")
fi

xunreferenced \
	"${SERVICES_STOP[@]}" \
	"${PROCESSES_STOP[@]}" \
	"${COPY_FILES[@]}"

xperform_build_and_deploy "[ECHO]" "[BUILD]" "[DEBUG]" \
	"Building & deploying $(xdecorate "$TARGET_BIN_NAME") to remote host"
