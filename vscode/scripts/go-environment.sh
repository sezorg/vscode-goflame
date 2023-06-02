#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# GO compiler wrapper environment
#
# Log messages are stored into file:///var/tmp/go-wrapper.log

set -euo pipefail

function xis_true() {
	[[ "${1^^}" =~ ^(1|T|TRUE|Y|YES)$ ]]
}

function xtime() {
	date +%s.%N
}

function xelapsed() {
	local dt dd dt2 dh dt3 dm ds
	dt=$(echo "$(date +%s.%N) - $1" | bc)
	dd=$(echo "$dt/86400" | bc)
	dt2=$(echo "$dt-86400*$dd" | bc)
	dh=$(echo "$dt2/3600" | bc)
	dt3=$(echo "$dt2-3600*$dh" | bc)
	dm=$(echo "$dt3/60" | bc)
	ds=$(echo "$dt3-60*$dm" | bc)
	if [[ "$dd" != "0" ]]; then
		xecho "$(printf "Total runtime: %dd %02dh %02dm %02.4fs\n" "$dd" "$dh" "$dm" "$ds")"
	elif [[ "$dh" != "0" ]]; then
		xecho "$(printf "Total runtime: %dh %02dm %02.4fs\n" "$dh" "$dm" "$ds")"
	elif [[ "$dm" != "0" ]]; then
		xecho "$(printf "Total runtime: %dm %02.4f\n" "$dm" "$ds")"
	else
		xecho "$(printf "Total runtime: %02.4fs\n" "$ds")"
	fi
}

xstart="$(xtime)"
trap xat_exit_trap EXIT

function xat_exit_trap() {
	xelapsed "${xstart}"
	return 0
}

if [[ ! -f "${HOME}/.shellcheckrc" ]]; then
	echo "external-sources=true" >"${HOME}/.shellcheckrc"
fi

function xval() {
	eval "$*"
}

# To omit shellcheck warnings
function xunreferenced_variables() {
	return 0
}

SSH_FLAGS=(-o StrictHostKeyChecking=no
	-o UserKnownHostsFile=/dev/null
	-o ConnectTimeout=5
	-o ConnectionAttempts=1)
CACHE_DIR="/var/tmp/delve_scp"

if [[ ! -d "${CACHE_DIR}" ]]; then
	mkdir -p "${CACHE_DIR}"
fi

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
RUN_GO_VET=""
RUN_GO_VET_FLAGS=("-composites=false")
RUN_STATICCHECK=""
RUN_STATICCHECK_ALL=""

source "${SCRIPT_DIR}/../config.ini"

BUILDROOT_HOST_DIR="${BUILDROOT_DIR}/output/host"
BUILDROOT_TARGET_DIR="${BUILDROOT_DIR}/output/target"

TARGET_BUILD_LAUNCHER="cmd/onvifd/onvifd.go"
TARGET_BUILD_GOFLAGS=("-gcflags=\"-N -l\"")
TARGET_BUILD_LDFLAGS=("-X main.currentVersion=custom")
TARGET_BUILD_LDFLAGS+=("-X main.sysConfDir=/etc")
TARGET_BUILD_LDFLAGS+=("-X main.localStateDir=/var")

TARGET_BUILD_FLAGS=("${TARGET_BUILD_GOFLAGS[@]}")
if [[ "${#TARGET_BUILD_LDFLAGS[@]}" != "0" ]]; then
	TARGET_BUILD_FLAGS+=("-ldflags \"${TARGET_BUILD_LDFLAGS[@]}\"")
fi
if [[ "${TARGET_BUILD_LAUNCHER}" != "" ]]; then
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
if [[ "$MESSAGE_SOURCE" == "" ]]; then
	MESSAGE_SOURCE="unknown-wrapper"
fi

BUILDROOT_GOBIN="${BUILDROOT_HOST_DIR}/bin/go"

LOCAL_GOPATH="$(go env GOPATH)"
LOCAL_GOBIN="/usr/bin/go"
LOCAL_DLVBIN="$(which dlv)"
LOCAL_STATICCHECK="${LOCAL_GOPATH}/bin/staticcheck"

