#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# GO compiler wrapper environment
#
# Log messages are stored into file:///var/tmp/goflame/go-wrapper.log

set -euo pipefail
#set -x

function xis_true() {
	[[ "${1^^}" =~ ^(1|T|TRUE|Y|YES)$ ]]
}

function xis_false() {
	[[ ! "${1^^}" =~ ^(1|T|TRUE|Y|YES)$ ]]
}

function xis_set() {
	[[ "$1" != "" ]]
}

function xis_unset() {
	[[ "$1" == "" ]]
}

function xis_eq() {
	[[ "$1" == "$2" ]]
}

function xis_ne() {
	[[ "$1" != "$2" ]]
}

function xtime() {
	date +%s.%N
}

function xelapsed() {
	local time days days_frac hours hours_frac mins secs
	time=$(echo "$(date +%s.%N) - $1" | bc)
	days=$(echo "$time/86400" | bc)
	days_frac=$(echo "$time-86400*$days" | bc)
	hours=$(echo "$days_frac/3600" | bc)
	hours_frac=$(echo "$days_frac-3600*$hours" | bc)
	mins=$(echo "$hours_frac/60" | bc)
	secs=$(echo "$hours_frac-60*$mins" | bc)
	if xis_ne "$days" "0"; then
		xecho "$(printf "Total runtime: %dd %02dh %02dm %02.3fs" "$days" "$hours" "$mins" "$secs")"
	elif xis_ne "$hours" "0"; then
		xecho "$(printf "Total runtime: %dh %02dm %02.3fs" "$hours" "$mins" "$secs")"
	elif xis_ne "$mins" "0"; then
		xecho "$(printf "Total runtime: %dm %02.3fs" "$mins" "$secs")"
	else
		xecho "$(printf "Total runtime: %02.3fs" "$secs")"
	fi
}

xstart="$(xtime)"
trap xat_exit_trap EXIT

function xat_exit_trap() {
	xelapsed "$xstart"
	return 0
}

function xat_error() {
	set +u
	local parent_lineno="$1"
	local message="$2"
	local code="${3:-1}"
	if [[ -n "$message" ]]; then
		xecho "Error on or near line $parent_lineno: $message; exiting with status $code"
	else
		xecho "Error on or near line $parent_lineno; exiting with status $code"
	fi
	exit "$code"
}

trap 'xat_error $LINENO' ERR

if [[ ! -f "$HOME/.shellcheckrc" ]]; then
	echo "external-sources=true" >"$HOME/.shellcheckrc"
fi

function xset() {
	eval "$*"
}

# To omit shellcheck warnings
function xunreferenced() {
	return 0
}

SSH_FLAGS=(
	-o StrictHostKeyChecking=no
	-o UserKnownHostsFile=/dev/null
	-o ConnectTimeout=5
	-o ConnectionAttempts=1
	-o ServerAliveInterval=1
	-o ServerAliveCountMax=2
	-o Compression=no
	#-o CompressionLevel=9
	-o Ciphers="aes128-ctr,aes192-ctr,aes256-ctr"
	-o MACs="hmac-sha1"
	-o ControlMaster=auto
	-o ControlPersist=600
	-o ControlPath=/var/tmp/ssh-%r@%h-%p
	-o ForwardAgent=yes
	-o PreferredAuthentications="password"
)

TEMP_DIR="/var/tmp/goflame"
P_CACHE_DIR="$TEMP_DIR/cachedb"

mkdir -p "$TEMP_DIR" "$P_CACHE_DIR"

XECHO_ENABLED=
XDEBUG_ENABLED=
DT="$(date '+%d/%m/%Y %H:%M:%S') "
CE=$'\u1B' # Color escape
EP=""
PI="\`"
PO="'"
xunreferenced "$DT" "$CE" "$EP"

TARGET_ARCH=""
TARGET_GOCXX=""
TARGET_IPADDR="UNKNOWN-TARGET_IPADDR"
TARGET_IPPORT="UNKNOWN-TARGET_IPPORT"
TARGET_USER="UNKNOWN-TARGET_USER"
TARGET_PASS="UNKNOWN-TARGET_PASS"
TARGET_BUILD_LAUNCHER=""
TARGET_BIN_SOURCE=""
TARGET_BIN_DESTIN=""
TARGET_EXEC_ARGS=()
TARGET_SUPRESS_MSSGS=()

BUILDROOT_DIR="UNKNOWN-BUILDROOT_DIR"
CLEAN_GOCACHE=false
GIT_COMMIT_FILTER="" #
GOLANGCI_LINT_ENABLE=false
GOLANGCI_LINT_LINTERS=(
	"all"
	"-depguard"
	"-gochecknoglobals"
)
GOLANGCI_LINT_FILTER=true
GOLANGCI_LINT_FAIL=false
GOLANGCI_LINT_SUPRESSED=()
GOLANGCI_LINT_DEPRECATED=(
	"deadcode"
	"exhaustivestruct"
	"golint"
	"ifshort"
	"interfacer"
	"maligned"
	"nosnakecase"
	"scopelint"
	"structcheck"
	"varcheck"
)
STATICCHECK_ENABLE=false
STATICCHECK_CHECKS="all"
STATICCHECK_FILTER=true
STATICCHECK_SUPRESS=""
STATICCHECK_FAIL=true
GO_VET_ENABLE=false
GO_VET_FLAGS=("-composites=true")
GO_VET_FAIL=true
LLENCHECK_ENABLE=false
LLENCHECK_TABWIDTH=4
LLENCHECK_LIMIT=100
LLENCHECK_FILTER=true
LLENCHECK_FAIL=true

INSTALL_SSH_KEY=false

# Cimpiler messages to be ignored
MESSAGES_IGNORE=()
MESSAGES_IGNORE+=("# github.com/lestrrat-go/libxml2/clib")
MESSAGES_IGNORE+=("WARNING: unsafe header/library path used in cross-compilation:")

# List of files to be deleted
DELETE_FILES=()

# List of files to be copied, "source|target"
COPY_FILES=()
COPY_CACHE=true

# List of services to be stopped
SERVICES_STOP=()

# List of services to be started
SERVICES_START=()

# List of process names to be stopped
PROCESSES_STOP=()

# List of processed to be started, executable with args
PROCESSES_START=()

# List of directories to be created
DIRECTORIES_CREATE=()

# List of directories to be created
EXECUTE_COMMANDS=()

# Camera features ON and OFF
CAMERA_FEATURES_ON=()
CAMERA_FEATURES_OFF=()

