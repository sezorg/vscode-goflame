#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# GO compiler wrapper environment

set -euo pipefail

function xtime() {
	date +%s.%N
}

function xelapsed() {
	local dt
	local dd
	local dt2
	local dh
	local dt3
	local dm
	local ds
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
trap at_exit EXIT

function at_exit() {
	xelapsed "${xstart}"
	return 0
}

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

SSH_FLAGS=(-o StrictHostKeyChecking=no 
	-o UserKnownHostsFile=/dev/null 
	-o ConnectTimeout=5 
	-o ConnectionAttempts=1)
CACHE_DIR="/var/tmp/delve_scp"

if [ ! -d "${CACHE_DIR}" ]; then
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

ORIGINAL_GOBIN="${BUILDROOT_HOST_DIR}/bin/go"

LOCAL_GOPATH="$(go env GOPATH)"
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
	"${ORIGINAL_GOBIN}" \
	"${LOCAL_DLVBIN}" \
	"${GOLANG_EXPORTS[@]}"

DLVBIN="${SCRIPT_DIR}/dlv.sh"
GOBIN="${SCRIPT_DIR}/go.sh"

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
CGO_CFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O3 -g2 -D_FORTIFY_SOURCE=1"
CGO_CXXFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O3 -g2 -D_FORTIFY_SOURCE=1"
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
	local message
	message="$(date '+%d/%m/%Y %H:%M:%S') [${WRAPPER_TYPE}] $*"
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

function xssh() {
	xdebug "Target exec: $*"
	local canfail=
	if [ "${1:-}" == "${CANFAIL}" ]; then
		canfail="$1"
		shift
	fi

	xrun sshpass -p "${TARGET_PASS}" ssh "${SSH_FLAGS[@]}" "${TARGET_USER}@${TARGET_IPADDR}" "\"$*\""

	if [ "${RUN_STATUS}" != "0" ] && [ "${canfail}" == "" ]; then
		xecho "Failed. Terminating with status ${RUN_STATUS}"
		exit ${RUN_STATUS}
	fi
}

SSH_HOST_STDIO=""
SSH_HOST_POST=""
SSH_TARGET_STDIO=""
SSH_TARGET_PREF=""
SSH_TARGET_POST=""

function xflash() {
	if [[ "${SSH_HOST_STDIO}" != "" ]] || \
		[[ "${SSH_TARGET_PREF}" != "" ]] || \
		[[ "${SSH_TARGET_STDIO}" != "" ]] || \
		[[ "${SSH_TARGET_POST}" != "" ]]; then

		local code="${SSH_HOST_STDIO}sshpass -p \"${TARGET_PASS}\" "
		local code="${code}ssh ${SSH_FLAGS[*]} ${TARGET_USER}@${TARGET_IPADDR} "
		local code="${code}\"${SSH_TARGET_PREF}${SSH_TARGET_STDIO}${SSH_TARGET_POST}\""

		xrun "${code}"
		xrun "${SSH_HOST_POST}"

		SSH_HOST_STDIO=""
		SSH_TARGET_STDIO=""
		SSH_TARGET_PREF=""
		SSH_TARGET_POST=""
	fi
}

function xkill() {
	local canfail=
	if [ "${1:-}" == "${CANFAIL}" ]; then
		canfail="$1"
		shift
	fi
	for procname in "$@"; do
		SSH_TARGET_PREF="${SSH_TARGET_PREF}(if pgrep ${procname} > /dev/null; then pkill ${procname}; fi); "
	done
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
	sshpass -p "${TARGET_PASS}" scp -C "${SSH_FLAGS[@]}" "${one}" "${two}"

	if [ "${RUN_STATUS}" != "0" ] && [ "${canfail}" == "" ]; then
		xecho "Failed. Terminating with status ${RUN_STATUS}"
		exit "${RUN_STATUS}"
	fi
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
		local elements=""
		for filename in "${list[@]}"; do
			elements="${elements}, $(basename -- "$filename")" 
			SSH_TARGET_PREF="${SSH_TARGET_PREF}(if [ -f \"${filename}\" ]; then rm -f \"${filename}\"; fi); "
		done
		xecho "Removing ${#list[@]} files: ${elements:2}"
	fi
}

function cache_put() {
	echo "$2" > "${CACHE_DIR}/cachedb/${1}"
}

function cache_get() {
	cat "${CACHE_DIR}/cachedb/${1}" 2>/dev/null
}


# List of files to be copied, "source|target"
COPY_FILES=()
COPY_CACHE=y

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
		local backup_source="${CACHE_DIR}/data"
		local backup_rname=""
		local backup_subdir=""
		rm -r "${backup_source}"
		if [ "${COPY_CACHE}" != "y" ]; then
			rm -r "${CACHE_DIR}/cachedb"
		fi
		mkdir -p "${CACHE_DIR}/cachedb"

		local elements=""
		local count="0"
		local uploading=""
		for pair in "${list[@]}"; do
			IFS='|'
			# shellcheck disable=SC2206
			files=($pair)
			unset IFS
			local fileA="${files[0]}"
			local fileB="${files[1]}"
			if [[ "$fileB" =~ ^\:.* ]]; then
				uploading="1"
				backup_rname="${fileB:1}"
				backup_subdir=$(dirname "${backup_rname}")
				mkdir -p "${backup_source}/${backup_subdir}"
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
					exit 1
				fi

				local nameSum
				local fileSum
				nameSum=$(md5sum <<< "${fileA}")
				nameSum="${nameSum:0:32}"
				fileSum=$(md5sum "${fileA}")
				fileSum="${fileSum:0:32}"

				#xecho "${nameSum} :: ${fileSum}"
				if [ "${COPY_CACHE}" != "y" ] || [ "$(cache_get "${nameSum}")"  != "${fileSum}" ]; then
					ln -s "${fileA}" "${backup_source}/${backup_rname}"	
					SSH_TARGET_PREF="${SSH_TARGET_PREF}(if [ -f \"${fileB:1}\" ]; then rm -f \"${fileB:1}\"; fi); "
					SSH_HOST_POST="${SSH_HOST_POST}(cache_put \"${nameSum}\" \"${fileSum}\"); "
				else 
					#xecho "Skipping ${fileA} :: ${nameSum} :: ${fileSum}"
					fileB=""
				fi

				#ln -s "${fileA}" "${backup_source}/${backup_rname}"
			fi
			if [ "${fileB}" != "" ]; then
				elements="${elements}, $(basename -- "$fileB")"
				count=$((count+1))
			fi
		done
		if [ "${uploading}" != "" ]; then
			if [ "${elements}" != "" ]; then
				xecho "Uploading ${count} files: ${elements:2}"
			fi
			SSH_HOST_STDIO="tar -cf - -C \"${backup_source}\" --dereference \".\" | gzip -7 - | "
			SSH_TARGET_STDIO="tar --no-same-owner --no-same-permissions -xzf - -C \"/\"; "
			#tar -cf - -C "${backup_source}" --dereference . | gzip -7 - | \
			#	sshpass -p "${TARGET_PASS}" \
			#	ssh "${SSH_FLAGS[@]}" ${TARGET_USER}@${TARGET_IPADDR} \
			#	"${command}tar -xzf - -C \"/\""
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
				if [ "${canfail}" != "" ]; then
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

function xsstop() {
	# Stop services from SERVICES_STOP
	xsstopv "${SERVICES_STOP[@]}"
}

# shellcheck disable=SC2120
function xsstopv() {
	local list=("$@")
	if [ "${#list[@]}" != "0" ]; then
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

function xsstart() {
	# Start services from SERVICES_START
	xsstartv "${SERVICES_START[@]}"
}

# shellcheck disable=SC2120
function xsstartv() {
	local list=("$@")
	if [ "${#list[@]}" != "0" ]; then
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

function xpstop() {
	# Stop processes from PROCESSES_STOP
	xpstopv "${PROCESSES_STOP[@]}"
}

# shellcheck disable=SC2120
function xpstopv() {
	local list=("$@")
	if [ "${#list[@]}" != "0" ]; then
		local elements=""
		for procname in "${list[@]}"; do
			elements="${elements}, ${procname}"
			SSH_TARGET_PREF="${SSH_TARGET_PREF}(if pgrep ${procname} > /dev/null; then pkill ${procname}; fi); "
		done
		xecho "Terminating ${#list[@]} processes: ${elements:2}"
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

function xmkdirs() {
	# Create directories from DIRECTORIES_CREATE
	xmkdirsv "${DIRECTORIES_CREATE[@]}"
}

# shellcheck disable=SC2120
function xmkdirsv() {
	local list=("$@")
	if [ "${#list[@]}" != "0" ]; then
		local elements=""
		for dirname in "${list[@]}"; do
			elements="${elements}, ${dirname}"
			SSH_TARGET_POST="${SSH_TARGET_POST}mkdir -p \"${dirname}\"; "
		done
		xecho "Creating ${#list[@]} directories: ${elements:2}"
	fi
}

# List of directories to be created
COMMANDS_EXECUTE=()

function xcommand() {
	# Create directories from DIRECTORIES_CREATE
	xcommandv "${COMMANDS_EXECUTE[@]}"
}

# shellcheck disable=SC2120
function xcommandv() {
	local list=("$@")
	if [ "${#list[@]}" != "0" ]; then
		local elements=""
		for command in "${list[@]}"; do
			elements="${elements}, ${command}"
			SSH_TARGET_POST="${SSH_TARGET_POST}( ${command} ); "
		done
		xecho "Creating ${#list[@]} directories: ${elements:2}"
	fi
}

function xbuild() {
	xexport "${GOLANG_EXPORTS[@]}"
	if [ "${RUN_GO_VET}" == "yes" ]; then
		xecho "Running ${PI}go vet${PO} on ${PI}${TARGET_BUILD_LAUNCHER}${PO}..."
		#-checks=all 
		xexec "go" "vet" "./..."
		if [ "${EXEC_STDERR}" != "" ]; then
			xecho "${EXEC_STDERR}"
		fi
		xecho "Go vet finished with status ${EXEC_STATUS}"
	fi
	if [ "${RUN_STATICCHECK}" == "yes" ]; then
		local flags=()
		if [ "${RUN_STATICCHECK_ALL}" == "yes" ]; then
			flags+=("-checks=all")
		fi
		xecho "Running ${PI}staticcheck${PO} on of ${PI}${TARGET_BUILD_LAUNCHER}${PO}..."
		xexec "${LOCAL_STATICCHECK}" "${flags[@]}" "./..."
		if [ "${EXEC_STDOUT}" != "" ]; then
			xecho "${EXEC_STDOUT}"
		fi
		xecho "Staticcheck finished with status ${EXEC_STATUS}"
	fi
	#xecho "Building ${PI}${TARGET_BUILD_LAUNCHER}${PO}"
	
	#env
	#xecho "BUILDROOT_DIR=$BUILDROOT_DIR"
	#xecho "GOPATH=$GOPATH"
	#xecho "GOROOT=$GOROOT"
	#xecho "${ORIGINAL_GOBIN}" "build" "${TARGET_BUILD_FLAGS[@]}"
	local flags=()
	flags+=("build")
	#flags+=("-race")
	#xecho "${ORIGINAL_GOBIN}" "${flags[@]}" "${TARGET_BUILD_FLAGS[@]}"
	xexec "${ORIGINAL_GOBIN}" "${flags[@]}" "${TARGET_BUILD_FLAGS[@]}"
	if [ "${EXEC_STATUS}" != "0" ]; then
		xexit
	else
		xexestat "Exec" "${EXEC_STDOUT}" "${EXEC_STDERR}" "${EXEC_STATUS}"
	fi
}