xunreferenced_variables \
	"${BUILDROOT_HOST_DIR}" \
	"${BUILDROOT_TARGET_DIR}" \
	"${TARGET_BIN_SOURCE}" \
	"${TARGET_BIN_DESTIN}" \
	"${TARGET_BIN_NAME}" \
	"${TARGET_EXEC_ARGS}" \
	"${TARGET_LOGFILE}" \
	"${DELVE_LOGFILE}" \
	"${DELVE_DAP_START}" \
	"${WRAPPER_LOGFILE}" \
	"${BUILDROOT_GOBIN}" \
	"${LOCAL_GOBIN}" \
	"${LOCAL_DLVBIN}" \
	"${GOLANG_EXPORTS[@]}"

DLVBIN="${SCRIPT_DIR}/dlv-wrapper.sh"
GOBIN="${SCRIPT_DIR}/go-wrapper.sh"

GOROOT="${BUILDROOT_HOST_DIR}/lib/go"
GOPATH="${BUILDROOT_HOST_DIR}/usr/share/go-path"
GOMODCACHE="${BUILDROOT_HOST_DIR}/usr/share/go-path/pkg/mod"
GOTOOLDIR="${BUILDROOT_HOST_DIR}/lib/go/pkg/tool/linux_arm64"
GOCACHE="${BUILDROOT_HOST_DIR}/usr/share/go-cache"

GOPROXY="direct"
GO111MODULE="on"
GOWORK="off"
GOVCS="*:all"
GOARCH="arm64"
#GOFLAGS="-mod=vendor"
GOFLAGS="-mod=mod"

CGO_ENABLED="1"
#CGO_CFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O3 -g2 -D_FORTIFY_SOURCE=1"
#CGO_CXXFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O3 -g2 -D_FORTIFY_SOURCE=1"
CGO_CFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O0 -g2"
CGO_CXXFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O0 -g2"
CGO_LDFLAGS=""
CC="${BUILDROOT_HOST_DIR}/bin/aarch64-buildroot-linux-gnu-gcc"
CXX="${BUILDROOT_HOST_DIR}/bin/aarch64-buildroot-linux-gnu-g++"

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

function xcontains() {
	local value="$1"
	shift
	for element; do [[ "$element" == "$value" ]] && return 0; done
	return 1
}

function xexport() {
	#xdebug "Exports: $*"
	for variable in "$@"; do
		local name="${variable}"
		local value="${!name}"
		if [[ "${value}" == "" ]]; then
			if ! xcontains "${variable}" "CGO_LDFLAGS"; then
				xecho "WARNING: An empty exported variable ${variable}"
			fi
		fi
		# shellcheck disable=SC2086
		export ${name}="${value}"
	done
}

FIRST_ECHO=y