P_CONFIG_INI_LOADED=true
if [[ -f "$SCRIPT_DIR/../config.ini" ]]; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/../config.ini"
	P_CONFIG_INI_LOADED=true
fi
if [[ -f "$SCRIPT_DIR/../config-user.ini" ]]; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/../config-user.ini"
	P_CONFIG_INI_LOADED=true
fi

P_IGNORE_PATTERN="$(printf "\n%s" "${MESSAGES_IGNORE[@]}")"
P_IGNORE_PATTERN="${P_IGNORE_PATTERN:1}"
P_FIRST_ECHO=true
P_MESSAGE_SOURCE=$(basename -- "$0") #"${BASH_SOURCE[0]}")
P_MESSAGE_SOURCE="${P_MESSAGE_SOURCE%.*}"

function xemit() {
	local echo_flag="$1"
	shift
	local stamp message input="$*"
	if xis_set "$input"; then
		input=$(grep -v "$P_IGNORE_PATTERN" <<<"$input")
		if xis_unset "$input"; then
			return 0
		fi
	fi
	stamp="$(date '+%d/%m/%Y %H:%M:%S.%N')"
	message="${stamp:0:-6} [$P_MESSAGE_SOURCE] $input"
	if xis_unset "$P_FIRST_ECHO"; then
		if xis_set "$echo_flag"; then
			echo >&2 "$EP${message}"
		fi
		echo "$message" >>"$WRAPPER_LOGFILE"
	else
		P_FIRST_ECHO=
		if xis_set "$XECHO_ENABLED" || xis_set "$XDEBUG_ENABLED"; then
			echo >&2
		fi
		if xis_set "$echo_flag"; then
			echo >&2 "$EP${message}"
		fi
		echo >>"$WRAPPER_LOGFILE"
		echo "$message" >>"$WRAPPER_LOGFILE"
	fi
}

function xecho() {
	# Echo message
	xemit "$XECHO_ENABLED" "$*"
}

function xfatal() {
	xemit "1" "FATAL: $*"
	exit 1
}

function xdebug() {
	# Debug message
	xemit "$XDEBUG_ENABLED" "DEBUG: $*"
}

function xtext() {
	if xis_unset "$*"; then
		return 0
	fi
	local text
	readarray -t text <<<"$@"
	for line in "${text[@]}"; do
		xecho "$line"
	done
}

function xdecorate() {
	echo "$PI$*$PO"
}

if xis_false "$P_CONFIG_INI_LOADED"; then
	xerror "Unable to load configuration from \"config-user.ini\" or \"config.ini\"."
	xfatal "See documentation for more details."
fi

cat <<EOF >"$TEMP_DIR/config-vscode.ini"
# Machine generated file. Do not modify.
TARGET_IPADDR=$TARGET_IPADDR
TARGET_IPPORT=$TARGET_IPPORT
TARGET_USER=$TARGET_USER
TARGET_PASS=$TARGET_PASS
EOF

BUILDROOT_HOST_DIR="$BUILDROOT_DIR/output/host"
BUILDROOT_TARGET_DIR="$BUILDROOT_DIR/output/target"

TARGET_BUILD_GOFLAGS=("-gcflags=\"-N -l\"")
TARGET_BUILD_LDFLAGS=("-X main.currentVersion=custom")
TARGET_BUILD_LDFLAGS+=("-X main.sysConfDir=/etc")
TARGET_BUILD_LDFLAGS+=("-X main.localStateDir=/var")

TARGET_BUILD_FLAGS=("${TARGET_BUILD_GOFLAGS[@]}")
if xis_ne "${#TARGET_BUILD_LDFLAGS[@]}" "0"; then
	TARGET_BUILD_FLAGS+=("-ldflags \"${TARGET_BUILD_LDFLAGS[@]}\"")
fi
if xis_set "$TARGET_BUILD_LAUNCHER"; then
	TARGET_BUILD_FLAGS+=("$TARGET_BUILD_LAUNCHER")
fi

TARGET_BIN_NAME=$(basename -- "$TARGET_BIN_DESTIN")
DELVE_DAP_START="dlv dap --listen=:2345 --api-version=2 --log"
BUILDROOT_GOBIN="$BUILDROOT_HOST_DIR/bin/go"
WRAPPER_LOGFILE="$TEMP_DIR/go-wrapper.log"

LOCAL_DLVBIN="$(which dlv)"
LOCAL_GOBIN="$(which go)"
LOCAL_GOPATH="$(go env GOPATH)"
LOCAL_STATICCHECK="$LOCAL_GOPATH/bin/staticcheck"
LOCAL_GOLANGCI_LINT="$LOCAL_GOPATH/bin/golangci-lint"

DLOOP_ENABLE_FILE="/tmp/dlv-loop-enable"
DLOOP_STATUS_FILE="/tmp/dlv-loop-status"
DLOOP_RESTART_FILE="/tmp/dlv-loop-restart"

xunreferenced \
	"$BUILDROOT_HOST_DIR" \
	"$BUILDROOT_TARGET_DIR" \
	"$TARGET_BIN_SOURCE" \
	"$TARGET_BIN_DESTIN" \
	"$TARGET_BIN_NAME" \
	"${TARGET_EXEC_ARGS[@]}" \
	"$DELVE_DAP_START" \
	"$WRAPPER_LOGFILE" \
	"$BUILDROOT_GOBIN" \
	"$LOCAL_GOBIN" \
	"$LOCAL_DLVBIN" \
	"${GOLANG_EXPORTS[@]}" \
	"$DLOOP_ENABLE_FILE" \
	"$DLOOP_STATUS_FILE" \
	"$DLOOP_RESTART_FILE"

if xis_unset "$TARGET_ARCH"; then
	if [[ -f "$BUILDROOT_DIR/output/host/bin/arm-buildroot-linux-gnueabihf-gcc" ]]; then
		TARGET_ARCH="arm"
	elif [[ -f "$BUILDROOT_DIR/output/host/bin/aarch64-buildroot-linux-gnu-gcc" ]]; then
		TARGET_ARCH="arm64"
	else
		xfatal "Can not determine target architecture from BUILDROOT_DIR: $BUILDROOT_DIR."
	fi
fi

if xis_unset "$TARGET_GOCXX"; then
	case "$TARGET_ARCH" in
	"arm") TARGET_GOCXX="arm-buildroot-linux-gnueabihf" ;;
	"arm64") TARGET_GOCXX="aarch64-buildroot-linux-gnu" ;;
	*) xfatal "Can not determine compiler for TARGET_ARCH=\"$TARGET_ARCH\"" ;;
	esac
