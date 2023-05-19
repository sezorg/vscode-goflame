#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# GO compiler wrapper.
#
# Log messages are stored into file:///var/tmp/go-wrapper.log

set -euo pipefail

MESSAGE_SOURCE="go-wrapper"

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "${SCRIPT_DIR}/go-environment.sh"
xunreferenced_variables "${MESSAGE_SOURCE}"

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
	".vscode/data/onvifd_debug.service|:/usr/lib/systemd/system/onvifd_debug.service"
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

function xparse_go_arguments() {
	local dirty=
	local result=()
	xdebug "Go Args: ${SRCIPT_ARGS[*]}"
	for ((i = 0; i < ${#SRCIPT_ARGS[@]}; i++)); do
		item="${SRCIPT_ARGS[$i]}"
		if [[ "${item}" == "${DLVBIN}" ]]; then
			result+=("${LOCAL_DLVBIN}")
			dirty="y"
		elif [[ "${item}" == "build" ]]; then
			xval XECHO_ENABLED=y
			xecho "Building \`${TARGET_BUILD_LAUNCHER}'"
			result+=("${item}")
			dirty="y"
			HAVE_BUILD="y"
		elif [[ "${item}" == "install" ]]; then
			xval HAVE_INSTALL="y"
			result+=("${item}")
		elif [[ "${item}" == "--echo" ]]; then
			xval XECHO_ENABLED="y"
			dirty="y"
		elif [[ "${item}" == "--debug" ]]; then
			xval XDEBUG_ENABLED="y"
			dirty="y"
		elif [[ "${item}" == "--trace" ]]; then
			set -x
			dirty="y"
		else
			result+=("${item}")
		fi
	done

	if [[ "${dirty}" != "" ]]; then
		if [[ "${HAVE_BUILD}" != "" ]]; then
			# force debug build
			result+=("${TARGET_BUILD_FLAGS[@]}")
		fi
		SRCIPT_ARGS=("${result[@]}")
		xdebug "Dirty args: ${ORIGINAL_GOBIN} ${SRCIPT_ARGS[*]}"
		return 0
	fi
	return 1
}

if xparse_go_arguments; then
	set "${SRCIPT_ARGS[@]}"
	xdebug "New Args: $*"
fi

if [[ "${HAVE_BUILD}" != "" ]]; then
	xexport "${GOLANG_EXPORTS[@]}"
fi

if [[ "${HAVE_INSTALL}" != "" ]]; then
	xunreferenced_variables
fi

if [[ ! -f "${ORIGINAL_GOBIN}" ]]; then
	xecho "ERROR: Can not find Go executable at \"${ORIGINAL_GOBIN}\"."
	xecho "ERROR: Check BUILDROOT_DIR variable in your \"config.ini\"."
	lookup_dir=$(find "${BUILDROOT_DIR}" -name "using-buildroot-toolchain.txt" -maxdepth 5)
	xdebug "Actual BUILDROOT_DIR=\"${BUILDROOT_DIR}\""
	xdebug "Found buildroot doc file: ${lookup_dir}"
	if [[ "${lookup_dir}" != "" ]]; then
		lookup_dir="$(dirname "${lookup_dir}")"
		lookup_dir="$(dirname "${lookup_dir}")"
		lookup_dir="$(dirname "${lookup_dir}")"
		xecho "HINT: Set BUILDROOT_DIR=\"${lookup_dir}\"."
	fi
	exit "1"
fi

# Exdcute original Golang command
xexec "${ORIGINAL_GOBIN}" "$@"

if [[ "${HAVE_BUILD}" != "" ]]; then
	if [[ "${EXEC_STATUS}" == "0" ]]; then
		if [[ -f "./${TARGET_BIN_SOURCE}" ]]; then
			xexec cp "${PWD}/.vscode/scripts/dlv-loop.sh" "/var/tmp/dlv-loop.sh"
			xexec sed -i "s/{TARGET_IPPORT}/${TARGET_IPPORT}/" "/var/tmp/dlv-loop.sh"
			xcamera_features "true" "videoanalytics" "audio"
			xperform_build_and_deploy "Installing ${PI}${TARGET_BIN_NAME}${PO} to remote host http://${TARGET_IPADDR}"
			exit "0"
		else
			xecho "ERROR: Main executable ${PI}${TARGET_BIN_SOURCE}${PO} does not exist"
			exit "1"
		fi
	fi
fi

xexit
