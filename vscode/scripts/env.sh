#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# GO compiler wrapper environment

set -euo pipefail

if [ ! -f "${HOME}/.shellcheckrc" ]; then
	echo "external-sources=true" >"${HOME}/.shellcheckrc"
fi

function xval() {
	eval "$*"
}

# To omit shellcheck warnings
function xunreferenced_variables() {
	return 0
}

XECHO_ENABLED=
XDEBUG_ENABLED=
DT="$(date '+%d/%m/%Y %H:%M:%S') "
CE=$'\u1B' # Color escape
EP=""
PI="\`"
PO="'"
xunreferenced_variables "${DT}" "${CE}" "${EP}"

TARGET_IPADDR="UNKNOWN-TARGET_IPADDR"
TARGET_IPPORT="UNKNOWN-TARGET_IPPORT"
TARGET_USER="UNKNOWN-TARGET_USER"
TARGET_PASS="UNKNOWN-TARGET_PASS"
BUILDROOT_DIR="UNKNOWN-BUILDROOT_DIR"

source "${SCRIPT_DIR}/../config.ini"

TARGET_BUILD_LAUNCHER="cmd/onvifd/onvifd.go"
TARGET_BUILD_GOFLAGS=(
	"-gcflags=-N"
	"-gcflags=-l")
TARGET_BUILD_LDFLAGS=(
	"-X main.currentVersion=custom"
	"-X main.sysConfDir=/etc"
	"-X main.localStateDir=/var")

TARGET_BUILD_FLAGS=("${TARGET_BUILD_GOFLAGS[@]}")
if [ "${#TARGET_BUILD_LDFLAGS[@]}" != "0" ]; then
	TARGET_BUILD_FLAGS+=("-ldflags \"${TARGET_BUILD_LDFLAGS[@]}\"")
fi
if [ "${TARGET_BUILD_LAUNCHER}" != "" ]; then
	TARGET_BUILD_FLAGS+=("${TARGET_BUILD_LAUNCHER}")
fi

TARGET_BIN_SOURCE="onvifd"
TARGET_BIN_DESTIN="/usr/bin/onvifd_debug"
TARGET_BIN_NAME=$(basename -- "${TARGET_BIN_DESTIN}")
TARGET_EXEC_ARGS="-settings /root/onvifd.settings"
TARGET_LOGFILE="/var/tmp/${TARGET_BIN_NAME}.log"

DELVE_LOGFILE="/var/tmp/dlv.log"
DELVE_DAP_START="dlv dap --listen=:2345 --api-version=2 --log"

WRAPPER_LOGFILE="/var/tmp/go-wrapper.log"
if [ "$WRAPPER_TYPE" == "" ]; then
	WRAPPER_TYPE="unknown-wrapper"
fi

ORIGINAL_GOBIN="${BUILDROOT_DIR}/output/host/bin/go"
ORIGINAL_DLVBIN="$(which dlv)"

xunreferenced_variables \
	"${TARGET_BIN_SOURCE}" \
	"${TARGET_BIN_DESTIN}" \
	"${TARGET_BIN_NAME}" \
	"${TARGET_EXEC_ARGS}" \
	"${TARGET_LOGFILE}" \
	"${DELVE_LOGFILE}" \
	"${DELVE_DAP_START}" \
	"${WRAPPER_LOGFILE}" \
	"${ORIGINAL_GOBIN}" \
	"${ORIGINAL_DLVBIN}" \
	"${GOLANG_EXPORTS[@]}"

DLVBIN="${SCRIPT_DIR}/dlv.sh"
GOBIN="${SCRIPT_DIR}/go.sh"

GOROOT="${BUILDROOT_DIR}/output/host/lib/go"
GOPATH="${BUILDROOT_DIR}/output/host/usr/share/go-path"
GOMODCACHE="${BUILDROOT_DIR}/output/host/usr/share/go-path/pkg/mod"
GOTOOLDIR="${BUILDROOT_DIR}/output/host/lib/go/pkg/tool/linux_arm64"
GOCACHE="${BUILDROOT_DIR}/output/host/usr/share/go-cache"

GOPROXY="direct"
GO111MODULE="on"
GOWORK="off"
GOVCS="*:all"
GOARCH="arm64"
GOFLAGS="-mod=vendor"
GOFLAGS="-mod=mod"

CGO_ENABLED="1"
CGO_CFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O3 -g2 -D_FORTIFY_SOURCE=1"
CGO_CXXFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O3 -g2 -D_FORTIFY_SOURCE=1"
CGO_LDFLAGS=""
CC="${BUILDROOT_DIR}/output/host/bin/aarch64-buildroot-linux-gnu-gcc"
CXX="${BUILDROOT_DIR}/output/host/bin/aarch64-buildroot-linux-gnu-g++"