fi

EXPORT_DLVBIN="$SCRIPT_DIR/dlv-wrapper.sh"
EXPORT_GOBIN="$SCRIPT_DIR/go-wrapper.sh"

EXPORT_GOROOT="$BUILDROOT_HOST_DIR/lib/go"
EXPORT_GOPATH="$BUILDROOT_HOST_DIR/usr/share/go-path"
EXPORT_GOMODCACHE="$BUILDROOT_HOST_DIR/usr/share/go-path/pkg/mod"
EXPORT_GOTOOLDIR="$BUILDROOT_HOST_DIR/lib/go/pkg/tool/linux_$TARGET_ARCH"
EXPORT_GOCACHE="$BUILDROOT_HOST_DIR/usr/share/go-cache"

EXPORT_GOPROXY="direct"
EXPORT_GO111MODULE="on"
EXPORT_GOWORK="off"
EXPORT_GOVCS="*:all"
EXPORT_GOARCH="$TARGET_ARCH"
#EXPORT_GOFLAGS="-mod=vendor"
EXPORT_GOFLAGS="-mod=mod"

EXPORT_CGO_ENABLED="1"
#EXPORT_CGO_CFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O3 -g2 -D_FORTIFY_SOURCE=1"
#EXPORT_CGO_CXXFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O3 -g2 -D_FORTIFY_SOURCE=1"
EXPORT_CGO_CFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O0 -g2"
EXPORT_CGO_CXXFLAGS="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -O0 -g2"
EXPORT_CGO_LDFLAGS=""

EXPORT_CC="$BUILDROOT_HOST_DIR/bin/$TARGET_GOCXX-gcc"
EXPORT_CXX="$BUILDROOT_HOST_DIR/bin/$TARGET_GOCXX-g++"

GOLANG_EXPORTS=(
	"EXPORT_DLVBIN"
	"EXPORT_GOBIN"

	"EXPORT_GOROOT"
	"EXPORT_GOPATH"
	"EXPORT_GOMODCACHE"
	"EXPORT_GOTOOLDIR"
	"EXPORT_GOCACHE"

	"EXPORT_GOPROXY"
	"EXPORT_GO111MODULE"
	"EXPORT_GOWORK"
	"EXPORT_GOVCS"
	"EXPORT_GOARCH"
	"EXPORT_GOFLAGS"

	"EXPORT_CGO_ENABLED"
	"EXPORT_CGO_CFLAGS"
	"EXPORT_CGO_CXXFLAGS"
	"EXPORT_CGO_LDFLAGS"
	"EXPORT_CC"
	"EXPORT_CXX"
)

xunreferenced \
	"$EXPORT_DLVBIN" \
	"$EXPORT_GOBIN" \
	"$EXPORT_GOROOT" \
	"$EXPORT_GOPATH" \
	"$EXPORT_GOMODCACHE" \
	"$EXPORT_GOTOOLDIR" \
	"$EXPORT_GOCACHE" \
	"$EXPORT_GOPROXY" \
	"$EXPORT_GO111MODULE" \
	"$EXPORT_GOWORK" \
	"$EXPORT_GOVCS" \
	"$EXPORT_GOARCH" \
	"$EXPORT_GOFLAGS" \
	"$EXPORT_GOFLAGS" \
	"$EXPORT_CGO_ENABLED" \
	"$EXPORT_CGO_CFLAGS" \
	"$EXPORT_CGO_CXXFLAGS" \
	"$EXPORT_CGO_LDFLAGS" \
	"$EXPORT_CC" \
	"$EXPORT_CXX"

function xcontains() {
	local value="$1"
	shift
	for element; do xis_eq "$element" "$value" && return 0; done
	return 1
}

function xsort_unique() {
	local output_name="$1" joined_list
	shift
	readarray -t sorted_list <<<"$(printf "%s\n" "$@" | sort -u)"
	joined_list=$(printf " \"%s\"" "${sorted_list[@]}")
	eval "$output_name=(${joined_list:1})"
}

P_EXPORTED_STATE=false

function xexport_apply() {
	if xis_true "$P_EXPORTED_STATE"; then
		return 0
	fi
	P_EXPORTED_STATE=true
	#xdebug "Exports: $*"
	for variable in "$@"; do
		local name="$variable"
		local value="${!name}"
		if xis_unset "$value"; then
			if ! xcontains "$variable" "EXPORT_CGO_LDFLAGS"; then
				xecho "WARNING: An empty exported variable $variable"
			fi
		fi
		name=${name:7}
		set +u
		local actual="${!name}"
		set -u
		export "P_SAVED_$name"="$actual"
		if xis_unset "$actual"; then
			export "$name"="$value"
		else
			: #xecho "INFO: Unexported variable: $name=\"$actual\""
		fi
	done
}

function xexport_clean() {
	if xis_false "$P_EXPORTED_STATE"; then
		return 0
	fi
	P_EXPORTED_STATE=n
	xdebug "Cleaning: $*"
	for variable in "$@"; do
		local name="${variable:7}"
		local save_name="P_SAVED_$name"
		set +u
		local save_value="${!save_name}"
		set -u
		export "$name"="$save_value"
	done
}

function xexport_print() {
	xfset "+u"
	for variable in "$@"; do
		local name="${variable:7}"
		local value="${!name}"
		xdebug "Exports: $name=\"$value\""
	done
	xfunset
}

EXEC_STDOUT=
EXEC_STDERR=
EXEC_STATUS=

function xexestat() {
	local prefix="$1"
	local stdout="$2"
	local stderr="$3"
	local status="$4"
	if xis_ne "$status" "0"; then
		local needStatus=true
		if xis_set "$stdout"; then
			xecho "$prefix STATUS $status, STDOUT: $stdout"
			needStatus=false
		fi
		if xis_set "$stderr"; then
			xecho "$prefix STATUS $status, STDERR: $stderr"
			needStatus=false
		fi
		if xis_true "$needStatus"; then
			xecho "$prefix STATUS: $status"
		fi
	else
		if xis_set "$stdout"; then
			xdebug "$prefix STDOUT: $stdout"
		fi
		if xis_set "$stderr"; then
			xdebug "$prefix STDERR: $stderr"
		fi
	fi
}

P_CANFAIL="[CANFAIL]"

function xis_canfail() {
	[[ "$1" == "$P_CANFAIL" ]]
}

