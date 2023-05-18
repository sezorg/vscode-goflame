#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# GO compiler wrapper.

set -euo pipefail

WRAPPER_TYPE="go"

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/env.sh"
xunreferenced_variables "${WRAPPER_TYPE}"

# List of services to be stopped
SERVICES_STOP=("onvifd" "onvifd-debug")

# List of services to be started
#SERVICES_START=("nginx")

# List of process names to be stopped
PROCESSES_STOP=("dlv" "${TARGET_BIN_SOURCE}" "${TARGET_BIN_NAME}")

# List of processed to be started, executable with args
PROCESSES_START=(
	#"nohup dlv exec ${TARGET_BIN_DESTIN} --listen=:2345 --headless=true --log=true --allow-non-terminal-interactive --log-output=debugger,debuglineerr,gdbwire,lldbout,rpc --accept-multiclient --api-version=2 -- ${TARGET_EXEC_ARGS} >${DELVE_LOGFILE} 2>&1 &"
)

#DIRECTORIES_CREATE=("/tmp/nginx/")

# List of files to be deleted
DELETE_FILES=(
	"${TARGET_BIN_DESTIN}"
	"${TARGET_LOGFILE}"
	"${DELVE_LOGFILE}")

# List of files to be copied, "source|target"
COPY_FILES=(
	"/var/tmp/dlv-loop.sh|:/usr/bin/dl"
	".vscode/scripts/dlv-stop.sh|:/usr/bin/ds"
	".vscode/scripts/onvifd-debug.service|:/usr/lib/systemd/system/onvifd-debug.service"
	"${TARGET_BIN_SOURCE}|:${TARGET_BIN_DESTIN}"
	"${BUILDROOT_TARGET_DIR}/usr/bin/dlv|:/usr/bin/dlv"
	"init/onvifd.conf|:/etc/onvifd.conf"
	#"init/onvifd.service|:/usr/lib/systemd/system/onvifd.service"
	"init/users.toml|:/var/lib/onvifd/users.toml")
COPY_CACHE=n

xunreferenced_variables \
	"${SERVICES_STOP[@]}" \
	"${SERVICES_START[@]}" \
	"${PROCESSES_STOP[@]}" \
	"${PROCESSES_START[@]}" \
	"${DELETE_FILES[@]}" \
	"${COPY_FILES[@]}"

SRCIPT_ARGS=("$@")
HAVE_BUILD=
HAVE_INSTALL=

function xparseargs() {
	local dirty=
	local result=()
	xdebug "Args: ${SRCIPT_ARGS[*]}"
	for ((i = 0; i < ${#SRCIPT_ARGS[@]}; i++)); do
		item="${SRCIPT_ARGS[$i]}"
		if [ "${item}" == "${DLVBIN}" ]; then
			result+=("${LOCAL_DLVBIN}")
			dirty="y"
		elif [ "${item}" == "build" ]; then
			xval XECHO_ENABLED=y
			xecho "Building \`${TARGET_BUILD_LAUNCHER}'"
			result+=("${item}")
			dirty="y"
			HAVE_BUILD="y"
		elif [ "${item}" == "install" ]; then
			xval HAVE_INSTALL="y"
			result+=("${item}")
		elif [ "${item}" == "--echo" ]; then
			xval XECHO_ENABLED="y"
			dirty="y"
		elif [ "${item}" == "--debug" ]; then
			xval XDEBUG_ENABLED="y"
			dirty="y"
		elif [ "${item}" == "--trace" ]; then
			set -x
			dirty="y"
		else
			result+=("${item}")
		fi
	done

	if [ "${dirty}" != "" ]; then
		if [ "${HAVE_BUILD}" != "" ]; then
			# force debug build
			result+=("${TARGET_BUILD_FLAGS[@]}")
		fi
		SRCIPT_ARGS=("${result[@]}")
		xdebug "Dirty args: ${ORIGINAL_GOBIN} ${SRCIPT_ARGS[*]}"
		return 0
	fi
	return 1
}

if xparseargs; then
	set "${SRCIPT_ARGS[@]}"
	xdebug "New Args: $*"
fi

if [ "${HAVE_BUILD}" != "" ]; then
	xexport "${GOLANG_EXPORTS[@]}"
fi

if [ "${HAVE_INSTALL}" != "" ]; then
	xunreferenced_variables
fi

function xcamera_feature() {
	local response
	local timeout=2
	local wget_command=(timeout "${timeout}" wget --no-proxy --timeout="${timeout}" "http://${TARGET_IPADDR}/cgi/features.cgi?$1=$2" -q -O -)
	xdebug "Run Action: ${wget_command[*]}"
	response=$("${wget_command[@]}")
	local pattern="\"$1\": set to $2"
	if grep -i -q "$pattern" <<< "$response"; then
		xecho "Camera feature \"$1\" is set to \"$2\"."
	else
		xecho "WARNING: Failed to set camera feature \"$1\" to \"$2\"."
	fi
}

if [[ ! -f "${ORIGINAL_GOBIN}" ]]; then
	xecho "ERROR: Can not find Go executable at \"${ORIGINAL_GOBIN}\"."
	xecho "ERROR: Check BUILDROOT_DIR variable in your \"config.ini\"."
	exit 1
fi

# Exdcute original Golang command
xexec "${ORIGINAL_GOBIN}" "$@"

if [ "${HAVE_BUILD}" != "" ]; then
	if [ "${EXEC_STATUS}" == "0" ]; then
		xecho "Installing to remote host ${PI}${TARGET_USER}@${TARGET_IPADDR}${PO}"
		if [ -f "./${TARGET_BIN_SOURCE}" ]; then

			cp "${PWD}/.vscode/scripts/dlv-loop.sh" "/var/tmp/dlv-loop.sh"
			sed -i "s/{TARGET_IPPORT}/${TARGET_IPPORT}/" "/var/tmp/dlv-loop.sh"

			xcamera_feature "videoanalytics" "true"
			xsstop
			xpstop
			xfdel
			xfcopy
			xmkdirs
			xsstart
			xpstart
			xflash
			exit "1"
		else
			xecho "ERROR: Main executable ${PI}${TARGET_BIN_SOURCE}${PO} does not exist"
			exit "1"
		fi
	fi
fi

xexit