GOLANG_EXPORTS=(
	"DLVBIN"
	"GOBIN"

	"GOROOT"
	"GOPATH"
	"GOMODCACHE"
	"GOTOOLDIR"
	"GOCACHE"

	"GOPROXY"
	"GO111MODULE"
	"GOWORK"
	"GOVCS"
	"GOARCH"
	"GOFLAGS"
	"GOFLAGS"

	"CGO_ENABLED"
	"CGO_CFLAGS"
	"CGO_CXXFLAGS"
	"CGO_LDFLAGS"
	"CC"
	"CXX"
)

xunreferenced_variables \
	"${DLVBIN}" \
	"${GOBIN}" \
	"${GOROOT}" \
	"${GOPATH}" \
	"${GOMODCACHE}" \
	"${GOTOOLDIR}" \
	"${GOCACHE}" \
	"${GOPROXY}" \
	"${GO111MODULE}" \
	"${GOWORK}" \
	"${GOVCS}" \
	"${GOARCH}" \
	"${GOFLAGS}" \
	"${GOFLAGS}" \
	"${CGO_ENABLED}" \
	"${CGO_CFLAGS}" \
	"${CGO_CXXFLAGS}" \
	"${CGO_LDFLAGS}" \
	"${CC}" \
	"${CXX}"

function xexport() {
	xdebug "Exports: $*"
	for variable in "$@"; do
		local name="${variable}"
		local value="${!name}"
		# shellcheck disable=SC2086
		export ${name}="${value}"
	done
}

FIRST_ECHO=y

function xemit() {
	local echo_flag="$1"
	shift
	local message="${DT}[${WRAPPER_TYPE}] $*"
	if [ "${FIRST_ECHO}" == "" ]; then
		if [ "${echo_flag}" != "" ]; then
			echo >&2 "${EP}${message}"
		fi
		echo "${message}" >>"${WRAPPER_LOGFILE}"
	else
		FIRST_ECHO=
		if [ "${XECHO_ENABLED}" != "" ] || [ "${XDEBUG_ENABLED}" != "" ]; then
			echo >&2
		fi
		if [ "${echo_flag}" != "" ]; then
			echo >&2 "${EP}${message}"
		fi
		echo >>"${WRAPPER_LOGFILE}"
		echo "${message}" >>"${WRAPPER_LOGFILE}"
	fi
}

function xecho() {
	# Echo message
	xemit "${XECHO_ENABLED}" "$*"
}

function xdebug() {
	# Debug message
	xemit "${XDEBUG_ENABLED}" "DEBUG: $*"
}

EXEC_STDOUT=
EXEC_STDERR=
EXEC_STATUS=

function xexestat() {
	local prefix="${1}"
	local stdout="${2}"
	local stderr="${3}"
	local status="${4}"
	if [ "${status}" != "0" ]; then
		local needStatus="1"
		if [ "${stdout}" != "" ]; then
			xecho "${prefix} STATUS ${status}, STDOUT: ${stdout}"
			needStatus="0"
		fi
		if [ "${stderr}" != "" ]; then
			xecho "${prefix} STATUS ${status}, STDERR: ${stderr}"
			needStatus="0"
		fi
		if [ "${needStatus}" == "1" ]; then
			xecho "${prefix} STATUS: ${status}"
		fi
	else
		if [ "${stdout}" != "" ]; then
			xdebug "${prefix} STDOUT: ${stdout}"
		fi
		if [ "${2}" != "" ]; then
			xdebug "${prefix} STDERR: ${stderr}"
		fi
	fi
}

function xexec() {
	xfset "+e"
	xdebug "Exec Action: $*"
	{
		EXEC_STDOUT=$(
			chmod u+w /dev/fd/3 && # Needed for bash5.0
				eval "$*" 2>/dev/fd/3
		)
		EXEC_STATUS=$?
		EXEC_STDERR=$(cat <&3)
	} 3<<EOF
EOF
	xfunset
	#xexestat "Exec" "${EXEC_STDOUT}" "${EXEC_STDERR}" "${EXEC_STATUS}"
}

function xexit() {
	xdebug "Finishing wrapper with STDOUT, STDERR & STATUS=${EXEC_STATUS}"
	if [ "${EXEC_STDOUT}" != "" ]; then
		echo "${EXEC_STDOUT}"
	fi
	if [ "${EXEC_STDERR}" != "" ]; then
		echo "${EXEC_STDERR}" 1>&2
	fi
	exit "${EXEC_STATUS}"
}