# Execute command which can not fail
function xexec() {
	xfset "+e"
	local canfail=
	if xis_canfail "${1:-}"; then
		canfail="${1:-}"
		shift
	fi
	local command="$*"
	if xis_unset "$command"; then
		return 0
	fi
	xdebug "Exec: $command"
	{
		EXEC_STDOUT=$(chmod u+w /dev/fd/3 && eval "$command" 2>/dev/fd/3)
		EXEC_STATUS=$?
		EXEC_STDERR=$(cat <&3)
	} 3<<EOF
EOF
	xfunset
	if xis_ne "$EXEC_STATUS" "0" && xis_unset "$canfail"; then
		#xexestat "Exec" "$EXEC_STDOUT" "$EXEC_STDERR" "$EXEC_STATUS"
		xecho "ERROR: Failed to execute: $command"
		xtext "$EXEC_STDERR"
		xtext "$EXEC_STDOUT"
		xecho "ERROR: Terminating with status $EXEC_STATUS"
		xecho "ERROR: More details in file://$WRAPPER_LOGFILE"
		exit ${EXEC_STATUS}
	elif xis_true "false"; then
		if xis_set "$EXEC_STDOUT"; then
			xdebug "EXEC_STDOUT: $EXEC_STDOUT"
		fi
		if xis_set "$EXEC_STDERR"; then
			xdebug "EXEC_STDERR: $EXEC_STDERR"
		fi
	fi
}

function xexit() {
	xdebug "Finishing wrapper with STDOUT, STDERR & STATUS=$EXEC_STATUS"
	if xis_set "$EXEC_STDOUT"; then
		echo "$EXEC_STDOUT"
	fi
	if xis_set "$EXEC_STDERR"; then
		echo "$EXEC_STDERR" 1>&2
	fi
	exit "$EXEC_STATUS"
}

P_OPTIONS_STACK=()

function xfset() {
	local oldopts
	oldopts="$(set +o)"
	P_OPTIONS_STACK+=("$oldopts")
	for opt in "$@"; do
		set "$opt"
	done
}

function xfunset() {
	local oldopts="${P_OPTIONS_STACK[-1]}"
	set +vx
	eval "$oldopts"
	unset "P_OPTIONS_STACK[-1]"
}

function xssh() {
	xdebug "Target exec: $*"
	local canfail=
	if xis_canfail "${1:-}"; then
		canfail="${1:-}"
		shift
	fi
	xexec "$canfail" sshpass -p "$TARGET_PASS" ssh "${SSH_FLAGS[@]}" "$TARGET_USER@$TARGET_IPADDR" "\"$*\""
}

P_SSH_HOST_STDIO=""
P_SSH_HOST_POST=""
P_SSH_TARGET_STDIO=""
P_SSH_TARGET_PREF="" # mount -o remount,rw /;
P_SSH_TARGET_POST=""

function xflash_pending_commands() {
	if xis_set "$P_SSH_HOST_STDIO${P_SSH_HOST_POST}" ||
		xis_set "$P_SSH_TARGET_PREF${P_SSH_TARGET_STDIO}$P_SSH_TARGET_POST"; then
		if xis_set "$P_SSH_TARGET_PREF${P_SSH_TARGET_STDIO}$P_SSH_TARGET_POST"; then
			local code="${P_SSH_HOST_STDIO}sshpass -p \"$TARGET_PASS\" "
			local code="${code}ssh ${SSH_FLAGS[*]} $TARGET_USER@$TARGET_IPADDR "
			local code="$code\"$P_SSH_TARGET_PREF${P_SSH_TARGET_STDIO}$P_SSH_TARGET_POST\""
			xexec "$code"
		fi
		xexec "$P_SSH_HOST_POST"
		P_SSH_HOST_STDIO=""
		P_SSH_HOST_POST=""
		P_SSH_TARGET_STDIO=""
		P_SSH_TARGET_PREF=""
		P_SSH_TARGET_POST=""
	fi
}

function xperform_build_and_deploy() {
	local fbuild=false frebuild=false fdebug=false fexec=false

	while :; do
		if xis_eq "$1" "[BUILD]"; then
			fbuild=true
		elif xis_eq "$1" "[REBUILD]"; then
			frebuild=true
		elif xis_eq "$1" "[DEBUG]"; then
			fdebug=true
		elif xis_eq "$1" "[EXEC]"; then
			fexec=true
		elif xis_eq "$1" "[ECHO]"; then
			xset XECHO_ENABLED=true
			clear
		else
			break
		fi
		shift
	done

	xecho "$*"
	if xis_true "$fbuild"; then
		xbuild_project
	else
		xcheck_project
	fi

	if xis_false "$fdebug" && xis_true "$fexec"; then
		P_SSH_TARGET_PREF="$P_SSH_TARGET_PREF(rm -f \"$DLOOP_RESTART_FILE\"); "
		EXECUTE_COMMANDS+=("@echo 1 > $DLOOP_RESTART_FILE")
	fi

	if xis_true "$frebuild"; then
		xistall_ssh_key
	fi

	xservices_stop
	xprocesses_stop
	xfiles_delete
	xcreate_directories
	xfiles_copy
	xservices_start
	xprocesses_start

	if xis_false "$fexec" && xis_false "$fdebug"; then
		P_SSH_TARGET_PREF="$P_SSH_TARGET_PREF(rm -f \"$DLOOP_ENABLE_FILE\"); "
		EXECUTE_COMMANDS+=("@echo 1 > $DLOOP_ENABLE_FILE")
	fi

	xexecute_target_commands
	xflash_pending_commands
	if xis_true "$frebuild"; then
		xcamera_features
	fi
}

function xkill() {
	local canfail=
	if xis_canfail "${1:-}"; then
		canfail="${1:-}"
		shift
	fi
	for procname in "$@"; do
		P_SSH_TARGET_PREF="${P_SSH_TARGET_PREF}if pgrep $procname > /dev/null; then pkill $procname; fi; "
	done
}

function xscp() {
	local canfail=
	if xis_canfail "${1:-}"; then
		canfail="${1:-}"
		shift
	fi

	local dir="$TARGET_USER@$TARGET_IPADDR"

	local one="$1"
	if [[ "$one" =~ ^\:.* ]]; then
		one="$dir${one}"
	elif [[ ! "$one" =~ ^\/.* ]]; then
		one="./$one"
	fi

	local two="$2"
	if [[ "$two" =~ ^\:.* ]]; then
		two="$dir${two}"
	elif [[ ! "$two" =~ ^\/.* ]]; then
		two="./$two"
	fi

	xdebug "Target copy: $canfail $one -> $two"
	xexec "$canfail" sshpass -p "$TARGET_PASS" scp -C "${SSH_FLAGS[@]}" "$one" "$two"
}