function xemit() {
	local echo_flag="$1"
	shift
	local message
	message="$(date '+%d/%m/%Y %H:%M:%S') [${MESSAGE_SOURCE}] $*"
	if [[ "${FIRST_ECHO}" == "" ]]; then
		if [[ "${echo_flag}" != "" ]]; then
			echo >&2 "${EP}${message}"
		fi
		echo "${message}" >>"${WRAPPER_LOGFILE}"
	else
		FIRST_ECHO=
		if [[ "${XECHO_ENABLED}" != "" ]] ||
			[[ "${XDEBUG_ENABLED}" != "" ]]; then
			echo >&2
		fi
		if [[ "${echo_flag}" != "" ]]; then
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

function xtext() {
	local text
	readarray -t text <<<"$@"
	for line in "${text[@]}"; do
		xecho "${line}"
	done
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
	if [[ "${status}" != "0" ]]; then
		local needStatus="1"
		if [[ "${stdout}" != "" ]]; then
			xecho "${prefix} STATUS ${status}, STDOUT: ${stdout}"
			needStatus="0"
		fi
		if [[ "${stderr}" != "" ]]; then
			xecho "${prefix} STATUS ${status}, STDERR: ${stderr}"
			needStatus="0"
		fi
		if [[ "${needStatus}" == "1" ]]; then
			xecho "${prefix} STATUS: ${status}"
		fi
	else
		if [[ "${stdout}" != "" ]]; then
			xdebug "${prefix} STDOUT: ${stdout}"
		fi
		if [[ "${2}" != "" ]]; then
			xdebug "${prefix} STDERR: ${stderr}"
		fi
	fi
}

CANFAIL="[CANFAIL]"
OPTIONS_STACK=()

# Execute command which can not fail
function xexec() {
	xfset "+e"
	local canfail=
	if [[ "${1:-}" == "${CANFAIL}" ]]; then
		canfail="${1:-}"
		shift
	fi
	local command="$*"
	if [[ "${command}" == "" ]]; then
		return 0
	fi
	xdebug "Exec: ${command}"
	{
		EXEC_STDOUT=$(chmod u+w /dev/fd/3 && eval "${command}" 2>/dev/fd/3)
		EXEC_STATUS=$?
		EXEC_STDERR=$(cat <&3)
	} 3<<EOF
EOF
	xfunset
	if [[ "${EXEC_STATUS}" != "0" ]] && [[ "${canfail}" == "" ]]; then
		xexestat "Exec" "${EXEC_STDOUT}" "${EXEC_STDERR}" "${EXEC_STATUS}"
		xecho "ERROR: Failed to execute: ${command}"
		if [[ "${EXEC_STDERR}" != "" ]]; then
			xtext "${EXEC_STDERR}"
		fi
		xecho "ERROR: Terminating with status ${EXEC_STATUS}"
		xecho "ERROR: More details in file://${WRAPPER_LOGFILE}"
		exit ${EXEC_STATUS}
	fi
}

function xexit() {
	xdebug "Finishing wrapper with STDOUT, STDERR & STATUS=${EXEC_STATUS}"
	if [[ "${EXEC_STDOUT}" != "" ]]; then
		echo "${EXEC_STDOUT}"
	fi
	if [[ "${EXEC_STDERR}" != "" ]]; then
		echo "${EXEC_STDERR}" 1>&2
	fi
	exit "${EXEC_STATUS}"
}

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

function xssh() {
	xdebug "Target exec: $*"
	local canfail=
	if [[ "${1:-}" == "${CANFAIL}" ]]; then
		canfail="${1:-}"
		shift
	fi
	xexec "${canfail}" sshpass -p "${TARGET_PASS}" ssh "${SSH_FLAGS[@]}" "${TARGET_USER}@${TARGET_IPADDR}" "\"$*\""
}

SSH_HOST_STDIO=""
SSH_HOST_POST=""
SSH_TARGET_STDIO=""
SSH_TARGET_PREF=""
SSH_TARGET_POST=""

function xflash_pending_commands() {
	if [[ "${SSH_HOST_STDIO}" != "" ]] ||
		[[ "${SSH_TARGET_PREF}" != "" ]] ||
		[[ "${SSH_TARGET_STDIO}" != "" ]] ||
		[[ "${SSH_TARGET_POST}" != "" ]]; then

		local code="${SSH_HOST_STDIO}sshpass -p \"${TARGET_PASS}\" "
		local code="${code}ssh ${SSH_FLAGS[*]} ${TARGET_USER}@${TARGET_IPADDR} "
		local code="${code}\"${SSH_TARGET_PREF}${SSH_TARGET_STDIO}${SSH_TARGET_POST}\""

		xexec "${code}"
		xexec "${SSH_HOST_POST}"

		SSH_HOST_STDIO=""
		SSH_TARGET_STDIO=""
		SSH_TARGET_PREF=""
		SSH_TARGET_POST=""
	fi
}

function xperform_build_and_deploy() {
	local fbuild=""

	while :; do
		if [[ "$1" == "[BUILD]" ]]; then
			fbuild="yes"
		elif [[ "$1" == "[ECHO]" ]]; then
			xval XECHO_ENABLED=y
			clear
		else
			break
		fi
		shift
	done

	xecho "$*"
	if xis_true "${fbuild}"; then
		xbuild_project
	else
		xcheck_project
	fi
	xservices_stop
	xprocesses_stop
	xfiles_delete
	xcreate_directories
	xfiles_copy
	xservices_start
	xprocesses_start
	xexecute_commands
	xflash_pending_commands
	xcamera_features
}

function xkill() {
	local canfail=
	if [[ "${1:-}" == "${CANFAIL}" ]]; then
		canfail="${1:-}"
		shift
	fi
	for procname in "$@"; do
		SSH_TARGET_PREF="${SSH_TARGET_PREF}if pgrep ${procname} > /dev/null; then pkill ${procname}; fi; "
	done
}

function xscp() {
	local canfail=
	if [[ "${1:-}" == "${CANFAIL}" ]]; then
		canfail="${1:-}"
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
	xexec "${canfail}" sshpass -p "${TARGET_PASS}" scp -C "${SSH_FLAGS[@]}" "${one}" "${two}"
}

# List of files to be deleted
DELETE_FILES=()

function xfiles_delete() {
	# Delete files from DELETE_FILES
	xfiles_delete_vargs "${DELETE_FILES[@]}"
}

# shellcheck disable=SC2120
function xfiles_delete_vargs() {
	local list=("$@")
	if [[ "${#list[@]}" != "0" ]]; then
		local elements=""
		for filename in "${list[@]}"; do
			elements="${elements}, $(basename -- "$filename")"
			SSH_TARGET_PREF="${SSH_TARGET_PREF}if [[ -f \"${filename}\" ]]; then rm -f \"${filename}\"; fi; "
		done
		xecho "Removing ${#list[@]} files: ${elements:2}"
	fi
}

function xclean_directory() {
	if [[ -d "${1}" ]]; then
		xexec rm -rf "${1}/*"
	else
		xexec mkdir -p "${1}"
	fi
}

function xcache_put() {
	echo "$2" >"${CACHE_DIR}/cachedb/${1}"
}

function xcache_get() {
	cat "${CACHE_DIR}/cachedb/${1}" 2>/dev/null
}

# List of files to be copied, "source|target"
COPY_FILES=()
COPY_CACHE=y

# shellcheck disable=SC2120
function xfiles_copy() {
	# Copy files from COPY_FILES
	local canfail=
	if [[ "${1:-}" == "${CANFAIL}" ]]; then
		canfail="${1:-}"
		shift
	fi

	local list=("$@")
	if [[ "${#list[@]}" == "0" ]]; then
		list=("${COPY_FILES[@]}")
	fi
	if [[ "${#list[@]}" != "0" ]]; then
		local backup_source="${CACHE_DIR}/data"
		if ! xis_true "${COPY_CACHE}"; then
			xclean_directory "${CACHE_DIR}/cachedb"
		elif [[ ! -d "${CACHE_DIR}/cachedb" ]]; then
			xexec mkdir -p "${CACHE_DIR}/cachedb"
		fi

		local elements=""
		local count="0"
		local uploading=""
		local directories=()
		for pair in "${list[@]}"; do
			IFS='|'
			# shellcheck disable=SC2206
			files=($pair)
			unset IFS
			local fileA="${files[0]}"
			local fileB="${files[1]}"
			if [[ "$fileB" =~ ^\:.* ]]; then
				uploading="1"
				local prefA="${fileA:0:1}"
				if [[ "${prefA}" == "?" ]]; then
					fileA="${fileA:1}"
				fi
				if [[ -f "${PWD}/${fileA}" ]]; then
					fileA="${PWD}/${fileA}"
				elif [[ -f "${fileA}" ]]; then
					:
				elif [[ "${prefA}" == "?" ]]; then
					xecho "File \"${fileA}\" does not exists, skipping"
					continue
				else
					xecho "ERROR: Unable to find \"${fileA}\" for upload"
					exit "1"
				fi

				local nameSum fileSum
				nameSum=$(md5sum <<<"${fileA}")
				nameSum="${nameSum:0:32}"
				fileSum=$(md5sum "${fileA}")
				fileSum="${fileSum:0:32}"
				#xecho "${nameSum} :: ${fileSum}"

				if ! xis_true "${COPY_CACHE}" || [[ "$(xcache_get "${nameSum}")" != "${fileSum}" ]]; then
					if [[ "${directories[*]}" == "" ]]; then
						xclean_directory "${backup_source}"
					fi
					local backup_target="${backup_source}/${fileB:1}"
					backup_target="${backup_target//\/\//\/}"
					local backup_subdir
					backup_subdir=$(dirname "${backup_target}")
					if ! xcontains "${backup_subdir}" "${directories[@]}"; then
						directories+=("${backup_subdir}")
						xexec mkdir -p "${backup_subdir}"
					fi
					xexec ln -s "${fileA}" "${backup_target}"
					SSH_TARGET_PREF="${SSH_TARGET_PREF}if [[ -f \"${fileB:1}\" ]]; then rm -f \"${fileB:1}\"; fi; "
					SSH_HOST_POST="${SSH_HOST_POST}xcache_put \"${nameSum}\" \"${fileSum}\"; "
				else
					xdebug "Skipping upload ${fileA} :: ${nameSum} :: ${fileSum}"
					fileB=""
				fi
			fi
			if [[ "${fileB}" != "" ]]; then
				elements="${elements}, $(basename -- "$fileB")"
				count=$((count + 1))
			fi
		done
		if [[ "${uploading}" != "" ]]; then
			if [[ "${elements}" != "" ]]; then
				xecho "Uploading ${count} files: ${elements:2}"
				SSH_HOST_STDIO="tar -cf - -C \"${backup_source}\" --dereference \".\" | gzip -6 - | "
				SSH_TARGET_STDIO="tar --no-same-owner --no-same-permissions -xzf - -C \"/\"; "
			fi
		else
			xecho "Downloading ${#list[@]} files: ${elements:2}"
		fi

		for pair in "${list[@]}"; do
			IFS='|'
			# shellcheck disable=SC2206
			files=($pair)
			unset IFS
			local fileA="${files[0]}"
			local fileB="${files[1]}"
			if [[ ! "$fileB" =~ ^\:.* ]]; then
				xdebug "    ${fileB#":"}"
				if [[ "${canfail}" != "" ]]; then
					xscp "${CANFAIL}" "${fileA}" "${fileB}"
				else
					xscp "${fileA}" "${fileB}"
				fi
			fi
		done
	fi
}

# List of services to be stopped
SERVICES_STOP=()

function xservices_stop() {
	# Stop services from SERVICES_STOP
	xservices_stop_vargs "${SERVICES_STOP[@]}"
}

# shellcheck disable=SC2120
function xservices_stop_vargs() {
	local list=("$@")
	if [[ "${#list[@]}" != "0" ]]; then
		local elements=""
		for service in "${list[@]}"; do
			elements="${elements}, ${service}"
			#SSH_TARGET_PREF="${SSH_TARGET_PREF}systemctl mask \"${service}\"; "
			SSH_TARGET_PREF="${SSH_TARGET_PREF}systemctl stop \"${service}\"; "
		done
		xecho "Stopping ${#list[@]} services: ${elements:2}"
	fi
}

# List of services to be started
SERVICES_START=()

function xservices_start() {
	# Start services from SERVICES_START
	xservices_start_vargs "${SERVICES_START[@]}"
}

# shellcheck disable=SC2120
function xservices_start_vargs() {
	local list=("$@")
	if [[ "${#list[@]}" != "0" ]]; then
		local elements=""
		for service in "${list[@]}"; do
			elements="${elements}, ${service}"
			#SSH_TARGET_PREF="${SSH_TARGET_PREF}systemctl unmask \"${service}\"; "
			SSH_TARGET_POST="${SSH_TARGET_POST}systemctl start \"${service}\"; "
		done
		xecho "Starting ${#list[@]} services: ${elements:2}"
	fi
}

# List of process names to be stopped
PROCESSES_STOP=()

function xprocesses_stop() {
	# Stop processes from PROCESSES_STOP
	xprocesses_stop_vargs "${PROCESSES_STOP[@]}"
}

# shellcheck disable=SC2120
function xprocesses_stop_vargs() {
	local list=("$@")
	if [[ "${#list[@]}" != "0" ]]; then
		local elements=""
		for procname in "${list[@]}"; do
			elements="${elements}, ${procname}"
			SSH_TARGET_PREF="${SSH_TARGET_PREF}if pgrep ${procname} > /dev/null; then pkill ${procname}; fi; "
		done
		xecho "Terminating ${#list[@]} processes: ${elements:2}"
	fi
}

# List of processed to be started, executable with args
PROCESSES_START=()

function xprocesses_start() {
	# Start processes from PROCESSES_START
	xprocesses_start_vargs "${PROCESSES_START[@]}"
}

# shellcheck disable=SC2120
function xprocesses_start_vargs() {
	local list=("$@")
	if [[ "${#list[@]}" != "0" ]]; then
		local elements=""
		for procname in "${list[@]}"; do
			elements="${elements}, ${procname}"
			SSH_TARGET_POST="${SSH_TARGET_POST}${procname}; "
		done
		xecho "Starting ${#list[@]} processes: ${elements:2}"
	fi
}

# List of directories to be created
DIRECTORIES_CREATE=()

function xcreate_directories() {
	# Create directories from DIRECTORIES_CREATE
	xcreate_directories_vargs "${DIRECTORIES_CREATE[@]}"
}

# shellcheck disable=SC2120
function xcreate_directories_vargs() {
	local list=("$@")
	if [[ "${#list[@]}" != "0" ]]; then
		local elements=""
		for dirname in "${list[@]}"; do
			elements="${elements}, ${dirname}"
			SSH_TARGET_POST="${SSH_TARGET_POST}mkdir -p \"${dirname}\"; "
		done
		xecho "Creating ${#list[@]} directories: ${elements:2}"
	fi
}

# List of directories to be created
EXECUTE_COMMANDS=()

function xexecute_commands() {
	# Create directories from DIRECTORIES_CREATE
	xexecute_commands_vargs "${EXECUTE_COMMANDS[@]}"
}

# shellcheck disable=SC2120
function xexecute_commands_vargs() {
	local list=("$@")
	if [[ "${#list[@]}" != "0" ]]; then
		local elements=""
		for command in "${list[@]}"; do
			elements="${elements}, ${command%% *}"
			SSH_TARGET_POST="${SSH_TARGET_POST}(${command}); "
		done
		xecho "Executing ${#list[@]} target commands: ${elements:2}"
	fi
}

function xcheck_project() {
	xexport "${GOLANG_EXPORTS[@]}"
	if xis_true "${RUN_GO_VET}"; then
		xecho "Running ${PI}go vet${PO} on ${PI}${TARGET_BUILD_LAUNCHER}${PO}..."
		xexec "${CANFAIL}" "go" "vet" "${RUN_GO_VET_FLAGS[@]}" "./..."
		if [[ "${EXEC_STDERR}" != "" ]]; then
			xtext "${EXEC_STDERR}"
		fi
		xecho "Go vet finished with status ${EXEC_STATUS}"
	fi
	if xis_true "${RUN_STATICCHECK}"; then
		local flags=()
		if xis_true "${RUN_STATICCHECK_ALL}"; then
			flags+=("-checks=all")
		fi
		xecho "Running ${PI}staticcheck${PO} on of ${PI}${TARGET_BUILD_LAUNCHER}${PO}..."
		xexec "${CANFAIL}" "${LOCAL_STATICCHECK}" "${flags[@]}" "./..."
		if [[ "${EXEC_STDOUT}" != "" ]]; then
			xtext "${EXEC_STDOUT}"
		fi
		xecho "Staticcheck finished with status ${EXEC_STATUS}"
	fi
}

function xbuild_project() {
	xcheck_project
	local flags=()
	flags+=("build")
	#flags+=("-race")
	#flags+=("-msan")
	#flags+=("-asan")
	xexec "${BUILDROOT_GOBIN}" "${flags[@]}" "${TARGET_BUILD_FLAGS[@]}"
	if [[ "${EXEC_STATUS}" != "0" ]]; then
		xdebug "BUILDROOT_DIR=$BUILDROOT_DIR"
		xdebug "GOPATH=$GOPATH"
		xdebug "GOROOT=$GOROOT"
		xexit
	else
		xexestat "Exec" "${EXEC_STDOUT}" "${EXEC_STDERR}" "${EXEC_STATUS}"
	fi
}

CAMERA_FEATURES_ON=()
CAMERA_FEATURES_OFF=()

# Set camera features
function xcamera_features() {
	local feature_args=""
	for feature in "${CAMERA_FEATURES_ON[@]}"; do
		feature_args="${feature_args}&${feature}=true"
	done
	for feature in "${CAMERA_FEATURES_OFF[@]}"; do
		feature_args="${feature_args}&${feature}=false"
	done
	if [[ "${feature_args}" == "" ]]; then
		return 0
	fi
	local timeout=2
	local wget_command=(timeout "${timeout}" wget --no-proxy "--timeout=${timeout}"
		-q -O - "\"http://${TARGET_IPADDR}/cgi/features.cgi?${feature_args:1}\"")
	xexec "${wget_command[*]}"
	local response="${EXEC_STDOUT//[$'\t\r\n']/}"
	xdebug "WGET response: ${response}"

	local features_on_set=""
	local features_on_err=""
	for feature in "${CAMERA_FEATURES_ON[@]}"; do
		local pattern="\"${feature}\": set to True"
		if grep -i -q "$pattern" <<<"$response"; then
			features_on_set="${features_on_set}, ${feature}"
		else
			features_on_err="${features_on_err}, ${feature}"
		fi
	done

	local features_off_set=""
	local features_off_err=""
	for feature in "${CAMERA_FEATURES_OFF[@]}"; do
		local pattern="\"${feature}\": set to False"
		if grep -i -q "$pattern" <<<"$response"; then
			features_off_set="${features_off_set}, ${feature}"
		else
			features_off_err="${features_off_err}, ${feature}"
		fi
	done

	local features_set=""
	if [[ "${features_on_set}" != "" ]]; then
		features_set="${features_set}; true: ${features_on_set:2}"
	fi
	if [[ "${features_off_set}" != "" ]]; then
		features_set="${features_set}; false: ${features_off_set:2}"
	fi

	local features_err=""
	if [[ "${features_on_err}" != "" ]]; then
		features_err="${features_err}; true: ${features_on_err:2}"
	fi
	if [[ "${features_off_err}" != "" ]]; then
		features_err="${features_err}; false: ${features_off_err:2}"
	fi

	if [[ "${features_set}" != "" ]]; then
		xecho "Camera features set to ${features_set:2}"
	fi
	if [[ "${features_err}" != "" ]]; then
		xecho "WARNING: Failed to set camera features to ${features_err:2}"
	fi
}

function xtruncate_text_file() {
	local name="$1"
	local limit="$2"
	local target="$3"
	if [[ ! -f "${name}" ]]; then
		return 0
	fi
	local actual
	actual=$(wc -l "${name}")
	actual=${actual%% *}
	local truncate=$((actual > limit ? 1 : 0))
	if ! xis_true "${truncate}"; then
		return 0
	fi
	local tmp_name="${name}.tmp"
	xdebug "Truncating ${WRAPPER_LOGFILE} from $actual to $target limit, thresold $limit."
	xexec "cp \"${name}\" \"${tmp_name}\""
	local offset=$((actual - target))
	xexec "tail -$offset \"${tmp_name}\" > \"${name}\""
	xexec "rm -rf \"${tmp_name}\""
}

function xtruncate_log_file() {
	xtruncate_text_file "${WRAPPER_LOGFILE}" 5000 300
}

xtruncate_log_file