RUN_STDOUT=
RUN_STDERR=
RUN_STATUS=

function xrun() {
	xfset "+e"
	xdebug "Run Action: $*"
	{
		RUN_STDOUT=$(
			chmod u+w /dev/fd/3 && # Needed for bash5.0
				eval "$*" 2>/dev/fd/3
		)
		RUN_STATUS=$?
		RUN_STDERR=$(cat <&3)
	} 3<<EOF
EOF
	xfunset
	xexestat "Run" "${RUN_STDOUT}" "${RUN_STDERR}" "${RUN_STATUS}"
}

CANFAIL="[CANFAIL]"
OPTIONS_STACK=()

function xfset() {
	local oldopts
	oldopts="$(set +o)"
	OPTIONS_STACK+=("${oldopts}")
	for opt in "$@"; do
		set "${opt}"
	done
}

function xfunset() {
	local oldopts="${OPTIONS_STACK[-1]}"
	set +vx
	eval "${oldopts}"
	unset "OPTIONS_STACK[-1]"
}

function xsshexec() {
	local canfail=
	if [ "${1:-}" == "${CANFAIL}" ]; then
		canfail="$1"
		shift
	fi

	xrun sshpass -p "${TARGET_PASS}" ssh -o StrictHostKeyChecking=no ${TARGET_USER}@${TARGET_IPADDR} "\"$*\""

	if [ "${RUN_STATUS}" != "0" ] && [ "${canfail}" == "" ]; then
		xecho "Failed. Terminating with status ${RUN_STATUS}"
		exit ${RUN_STATUS}
	fi
}

function xssh() {
	xdebug "Target exec: $*"
	xsshexec "$@"
}

function xkill() {
	local canfail=
	if [ "${1:-}" == "${CANFAIL}" ]; then
		canfail="$1"
		shift
	fi

	local command=""
	for procname in "$@"; do
		command="${command} && (if pgrep ${procname} > /dev/null; then pkill ${procname}; fi)"
	done
	xdebug "Target kill: ${canfail} ${command:4}"
	xsshexec "${canfail}" "${command:4}"
}

function xscp() {
	local canfail=
	if [ "${1:-}" == "${CANFAIL}" ]; then
		canfail="$1"
		shift
	fi

	local dir="${TARGET_USER}@${TARGET_IPADDR}"

	local one="$1"
	if [[ "$one" =~ ^\:.* ]]; then
		one="${dir}${one}"
	elif [[ ! "$one" =~ ^\/.* ]]; then
		one="./${one}"
	fi

	local two="$2"
	if [[ "$two" =~ ^\:.* ]]; then
		two="${dir}${two}"
	elif [[ ! "$two" =~ ^\/.* ]]; then
		two="./${two}"
	fi

	xdebug "Target copy: ${canfail} ${one} -> ${two}"
	sshpass -p "${TARGET_PASS}" scp -C -o StrictHostKeyChecking=no "${one}" "${two}"

	if [ "${RUN_STATUS}" != "0" ] && [ "${canfail}" == "" ]; then
		xecho "Failed. Terminating with status ${RUN_STATUS}"
		exit ${RUN_STATUS}
	fi
}

function xconn() {
	xdebug "Checking connectivity..."
	xssh uname -a
}

# List of files to be deleted
DELETE_FILES=()

function xfdel() {
	# Delete files from DELETE_FILES
	xfdelv "${DELETE_FILES[@]}"
}

# shellcheck disable=SC2120
function xfdelv() {
	local list=("$@")
	if [ "${#list[@]}" != "0" ]; then
		local command=""
		local cmdList=""
		for filename in "${list[@]}"; do
			command="${command} || (if [ -f \"${filename}\" ]; then rm -f \"${filename}\"; fi)"
			cmdList="${cmdList}, $(basename -- "$filename")" 
		done
		xecho "Removing ${#list[@]} files: ${cmdList:2}"
		xssh "${command:4}"
	fi
}

# List of files to be copied, "source|target"
COPY_FILES=()