function xfiles_delete() {
	# Delete files from DELETE_FILES
	xfiles_delete_vargs "${DELETE_FILES[@]}"
}

# shellcheck disable=SC2120
function xfiles_delete_vargs() {
	local list=("$@")
	if xis_ne "${#list[@]}" "0"; then
		local elements=""
		for filename in "${list[@]}"; do
			elements="$elements, $(basename -- "$filename")"
			P_SSH_TARGET_PREF="${P_SSH_TARGET_PREF}if [[ -f \"$filename\" ]]; then rm -f \"$filename\"; fi; "
		done
		xecho "Removing ${#list[@]} files: ${elements:2}"
	fi
}

function xclean_directory() {
	if [[ -d "$1" ]]; then
		xexec rm -rf "$1/*"
	else
		xexec mkdir -p "$1"
	fi
}

P_CACHE_SALT=$(echo -n "$PWD${TARGET_ARCH}$TARGET_GOCXX${BUILDROOT_DIR}$TARGET_IPADDR" | md5sum)
P_CACHE_SALT="${P_CACHE_SALT:0:32}"

function xcache_shash() {
	local string_hash
	string_hash=$(md5sum <<<"$1${P_CACHE_SALT}")
	string_hash="${string_hash:0:32}"
	echo "$string_hash"
}

function xcache_fhash() {
	local file_hash
	file_hash=$(md5sum "$1")
	file_hash="${file_hash:0:32}"
	echo "$file_hash-$P_CACHE_SALT"
}

function xcache_put() {
	echo "$2" >"$P_CACHE_DIR/$1"
}

function xcache_get() {
	cat "$P_CACHE_DIR/$1" 2>/dev/null
}

# shellcheck disable=SC2120
function xfiles_copy() {
	# Copy files from COPY_FILES
	local canfail=
	if xis_canfail "${1:-}"; then
		canfail="${1:-}"
		shift
	fi

	local list=("$@")
	if xis_eq "${#list[@]}" "0"; then
		list=("${COPY_FILES[@]}")
	fi
	if xis_ne "${#list[@]}" "0"; then
		local backup_source="$TEMP_DIR/data"
		if xis_false "$COPY_CACHE"; then
			xclean_directory "$P_CACHE_DIR"
		elif [[ ! -d "$P_CACHE_DIR" ]]; then
			xexec mkdir -p "$P_CACHE_DIR"
		fi

		local elements=""
		local count="0"
		local uploading=""
		local directories=()
		local symlinks=""
		for pair in "${list[@]}"; do
			IFS='|'
			# shellcheck disable=SC2206
			files=($pair)
			unset IFS
			if xis_ne "${#files[@]}" "2"; then
				xfatal "Invalid copy command: \"$pair\""
			fi
			local fileA="${files[0]}"
			local fileB="${files[1]}"
			if [[ "$fileB" =~ ^\:.* ]]; then
				uploading="1"
				local prefA="${fileA:0:1}"
				if xis_eq "$prefA" "?"; then
					fileA="${fileA:1}"
				fi
				if [[ -f "$PWD/$fileA" ]]; then
					fileA="$PWD/$fileA"
				elif [[ -f "$fileA" ]]; then
					:
				elif xis_eq "$prefA" "?"; then
					xecho "File \"$fileA\" does not exists, skipping"
					continue
				else
					xecho "ERROR: Unable to find \"$fileA\" for upload"
					exit "1"
				fi

				local name_hash file_hash
				name_hash=$(xcache_shash "$fileA")
				file_hash=$(xcache_fhash "$fileA")
				#xecho "$name_hash :: $file_hash"

				if xis_false "$COPY_CACHE" || xis_ne "$(xcache_get "$name_hash")" "$file_hash"; then
					if xis_unset "${directories[*]}"; then
						xclean_directory "$backup_source"
					fi
					local backup_target="$backup_source/${fileB:1}"
					backup_target="${backup_target//\/\//\/}"
					local backup_subdir
					backup_subdir=$(dirname "$backup_target")
					if ! xcontains "$backup_subdir" "${directories[@]}"; then
						directories+=("$backup_subdir")
					fi
					symlinks="${symlinks}ln -s \"$fileA\" \"$backup_target\"; "
					P_SSH_HOST_POST="${P_SSH_HOST_POST}xcache_put \"$name_hash\" \"$file_hash\"; "
				else
					xdebug "Skipping upload $fileA :: $name_hash :: $file_hash"
					fileB=""
				fi
			fi
			if xis_set "$fileB"; then
				elements="$elements, $(basename -- "$fileB")"
				count=$((count + 1))
			fi
		done
		if xis_ne "${#directories[@]}" "0"; then
			xexec mkdir -p "${directories[@]}"
		fi
		if xis_ne "$symlinks" ""; then
			xexec "$symlinks"
		fi
		if xis_set "$uploading"; then
			if xis_set "$elements"; then
				xecho "Uploading $count files: ${elements:2}"
				local pkg="gzip -5"
				if which pigz >/dev/null 2>&1; then
					local pkg="pigz -p$(nproc) -9"
				fi
				P_SSH_HOST_STDIO="tar -cf - -C \"$backup_source\" --dereference \".\" | $pkg - | "
				P_SSH_TARGET_STDIO="gzip -dc | tar --no-same-owner --no-same-permissions -xf - -C \"/\"; "
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
				if xis_set "$canfail"; then
					xscp "$P_CANFAIL" "$fileA" "$fileB"
				else
					xscp "$fileA" "$fileB"
				fi
			fi
		done
	fi
}

function xservices_stop() {
	# Stop services from SERVICES_STOP
	xservices_stop_vargs "${SERVICES_STOP[@]}"
}

# shellcheck disable=SC2120
function xservices_stop_vargs() {
	local list=("$@")
	if xis_ne "${#list[@]}" "0"; then
		local elements=""
		for service in "${list[@]}"; do
			elements="$elements, $service"
			#P_SSH_TARGET_PREF="${P_SSH_TARGET_PREF}systemctl mask \"$service\"; "
			P_SSH_TARGET_PREF="${P_SSH_TARGET_PREF}systemctl stop \"$service\"; "
		done
		xecho "Stopping ${#list[@]} services: ${elements:2}"
	fi
}

function xservices_start() {
	# Start services from SERVICES_START
	xservices_start_vargs "${SERVICES_START[@]}"
}

# shellcheck disable=SC2120
function xservices_start_vargs() {
	local list=("$@")
	if xis_ne "${#list[@]}" "0"; then
		local elements=""
		for service in "${list[@]}"; do
			elements="$elements, $service"
			#P_SSH_TARGET_PREF="${P_SSH_TARGET_PREF}systemctl unmask \"$service\"; "
			P_SSH_TARGET_POST="${P_SSH_TARGET_POST}systemctl start \"$service\"; "
		done
		xecho "Starting ${#list[@]} services: ${elements:2}"
	fi
}

function xprocesses_stop() {
	# Stop processes from PROCESSES_STOP
	xprocesses_stop_vargs "${PROCESSES_STOP[@]}"
}

# shellcheck disable=SC2120
function xprocesses_stop_vargs() {
	local list=("$@")
	if xis_ne "${#list[@]}" "0"; then
		local elements=""
		for procname in "${list[@]}"; do
			elements="$elements, $procname"
			P_SSH_TARGET_PREF="${P_SSH_TARGET_PREF}if pgrep $procname > /dev/null; then pkill $procname; fi; "
		done
		xecho "Terminating ${#list[@]} processes: ${elements:2}"
	fi
}

function xprocesses_start() {
	# Start processes from PROCESSES_START
	xprocesses_start_vargs "${PROCESSES_START[@]}"
}

# shellcheck disable=SC2120
function xprocesses_start_vargs() {
	local list=("$@")
	if xis_ne "${#list[@]}" "0"; then
		local elements=""
		for procname in "${list[@]}"; do
			elements="$elements, $procname"
			P_SSH_TARGET_POST="$P_SSH_TARGET_POST${procname}; "
		done
		xecho "Starting ${#list[@]} processes: ${elements:2}"
	fi
}

function xcreate_directories() {
	# Create directories from DIRECTORIES_CREATE
	xcreate_directories_vargs "${DIRECTORIES_CREATE[@]}"
}

# shellcheck disable=SC2120
function xcreate_directories_vargs() {
	local list=("$@")
	if xis_ne "${#list[@]}" "0"; then
		local elements=""
		for dirname in "${list[@]}"; do
			elements="$elements, $dirname"
			P_SSH_TARGET_POST="${P_SSH_TARGET_POST}mkdir -p \"$dirname\"; "
		done
		xecho "Creating ${#list[@]} directories: ${elements:2}"
	fi
}

function xexecute_target_commands() {
	# Create directories from DIRECTORIES_CREATE
	xexecute_target_commands_vargs "${EXECUTE_COMMANDS[@]}"
}

# shellcheck disable=SC2120
function xexecute_target_commands_vargs() {
	local list=("$@")
	if xis_ne "${#list[@]}" "0"; then
		local elements=""
		local count=$((0))
		for command in "${list[@]}"; do
			if xis_eq "${command:0:1}" "@"; then
				command="${command:1}"
			else
				elements="$elements, ${command%% *}"
				count=$(("$count" + 1))
			fi
			P_SSH_TARGET_POST="$P_SSH_TARGET_POST($command); "
		done
		if xis_set "$elements"; then
			xecho "Executing $count target commands: ${elements:2}"
		fi
	fi
}

P_GOCACHE_CLEANED=false

function xclean_gocache() {
	if xis_false "$CLEAN_GOCACHE" || xis_true "$P_GOCACHE_CLEANED"; then
		return 0
	fi
	P_GOCACHE_CLEANED=true
	export GOCACHE="$TEMP_DIR/gocache"
	xclean_directory "$GOCACHE"
	xexec go clean -cache
}

function xtest_installed() {
	if [[ ! -f "$1" ]]; then
		xerror "Reqired binary '$(basename -- "$1")' is not installed."
		xfatal "Check installation instructions: $2"
	fi
}

P_GOLANGCI_LINT_DONE=false
P_STATICCHECK_DONE=false
P_GO_VET_DONE=false
P_LLENCHECK_DONE=false

function xreset_lint_state() {
	P_GOLANGCI_LINT_DONE=false
	P_STATICCHECK_DONE=false
	P_GO_VET_DONE=false
	P_LLENCHECK_DONE=false
}

function xload_lint_state() {
	local state=()
	IFS=' ' read -r -a state <<<"$(cat "$P_CACHE_DIR/__linters_result.state" 2>/dev/null)"
	if xis_eq "${#state[@]}" "4"; then
		P_GOLANGCI_LINT_DONE="${state[0]}"
		P_STATICCHECK_DONE="${state[1]}"
		P_GO_VET_DONE="${state[2]}"
		P_LLENCHECK_DONE="${state[3]}"
	else
		xreset_lint_state
	fi
}

function xsave_lint_state() {
	if xis_eq "$name_hash" ""; then
		return
	fi
	xcache_put "$name_hash" "$file_hash"
	local state=(
		"$P_GOLANGCI_LINT_DONE"
		"$P_STATICCHECK_DONE"
		"$P_GO_VET_DONE"
		"$P_LLENCHECK_DONE"
	)
	echo "${state[@]}" >"$P_CACHE_DIR/__linters_result.state"
}

function xcheck_results() {
	xtext "$EXEC_STDOUT"
	xtext "$EXEC_STDERR"
	if xis_ne "$EXEC_STATUS" "0"; then
		eval "$1"=false
		if xis_true "$2"; then
			xecho "ERROR: $3 warnings has been detected. Fix before continue ($EXEC_STATUS)."
			xsave_lint_state
			exit "$EXEC_STATUS"
		fi
	else
		eval "$1"=true
	fi
}