# shellcheck disable=SC2120
function xfcopy() {
	# Copy files from COPY_FILES
	local canfail=
	if [ "${1:-}" == "${CANFAIL}" ]; then
		canfail="$1"
		shift
	fi

	local list=("$@")
	if [ "${#list[@]}" == "0" ]; then
		list=("${COPY_FILES[@]}")
	fi
	if [ "${#list[@]}" != "0" ]; then
		local command=""
		local cmdList=""
		for pair in "${list[@]}"; do
			IFS='|'
			# shellcheck disable=SC2206
			files=($pair)
			unset IFS
			local fileA="${files[0]}"
			local fileB="${files[1]}"
			if [[ "$fileB" =~ ^\:.* ]]; then
				command="${command} || (if [ -f \"${fileB:1}\" ]; then rm -f \"${fileB:1}\"; fi)"
			fi
			cmdList="${cmdList}, $(basename -- "$fileB")"
		done
		if [ "${command}" != "" ]; then
			xecho "Uploading ${#list[@]} files: ${cmdList:2}"
			xssh "${command:4}" # remove files before upload
		else
			xecho "Downloading ${#list[@]} files: ${cmdList:2}"
		fi

		for pair in "${list[@]}"; do
			IFS='|'
			# shellcheck disable=SC2206
			files=($pair)
			unset IFS
			local fileA="${files[0]}"
			local fileB="${files[1]}"
			xdebug "    ${fileB#":"}"
			if [ "${canfail}" != "" ]; then
				xscp "${CANFAIL}" "${fileA}" "${fileB}"
			else
				xscp "${fileA}" "${fileB}"
			fi
		done
	fi
}

# List of services to be stopped
SERVICES_STOP=()

function xsstop() {
	# Stop services from SERVICES_STOP
	xsstopv "${SERVICES_STOP[@]}"
}

# shellcheck disable=SC2120
function xsstopv() {
	local list=("$@")
	if [ "${#list[@]}" != "0" ]; then
		local command=""
		local cmdList=""
		for service in "${list[@]}"; do
			#command="${command} && systemctl mask \"${service}\" && systemctl stop \"${service}\""
			command="${command} && systemctl stop \"${service}\""
			cmdList="${cmdList}, ${service}"
		done
		xecho "Stopping ${#list[@]} services: ${cmdList:2}"
		xdebug "Service stop: [CANFAIL] ${command:4}"
		xssh "[CANFAIL]" "${command:4}"
	fi
}

# List of services to be started
SERVICES_START=()

function xsstart() {
	# Start services from SERVICES_START
	xsstartv "${SERVICES_START[@]}"
}

# shellcheck disable=SC2120
function xsstartv() {
	local list=("$@")
	if [ "${#list[@]}" != "0" ]; then
		local command="systemctl daemon-reload"
		local cmdList=""
		for service in "${list[@]}"; do
			#command="${command} && systemctl unmask \"${service}\" && systemctl start \"${service}\""
			command="${command} && systemctl start \"${service}\""
			cmdList="${cmdList}, ${service}"
		done
		xecho "Starting ${#list[@]} services: ${cmdList:2}"
		xdebug "Service start: ${command}"
		xssh "${command}"
	fi
}

# List of process names to be stopped
PROCESSES_STOP=()

function xpstop() {
	# Stop processes from PROCESSES_STOP
	xpstopv "${PROCESSES_STOP[@]}"
}

# shellcheck disable=SC2120
function xpstopv() {
	local list=("$@")
	if [ "${#list[@]}" != "0" ]; then
		local cmdList=""
		for procname in "${list[@]}"; do
			cmdList="${cmdList}, ${procname}"
		done
		xecho "Terminating ${#list[@]} processes: ${cmdList:2}"
		xkill "[CANFAIL]" "${list[@]}"
	fi
}

# List of processed to be started, executable with args
PROCESSES_START=()

function xpstart() {
	# Start processes from PROCESSES_START
	xpstartv "${PROCESSES_START[@]}"
}

# shellcheck disable=SC2120
function xpstartv() {
	local list=("$@")
	if [ "${#list[@]}" != "0" ]; then
		local cmdList=""
		for procname in "${list[@]}"; do
			cmdList="${cmdList}, ${procname}"
		done
		xecho "Starting ${#list[@]} processes: ${cmdList:2}"
		for process in "${list[@]}"; do
			xssh "${process}"
		done
	fi
}

function xbuild() {
	xecho "Building ${PI}${TARGET_BUILD_LAUNCHER}${PO}"
	xexport "${GOLANG_EXPORTS[@]}"
	xexec "${ORIGINAL_GOBIN}" "build" "${TARGET_BUILD_FLAGS[@]}"
	if [ "${EXEC_STATUS}" != "0" ]; then
		xexit
	else
		xexestat "Exec" "${EXEC_STDOUT}" "${EXEC_STDERR}" "${EXEC_STATUS}"
	fi
}