function xcheck_project() {
	local name_hash="" file_hash="" dir_hash="$P_CACHE_DIR/__project_checklist.log"
	local diff_filter_args=() diff_filter_command=""
	if xis_true "$GOLANGCI_LINT_ENABLE" || xis_true "$STATICCHECK_ENABLE" ||
		xis_true "$GO_VET_ENABLE" || xis_true "$LLENCHECK_ENABLE"; then
		xexec find -L "." -type f "\(" -iname "\"*\"" ! -iname "\"$TARGET_BIN_SOURCE\"" "\)" \
			-not -path "\"./.git/*\"" -exec date -r {} \
			"\"+%m-%d-%Y %H:%M:%S\"" "\;" ">" "$dir_hash"
		xtext "$EXEC_STDOUT"
		xtext "$EXEC_STDERR"
		xload_lint_state
		name_hash=$(xcache_shash "$dir_hash")
		file_hash=$(xcache_fhash "$dir_hash")
		#xecho "$name_hash :: $file_hash"
		if xis_ne "$(xcache_get "$name_hash")" "$file_hash" || xis_true "$CLEAN_GOCACHE"; then
			xreset_lint_state
		fi
		if xis_true "$P_GOLANGCI_LINT_DONE" &&
			xis_true "$P_STATICCHECK_DONE" &&
			xis_true "$P_GO_VET_DONE" &&
			xis_true "$P_LLENCHECK_DONE"; then
			return 0
		fi
		export PYTHONPYCACHEPREFIX="$TEMP_DIR/pycache"
		if [[ ! -d "$PYTHONPYCACHEPREFIX" ]]; then
			xexec mkdir -p "$PYTHONPYCACHEPREFIX"
		fi
		if xis_set "$GIT_COMMIT_FILTER"; then
			diff_filter_args+=("-c=$GIT_COMMIT_FILTER")
		fi
		diff_filter_command=(
			"python3" "-X" "pycache_prefix=\"$PYTHONPYCACHEPREFIX\""
			"./.vscode/scripts/py-diff-check.py" "${diff_filter_args[@]}"
		)
		xclean_gocache
	fi
	if xis_true "$GOLANGCI_LINT_ENABLE" && xis_false "$P_GOLANGCI_LINT_DONE"; then
		xtest_installed "$LOCAL_GOLANGCI_LINT" "https://golangci-lint.run/usage/install/"
		local linter_args=() linters_list=()
		xsort_unique linters_list "${GOLANGCI_LINT_LINTERS[@]}"
		if xcontains "all" "${linters_list[@]}"; then
			local disabled_list=("${GOLANGCI_LINT_DEPRECATED[@]}" "${GOLANGCI_LINT_SUPRESSED[@]}")
			for linter in "${linters_list[@]}"; do
				if xis_eq "$linter" "all" || xis_eq "$linter" "-all"; then
					continue
				fi
				if [[ "$linter" == -* ]]; then
					disabled_list+=("${linter:1}")
				fi
			done
			xsort_unique disabled_list "${disabled_list[@]}"
			linter_args+=("--enable-all")
			for linter in "${disabled_list[@]}"; do
				linter_args+=("-D" "$linter")
			done
		else
			linter_args+=("--disable-all")
			for linter in "${linters_list[@]}"; do
				if xis_eq "$linter" "all" || xis_eq "$linter" "-all"; then
					continue
				fi
				if [[ ! "$linter" == -* ]]; then
					linter_args+=("-E" "$linter")
				fi
			done
		fi
		local scheck="$TEMP_DIR/golangci-lint.log"
		xecho "Running $(xdecorate golangci-lint) (details: file://$scheck)"
		xexec "$P_CANFAIL" "$LOCAL_GOLANGCI_LINT" "run" "${linter_args[@]}" \
			"./..." ">" "$scheck" "2>&1"
		if xis_true "$GOLANGCI_LINT_FILTER"; then
			xexec "$P_CANFAIL" cat "$scheck" "|" "${diff_filter_command[@]}" -p -x
		else
			xexec "$P_CANFAIL" cat "$scheck" "|" "${diff_filter_command[@]}" -a -p -x
		fi
		xcheck_results "P_GOLANGCI_LINT_DONE" "$GOLANGCI_LINT_FAIL" "Golangci-lint"
	fi
	if xis_true "$STATICCHECK_ENABLE" && xis_false "$P_STATICCHECK_DONE"; then
		xtest_installed "$LOCAL_STATICCHECK" "https://staticcheck.dev/docs/"
		xexport_clean "${GOLANG_EXPORTS[@]}"
		local flags=() go_version
		go_version=$("$BUILDROOT_GOBIN" version)
		go_version=$(awk '{print $3}' <<<"$go_version")
		go_version="${go_version%.*}"
		flags+=("-go" "${go_version:2}")
		if xis_set "$STATICCHECK_CHECKS"; then
			flags+=("-checks" "$STATICCHECK_CHECKS")
		fi
		local scheck="$TEMP_DIR/staticcheck.log"
		xecho "Running $(xdecorate staticcheck) (details: file://$scheck)"
		xexec "$P_CANFAIL" "$LOCAL_STATICCHECK" "${flags[@]}" "./..." "2>&1" ">" "$scheck"
		if xis_true "$STATICCHECK_FILTER"; then
			xexec "$P_CANFAIL" cat "$scheck" "|" "${diff_filter_command[@]}" -p -x \
				-e="\"$STATICCHECK_SUPRESS\""
		else
			xexec "$P_CANFAIL" cat "$scheck" "|" "${diff_filter_command[@]}" -a -p -x
		fi
		xcheck_results "P_STATICCHECK_DONE" "$STATICCHECK_FAIL" "Staticcheck"
	fi
	if xis_true "$GO_VET_ENABLE" && xis_false "$P_GO_VET_DONE"; then
		xecho "Running $(xdecorate go vet) on $(xdecorate ${TARGET_BUILD_LAUNCHER})..."
		xexec "$P_CANFAIL" "$BUILDROOT_GOBIN" "vet" "${GO_VET_FLAGS[@]}" "./..."
		xcheck_results "P_GO_VET_DONE" "$GO_VET_FAIL" "Go-vet"
	fi
	if xis_true "$LLENCHECK_ENABLE" && xis_false "$P_LLENCHECK_DONE"; then
		local project_name
		project_name="$(basename -- "$PWD")"
		xecho "Running $(xdecorate line-length-limit) check on $(xdecorate "$project_name")"
		if xis_true "$LLENCHECK_FILTER"; then
			xexec "$P_CANFAIL" "${diff_filter_command[@]}" \
				-l="$LLENCHECK_LIMIT" -t="$LLENCHECK_TABWIDTH" "${diff_filter_args[@]}"
		else
			xexec "$P_CANFAIL" "${diff_filter_command[@]}" \
				-a -l="$LLENCHECK_LIMIT" -t="$LLENCHECK_TABWIDTH" "${diff_filter_args[@]}"
		fi
		xcheck_results "P_LLENCHECK_DONE" "$LLENCHECK_FAIL" "Line-length-limit"
	fi
	xsave_lint_state
}

function xbuild_project() {
	xclean_gocache
	xcheck_project
	local flags=()
	flags+=("build")
	#flags+=("-race")
	#flags+=("-msan")
	#flags+=("-asan")
	xexport_apply "${GOLANG_EXPORTS[@]}"
	xexec "$BUILDROOT_GOBIN" "${flags[@]}" "${TARGET_BUILD_FLAGS[@]}"
	if xis_ne "$EXEC_STATUS" "0"; then
		xdebug "BUILDROOT_DIR=$BUILDROOT_DIR"
		xdebug "EXPORT_GOPATH=$EXPORT_GOPATH"
		xdebug "EXPORT_GOROOT=$EXPORT_GOROOT"
		xexit
	else
		xexestat "Exec" "$EXEC_STDOUT" "$EXEC_STDERR" "$EXEC_STATUS"
	fi
}

# Set camera features
function xcamera_features() {
	local feature_args=""
	for feature in "${CAMERA_FEATURES_ON[@]}"; do
		feature_args="$feature_args&$feature=true"
	done
	for feature in "${CAMERA_FEATURES_OFF[@]}"; do
		feature_args="$feature_args&$feature=false"
	done
	if xis_unset "$feature_args"; then
		return 0
	fi
	local timeout=10
	local wget_command=(timeout "$timeout" wget --no-proxy "--timeout=$timeout"
		-q -O - "\"http://$TARGET_IPADDR/cgi/features.cgi?${feature_args:1}\"")
	xexec "${wget_command[*]}"
	local response="${EXEC_STDOUT//[$'\t\r\n']/}"
	xdebug "WGET response: $response"

	local features_on_set=""
	local features_on_err=""
	for feature in "${CAMERA_FEATURES_ON[@]}"; do
		local pattern="\"$feature\": set to True"
		if grep -i -q "$pattern" <<<"$response"; then
			features_on_set="$features_on_set, $feature"
		else
			features_on_err="$features_on_err, $feature"
		fi
	done

	local features_off_set=""
	local features_off_err=""
	for feature in "${CAMERA_FEATURES_OFF[@]}"; do
		local pattern="\"$feature\": set to False"
		if grep -i -q "$pattern" <<<"$response"; then
			features_off_set="$features_off_set, $feature"
		else
			features_off_err="$features_off_err, $feature"
		fi
	done

	local features_set=""
	if xis_set "$features_on_set"; then
		features_set="$features_set; TRUE: ${features_on_set:2}"
	fi
	if xis_set "$features_off_set"; then
		features_set="$features_set; FALSE: ${features_off_set:2}"
	fi

	local features_err=""
	if xis_set "$features_on_err"; then
		features_err="$features_err; TRUE: ${features_on_err:2}"
	fi
	if xis_set "$features_off_err"; then
		features_err="$features_err; FALSE: ${features_off_err:2}"
	fi

	if xis_set "$features_set"; then
		xecho "Camera features set to ${features_set:2}"
	fi
	if xis_set "$features_err"; then
		xecho "WARNING: Failed to set camera features to ${features_err:2}"
	fi
}

function xtruncate_text_file() {
	local name="$1"
	local limit="$2"
	local target="$3"
	if [[ ! -f "$name" ]]; then
		return 0
	fi
	local actual
	actual=$(wc -l "$name")
	actual=${actual%% *}
	local truncate=$((actual > limit ? 1 : 0))
	if xis_false "$truncate"; then
		return 0
	fi
	local tmp_name="$name.tmp"
	xdebug "Truncating $WRAPPER_LOGFILE from $actual to $target limit, thresold $limit."
	xexec "cp \"$name\" \"$tmp_name\""
	local offset=$((actual - target))
	xexec "tail -$offset \"$tmp_name\" > \"$name\""
	xexec "rm -rf \"$tmp_name\""
}

function xtruncate_log_file() {
	xtruncate_text_file "$WRAPPER_LOGFILE" 5000 300
}

xtruncate_log_file

function xsed_escape() {
	printf '%s' "$*" | sed -e 's/[\/&-\"]/\\&/g'
}

function xsed_replace() {
	local in="$1" out="$2"
	in="$(xsed_escape "$in")"
	out="$(xsed_escape "$out")"
	shift
	shift
	for file in "$@"; do
		xexec sed -i "\"s/$in/$out/g\"" "$file"
	done
}

function xprepare_runtime_scripts() {
	local exec_args=""
	for item in "${TARGET_EXEC_ARGS[@]}"; do
		exec_args="$exec_args \"$item\""
	done
	local supress=""
	for item in "${TARGET_SUPRESS_MSSGS[@]}"; do
		supress="$supress \"$item\""
	done
	xexec cp "$PWD/.vscode/scripts/dlv-loop.sh" "$TEMP_DIR/dlv-loop.sh"
	xexec cp "$PWD/.vscode/scripts/dlv-exec.sh" "$TEMP_DIR/dlv-exec.sh"
	xsed_replace "__TARGET_IPPORT__" "$TARGET_IPPORT" "$TEMP_DIR/dlv-loop.sh"
	xsed_replace "__TARGET_BINARY_PATH__" "$TARGET_BIN_DESTIN" "$TEMP_DIR/dlv-exec.sh"
	xsed_replace "__TARGET_BINARY_ARGS__" "${exec_args:1}" "$TEMP_DIR/dlv-exec.sh"
	xsed_replace "__TARGET_SUPRESS_MSSGS__" "${supress:1}" "$TEMP_DIR/dlv-loop.sh" "$TEMP_DIR/dlv-exec.sh"
	COPY_FILES+=(
		"$TEMP_DIR/dlv-loop.sh|:/usr/bin/dl"
		"$TEMP_DIR/dlv-exec.sh|:/usr/bin/de"
	)
}

function xistall_ssh_key() {
	if xis_false "$INSTALL_SSH_KEY"; then
		return
	fi
	local key_a="$HOME/.ssh/goflame-key"
	local key_b="$HOME/.ssh/goflame-key.pub"
	if [[ ! -f "$key_a" ]] || [[ ! -f "$key_b" ]]; then
		xexec rm -f "$key_a" "$key_b"
		xexec ssh-keygen -t ed25519 -C "goflame@elvees.com" -P "\"\"" -f "$key_a"
	fi
	DIRECTORIES_CREATE+=("/root/.ssh")
	COPY_FILES+=("$key_b|:/root/.ssh/goflame-key.pub")
	EXECUTE_COMMANDS+=(
		#"if [ ! -f /etc/ssh/sshd_config.old ]; cp /etc/ssh/sshd_config /etc/ssh/sshd_config.old; fi"
		#"sed -i 's/^#PubkeyAuthentication/PubkeyAuthentication/g' /etc/ssh/sshd_config"
	)
}
