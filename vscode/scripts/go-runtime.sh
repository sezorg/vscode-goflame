#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# GO compiler wrapper environment
#
# Log messages are stored into file:///var/tmp/goflame/go-wrapper.log

set -euo pipefail
#set -x

# Lokuup for unnecessary complex variable references: \$\{\w+\}([^\w]|$)

function xis_true() {
	[[ "${1^^}" =~ ^(1|T|TRUE|Y|YES)$ ]]
}

function xis_false() {
	[[ ! "${1^^}" =~ ^(1|T|TRUE|Y|YES)$ ]]
}

function xis_defined() {
	[[ -v "$1" ]]
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

function xis_succeeded() {
	xis_eq "$?" "0"
}

function xis_failed() {
	xis_ne "$?" "0"
}

function xis_file_exists() {
	[[ -f "$*" ]]
}

function xis_dir_exists() {
	[[ -d "$*" ]]
}

function xis_executable() {
	command -v "$1" &>/dev/null
}

function xis_ipv4_addr() {
	[[ "$*" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

function xis_mac_addr() {
	pattern='^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$'
	[[ "$*" =~ $pattern ]]
}

function xto_lowercase() {
	input_string=$1
	lowercase_string=${input_string,,}
	echo "$lowercase_string"
}

function xhas_prefix() {
	input_string="$1"
	prefix="$2"
	[[ "$input_string" == "$prefix"* ]]
}

function xjoin_strings() {
	local separator="$1" length="${#1}" joined
	shift
	joined=$(printf "$separator%s" "$@")
	echo "${joined:$length}"
}

function xjoin_elements() {
	local basename="$1"
	shift
	local result=""
	if xis_ne "$#" "0"; then
		for element in "$@"; do
			if xis_true "$basename"; then
				element="$(basename -- "$element")"
			fi
			result="$result, $(xelement "$element")"
		done
		result="${result:2}"
	fi
	echo "$result"
}

function xbegins_with() {
	case "$1" in
	"$2"*)
		true
		;;
	*)
		false
		;;
	esac
}

function xtime() {
	date +%s.%N
}

function xformat_time() {
	local from="$1" to="$2"
	local time days days_frac hours hours_frac mins secs pad="0000000"
	time=$(echo "$to - $from" | bc)
	days=$(echo "$time/86400" | bc)
	days_frac=$(echo "$time-86400*$days" | bc)
	hours=$(echo "$days_frac/3600" | bc)
	hours_frac=$(echo "$days_frac-3600*$hours" | bc)
	mins=$(echo "$hours_frac/60" | bc)
	secs=$(echo "$hours_frac-60*$mins" | bc)
	secs=$(printf "%02.3fs" "$secs")
	secs="${pad:${#secs}}$secs"
	if [[ "$days" != "0" ]]; then
		printf "%dd %02.2dh %02.2dm %s" "$days" "$hours" "$mins" "$secs"
	elif [[ "$hours" != "0" ]]; then
		printf "%dh %02.2dm %s" "$hours" "$mins" "$secs"
	elif [[ "$mins" != "0" ]]; then
		printf "%dm %s" "$mins" "$secs"
	else
		printf "%s" "$secs"
	fi
}

RED=$(printf "\e[31m")
GREEN=$(printf "\e[32m")
YELLOW=$(printf "\e[33m")
BLUE=$(printf "\e[34m")
GRAY=$(printf "\e[90m")
UNDERLINE=$(printf "\e[4m")
LINK="$BLUE$UNDERLINE"
NC=$(printf "\e[0m")
NCC=$(printf "\e[0m")

P_COLOR_FILTER="s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g"
P_ELAPSED_PREFIX=""
P_ELAPSED_COLOR=""

function xelapsed() {
	local end_time
	end_time="$(date +%s.%N)"
	xecho "$P_ELAPSED_COLOR${P_ELAPSED_PREFIX}Total runtime: $(xformat_time "$P_TIME_STARTED" "$end_time") (details: $(xhyperlink "file:///var/tmp/goflame/go-wrapper.log")$P_ELAPSED_COLOR)"
}

P_TIME_STARTED="$(date +%s.%N)"
P_TIME_PREV_OUT="$P_TIME_STARTED"
P_TIME_PREV_LOG="$P_TIME_STARTED"
trap xat_exit_trap EXIT

function xat_exit_trap() {
	xelapsed "$P_TIME_STARTED"
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

if ! xis_file_exists "$HOME/.shellcheckrc"; then
	echo "external-sources=true" >"$HOME/.shellcheckrc"
fi

function xset() {
	eval "$*"
}

# To omit shellcheck warnings
function xunreferenced() {
	return 0
}

SCP_FLAGS=(
	-T
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

SSH_FLAGS=(
	"${SCP_FLAGS[@]}"
	-x
)

P_TEMP_DIR="/var/tmp/goflame"
P_CACHEDB_DIR="$P_TEMP_DIR/cachedb"
P_SCRIPTS_DIR="$P_TEMP_DIR/scripts"
P_UPLOAD_DIR="$P_TEMP_DIR/upload"

mkdir -p "$P_TEMP_DIR" "$P_CACHEDB_DIR" "$P_UPLOAD_DIR"

XECHO_ENABLED=
XDEBUG_ENABLED=
DT="$(date '+%d/%m/%Y %H:%M:%S') "
CE=$'\u1B' # Color escape
EP=""
PI="\`"
PO="'"
xunreferenced "$DT" "$CE" "$EP"

if ! xis_defined TARGET_ARCH; then
	TARGET_ARCH=""
fi
TARGET_GOCXX=""
TARGET_DOMAIN="UNKNOWN-TARGET_DOMAIN"
TARGET_IPADDR="UNKNOWN-TARGET_IPADDR"
TARGET_IPPORT="UNKNOWN-TARGET_IPPORT"
TARGET_USER="UNKNOWN-TARGET_USER"
TARGET_PASS="UNKNOWN-TARGET_PASS"
TARGET_BUILD_LAUNCHER=""
TARGET_BIN_SOURCE=""
TARGET_BIN_DESTIN=""
TARGET_EXEC_ARGS=()
TARGET_SUPRESS_MSSGS=()

TARGET_BUILD_GOFLAGS=()
TARGET_BUILD_LDFLAGS=()

TTY_PORT="auto" # пустая строка или "auto" - автоматическое определение
TTY_SPEED="115200"
TTY_PICOCOM="picocom"
TTY_DIRECT=false
TTY_USER=""
TTY_PASS=""
TTY_DELAY="200" # milliseconds
TTY_RETRY="5"

BUILDROOT_DIR="UNKNOWN-BUILDROOT_DIR"
CLEAN_GOCACHE=false
GIT_COMMIT_FILTER="" #
REBUILD_FORCE_LINTERS=true
GOLANGCI_LINT_ENABLE=false
GOLANGCI_LINT_LINTERS=(
	"all"
	"-depguard"
	"-gochecknoglobals"
)
GOLANGCI_LINT_ARGUMENTS=(
	"--max-issues-per-linter" "0"
	"--max-same-issues" "0"
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
PRECOMMIT_ENABLE=false
PRECOMMIT_FAIL=true

USE_RSYNC_METHOD=true
USE_RSYNC_BINARY="rsync"
USE_PIGZ_COMPRESSION=true
USE_PIGZ_BINARY="pigz"
USE_ASYNC_LINTERS=true
USE_NO_COLORS=false
USE_SERVICE_MASKS=false
INSTALL_SSH_KEYS=false

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

LOCAL_DLVBIN="$(which dlv)"
LOCAL_GOBIN="$(which go)"
LOCAL_GOPATH="$(go env GOPATH)"
LOCAL_STATICCHECK="$LOCAL_GOPATH/bin/staticcheck"
LOCAL_GOLANGCI_LINT="$LOCAL_GOPATH/bin/golangci-lint"

P_CONFIG_INI_LOADED=false
if xis_file_exists "$SCRIPT_DIR/../config.ini"; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/../config.ini"
	P_CONFIG_INI_LOADED=true
fi
if xis_file_exists "$SCRIPT_DIR/../config-user.ini"; then
	# shellcheck disable=SC1091
	source "$SCRIPT_DIR/../config-user.ini"
	P_CONFIG_INI_LOADED=true
fi

P_IGNORE_PATTERN="$(printf "\n%s" "${MESSAGES_IGNORE[@]}")"
P_IGNORE_PATTERN="${P_IGNORE_PATTERN:1}"
P_FIRST_ECHO=true
P_MESSAGE_SOURCE=$(basename -- "$0") #"${BASH_SOURCE[0]}")
P_MESSAGE_SOURCE="${P_MESSAGE_SOURCE%.*}"

if xis_true "$USE_NO_COLORS"; then
	RED=""
	GREEN=""
	YELLOW=""
	BLUE=""
	GRAY=""
	UNDERLINE=""
	LINK=""
	NC=""
	NCC=""
fi

function xemit() {
	local echo_flag="$1"
	shift
	local time_stamp actual_time elapsed_time message_log message_out input="$*"
	input="${input//$'\r'/\\r}"
	input="${input//$'\n'/\\n}"
	input=" $GRAY""[$P_MESSAGE_SOURCE]$NC $input"
	if xis_set "$input"; then
		input=$(grep -v "$P_IGNORE_PATTERN" <<<"$input")
		if xis_unset "$input"; then
			return 0
		fi
	fi
	time_stamp="$(date '+%d/%m/%Y %H:%M:%S.%N')"
	time_stamp="${time_stamp:0:-6}"
	actual_time="$(date +%s.%N)"
	elapsed_time=" +$(xformat_time "$P_TIME_PREV_LOG" "$actual_time")"
	P_TIME_PREV_LOG="$actual_time"
	message_log="$GREEN$time_stamp$BLUE$elapsed_time$NC$input"
	if xis_set "$echo_flag"; then
		elapsed_time=" +$(xformat_time "$P_TIME_PREV_OUT" "$actual_time")"
		P_TIME_PREV_OUT="$actual_time"
		message_out="$GREEN$time_stamp$BLUE$elapsed_time$NC$input"
	fi
	if xis_unset "$P_FIRST_ECHO"; then
		if xis_set "$echo_flag"; then
			echo >&2 "$EP$message_out$NCC"
		fi
		echo "$message_log" | sed -r "$P_COLOR_FILTER" >>"$WRAPPER_LOGFILE"
	else
		P_FIRST_ECHO=
		if xis_set "$XECHO_ENABLED" || xis_set "$XDEBUG_ENABLED"; then
			echo >&2
		fi
		if xis_set "$echo_flag"; then
			echo >&2 "$EP$message_out$NCC"
		fi
		echo >>"$WRAPPER_LOGFILE"
		echo "$message_log" | sed -r "$P_COLOR_FILTER" >>"$WRAPPER_LOGFILE"
	fi
}

function xterminate() {
	exit "$1"
}

function xecho() {
	# Echo message
	xemit "$XECHO_ENABLED" "$*"
}

function xdebug() {
	# Debug message
	xemit "$XDEBUG_ENABLED" "DEBUG: $*"
}

function xwarn() {
	xemit "1" "${YELLOW}WARNING: ${*//$NC/$NC$YELLOW}"
}

function xerror() {
	P_ELAPSED_PREFIX="ERROR: "
	P_ELAPSED_COLOR="$RED"
	xemit "1" "${RED}ERROR: ${*//$NC/$NC$RED}"
}

function xfatal() {
	P_ELAPSED_PREFIX="FATAL: "
	P_ELAPSED_COLOR="$RED"
	xemit "1" "${RED}FATAL: ${*//$NC/$NC$RED}"
	xterminate "1"
}

function xtext() {
	local color="$1" source text lines code_link prefix
	shift
	source="$*"
	if xis_unset "$source"; then
		return 0
	fi
	text="$(sed -r "$P_COLOR_FILTER" <<<"$source")"
	# shellcheck disable=SC2206
	IFS=$'\n' lines=($text)
	for line in "${lines[@]}"; do
		line="${line//$'\r'/}"
		if xis_set "$line"; then
			code_link="${line%% *}"
			# shellcheck disable=SC2001
			prefix=$(sed 's/:.*//' <<<"$code_link")
			if xis_file_exists "./$prefix"; then
				xecho "$LINK$code_link$NC$color${line:${#code_link}}"
			else
				xecho "$color$line$NC"
			fi
		fi
	done
}

function xdecorate() {
	echo "$GRAY$PI$*$PO$NC"
}

function xelement() {
	echo "$GRAY$*$NC"
}

function xexecutable() {
	echo "$BLUE$PI$*$PO$NC"
}

function xexecutable_plain() {
	echo "$BLUE$*$NC"
}

function xhyperlink() {
	echo "$LINK$*$NC"
}

if xis_false "$P_CONFIG_INI_LOADED"; then
	xerror "Unable to load configuration from $(xhyperlink "file://./.vscode/config-user.ini") or $(xhyperlink "file://./.vscode/config.ini")."
	xfatal "See documentation for more details."
fi

BUILDROOT_HOST_DIR="$BUILDROOT_DIR/output/host"
BUILDROOT_TARGET_DIR="$BUILDROOT_DIR/output/target"

TARGET_BIN_NAME=$(basename -- "$TARGET_BIN_DESTIN")
DELVE_DAP_START="dlv dap --listen=:2345 --api-version=2 --log"
BUILDROOT_GOBIN="$BUILDROOT_HOST_DIR/bin/go"
WRAPPER_LOGFILE="$P_TEMP_DIR/go-wrapper.log"
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
	if xis_file_exists "$BUILDROOT_DIR/output/host/bin/arm-buildroot-linux-gnueabihf-gcc"; then
		TARGET_ARCH="arm"
	elif xis_file_exists "$BUILDROOT_DIR/output/host/bin/aarch64-buildroot-linux-gnu-gcc"; then
		TARGET_ARCH="arm64"
	elif ! xis_dir_exists "$BUILDROOT_DIR"; then
		xfatal "Toolchain $(xdecorate "BUILDROOT_DIR") does not exist: $BUILDROOT_DIR."
	else
		xfatal "Can not determine target architecture from $(xdecorate "BUILDROOT_DIR"): $BUILDROOT_DIR."
	fi
fi

P_TARGET_GOCXX=""
P_TARGET_PLATFORM=""
case "$TARGET_ARCH" in
"arm")
	P_TARGET_GOCXX="arm-buildroot-linux-gnueabihf"
	P_TARGET_PLATFORM="armv7l"
	;;
"arm64")
	P_TARGET_GOCXX="aarch64-buildroot-linux-gnu"
	P_TARGET_PLATFORM="aarch64"
	;;
"host")
	P_TARGET_GOCXX="gcc"
	P_TARGET_PLATFORM="x86_64"
	;;
*) xfatal "Can not determine compiler for TARGET_ARCH=\"$TARGET_ARCH\"" ;;
esac

if xis_unset "$TARGET_GOCXX"; then
	TARGET_GOCXX="$P_TARGET_GOCXX"
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

if xis_eq "$TARGET_ARCH" "host"; then
	BUILDROOT_GOBIN="go"

	EXPORT_GOROOT=""
	EXPORT_GOPATH=""
	EXPORT_GOMODCACHE=""
	EXPORT_GOTOOLDIR=""
	EXPORT_GOCACHE=""

	EXPORT_GOARCH=""

	EXPORT_CGO_CFLAGS=""
	EXPORT_CGO_CXXFLAGS=""
	EXPORT_CC=""
	EXPORT_CXX=""
fi

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

function xdecode_array() {
	local output_name="$1" joined_list
	shift
	local text joined_list
	readarray -t text <<<"$@"
	joined_list=$(printf " \"%s\"" "${text[@]}")
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
		if xis_unset "$value" && xis_ne "$TARGET_ARCH" "host"; then
			if ! xcontains "$variable" "EXPORT_CGO_LDFLAGS"; then
				xwarn "An empty exported variable $variable"
			fi
		fi
		name=${name:7}
		set +u
		local actual="${!name}"
		set -u
		export "P_SAVED_$name"="$actual"
		if xis_unset "$actual"; then
			export "$name"="$value"
			#xdebug "Exports: $name=$value"
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
	local prefix="$1" stdout="$2" stderr="$3" status="$4"
	if xis_ne "$status" "0"; then
		local needStatus=true
		if xis_set "$stdout"; then
			xecho "$prefix STATUS $(xexec_status "$status"), STDOUT: $stdout"
			needStatus=false
		fi
		if xis_set "$stderr"; then
			xecho "$prefix STATUS $(xexec_status "$status"), STDERR: $stderr"
			needStatus=false
		fi
		if xis_true "$needStatus"; then
			xecho "$prefix STATUS: $(xexec_status "$status")"
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

function xsuggest_to_install_message() {
	local executable="$1" lookup packages suggest
	if xis_file_exists "$executable"; then
		return 0
	fi
	if xis_executable "$executable" || ! xis_executable "dnf"; then
		return 0
	fi
	# shellcheck disable=SC2207
	packages=($(dnf search "$executable" --color never 2>/dev/null | awk 'FNR>=2{ print $1 }'))
	lookup="$executable."
	for package in "${packages[@]}"; do
		if xbegins_with "$package" "$lookup"; then
			suggest="Try to install it with: ${GRAY}dnf install $(xexecutable_plain "$package")"
			echo "Command $(xexecutable "$executable") not found. $suggest"
		fi
	done
}

function xsuggest_to_install() {
	local message
	message=$(xsuggest_to_install_message "$@")
	if xis_set "$message"; then
		xwarn "$message"
		return 1
	fi
}

P_CANFAIL="[CANFAIL]"

function xis_canfail() {
	[[ "$1" == "$P_CANFAIL" ]]
}

# Execute command which can not fail
function xexec() {
	local canfail=
	if xis_canfail "${1:-}"; then
		canfail="${1:-}"
		shift
	fi
	local command="$*" text
	if xis_unset "$command"; then
		return 0
	fi
	text="${command//$'\r'/\\r}"
	text="${text//$'\n'/\\n}"
	xdebug "Exec: $text"
	xfset "+e"
	{
		EXEC_STDOUT=$(chmod u+w /dev/fd/3 && eval "$command" 2>/dev/fd/3)
		EXEC_STATUS=$?
		EXEC_STDERR=$(cat <&3)
	} 3<<EOF
EOF
	xfunset
	if xis_ne "$EXEC_STATUS" "0" && xis_unset "$canfail"; then
		local executable="${text%% *}" prefix message directory
		prefix="$executable"
		text="${text:${#executable}}"
		directory="$BUILDROOT_HOST_DIR/"
		if xbegins_with "$executable" "$directory"; then
			prefix="\$BUILDROOT_HOST/${prefix:${#directory}}"
		fi
		xerror "Failed to execute: $(xexecutable_plain "$prefix")$GRAY$text"
		#xexestat "Exec" "$EXEC_STDOUT" "$EXEC_STDERR" "$EXEC_STATUS"
		message=$(xsuggest_to_install_message "$executable")
		if xis_set "$message"; then
			xdebug "$EXEC_STDERR"
			xdebug "$EXEC_STDOUT"
			xerror "$message"
		else
			xtext "$RED" "$EXEC_STDERR"
			xtext "$RED" "$EXEC_STDOUT"
		fi
		xerror "Terminating with status $(xexec_status "$EXEC_STATUS")"
		xterminate "$EXEC_STATUS"
	elif xis_true "false"; then
		if xis_set "$EXEC_STDOUT"; then
			xdebug "EXEC_STDOUT: $EXEC_STDOUT"
		fi
		if xis_set "$EXEC_STDERR"; then
			xdebug "EXEC_STDERR: $EXEC_STDERR"
		fi
	fi
}

function xexec_status() {
	local message=""
	case "$EXEC_STATUS" in
	"0") message="successfully completed" ;;
	"1" | "255") message="generic operation fault" ;;
	"2") message="invalid options or missing arguments" ;;
	"4" | "124") message="operation is timed out" ;;
	"125") message="out of memory" ;;
	"126") message="command cannot execute" ;;
	"127") message="command not found" ;;
	"128") message="invalid argument" ;;
	"130") message="terminated by Ctrl-C" ;;
	esac
	if xis_set "$message"; then
		echo "$BLUE$EXEC_STATUS$NC: $message"
	else
		echo "$BLUE$EXEC_STATUS$NC"
	fi
}

function xexit() {
	xdebug "Finishing wrapper with STDOUT, STDERR & STATUS=$(xexec_status "$EXEC_STATUS")"
	if xis_set "$EXEC_STDOUT"; then
		echo "$EXEC_STDOUT"
	fi
	if xis_set "$EXEC_STDERR"; then
		echo "$EXEC_STDERR" 1>&2
	fi
	if xis_unset "$EXEC_STATUS"; then
		xfatal "Missing EXEC_STATUS to exit"
	fi
	xterminate "$EXEC_STATUS"
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

P_CONFIG_HASH_INITIAL=(
	"$PWD"
	"$(find -L "./.vscode/scripts" -type f -printf "%p %TY-%Tm-%Td %TH:%TM:%TS %Tz\n")"
	"$(find -L "./.vscode" -maxdepth 1 -type f -printf "%p %TY-%Tm-%Td %TH:%TM:%TS %Tz\n")"
)

P_CONFIG_HASH=$(md5sum <<<"${P_CONFIG_HASH_INITIAL[*]}")
P_CONFIG_HASH="${P_CONFIG_HASH:0:32}"

function xhash_text() {
	local string_hash
	string_hash=$(md5sum <<<"$1$P_CONFIG_HASH")
	string_hash="${string_hash:0:32}"
	echo "$string_hash"
}

function xhash_file() {
	local file_hash
	file_hash=$(md5sum "$1")
	file_hash="${file_hash:0:32}"
	echo "$file_hash-$P_CONFIG_HASH"
}

function xcache_put() {
	echo "$2" >"$P_CACHEDB_DIR/$1"
}

function xcache_get() {
	cat "$P_CACHEDB_DIR/$1" 2>/dev/null
}

P_TTY_DEBUG=false
P_TTY_SHELL_OUT=""
P_RESOLVE_REASON=""

function xtty_debug() {
	if xis_true "$P_TTY_DEBUG"; then
		xdebug "TTY: $*"
	fi
}

function xtty_resolve_port() {
	if xis_unset "$TTY_USER"; then
		TTY_USER="$TARGET_USER"
	fi
	if xis_unset "$TTY_PASS"; then
		TTY_PASS="$TARGET_PASS"
	fi
	if xis_unset "$TTY_PORT" || xis_eq "$TTY_PORT" "auto"; then
		TTY_PORT="$(find /dev -name "ttyUSB*" -print -quit)"
		if [[ "$TTY_PORT" == "" ]]; then
			xfatal "Unable to find USB TTY port"
		fi
		xtty_debug "resolved port: $TTY_PORT"
	fi
	xecho "Resolving device IP from TTY $(xdecorate "$TTY_PORT") ($P_RESOLVE_REASON)..."
	if xis_true "$TTY_DIRECT"; then
		xexec stty -F "$TTY_PORT" raw -echo "$TTY_SPEED"
	fi
}

function xtty_shell() {
	local format="" text
	for ((i = 0; i < $#; i++)); do
		format="$format%s\r"
	done
	xtty_debug "form: -->$format<--"
	# shellcheck disable=SC2059
	text="$(printf "$format\r" "$@")"
	if xis_true "$TTY_DIRECT"; then
		echo "$text" >"$TTY_PORT"
		local seconds=$(("$TTY_DELAY" / 1000)) milliseconds=$(("$TTY_DELAY" % 1000))
		EXEC_STDOUT=$(timeout "$(printf "%d.%03d" $seconds $milliseconds)" cat "$TTY_PORT")
	else
		xexec "$TTY_PICOCOM" -qrb "$TTY_SPEED" -x "$TTY_DELAY" "$TTY_PORT" -t "$text" 2>&1
	fi
	xtty_debug "send: -->$text<--"
	xtty_debug "recv: -->$EXEC_STDOUT<--"
	P_TTY_SHELL_OUT="$EXEC_STDOUT"
}

function xtty_exchange() {
	xtty_shell "$1"
	[[ "$P_TTY_SHELL_OUT" == *"$2"* ]]
}

function xtty_logout() {
	xtty_exchange "" "#"
	if xis_succeeded; then
		xtty_exchange "exit" "exit not allowed"
		if xis_succeeded; then
			xtty_debug "Booting u-boot"
			xtty_shell "boot"
		else
			xtty_debug "Logging out"
			xtty_shell ""
		fi
	fi
}

function xtty_try_login() {
	xtty_shell ""
	case "$P_TTY_SHELL_OUT" in
	*"login:"*)
		xtty_debug "got login prompt"
		if xtty_exchange "$TTY_USER" "Password:"; then
			xtty_debug "got password prompt"
			xtty_exchange "$TTY_PASS" "#"
			return 0
		fi
		;;
	*"#"*)
		xtty_debug "got command prompt #: '$P_TTY_SHELL_OUT'"
		return 0
		;;
	*"=>"*)
		xfatal "Device on $(xdecorate "$TTY_PORT") is in U-Boot command prompt mode. Please boot up and continue."
		;;
	*) return 1 ;;
	esac
	return 1
}

function xtty_login() {
	xtty_try_login
	if xis_succeeded; then
		return 0
	fi
	xtty_logout
	xtty_try_login
	if xis_succeeded; then
		return 0
	fi
	return 1
}

function xtty_peek_ip() {
	local output_ip="$1" try_login="$2"
	if xis_true "$try_login"; then
		xtty_login
		if xis_failed; then
			if xis_set "$P_TTY_SHELL_OUT"; then
				eval "$output_ip='failed to login to device'"
			else
				eval "$output_ip='no response from device'"
			fi
			return 1
		fi
	fi
	local oldifs text lines=() line match have_eth=false
	${IFS+"false"} && unset oldifs || oldifs="$IFS"
	xtty_shell "ifconfig"
	# shellcheck disable=SC2206
	IFS=$'\r' lines=($P_TTY_SHELL_OUT)
	${oldifs+"false"} && unset IFS || IFS="$oldifs"
	for line in "${lines[@]}"; do
		match=$(echo "$line" | grep 'Link encap:Ethernet')
		if xis_set "$match"; then
			have_eth=true
		fi
		match=$(echo "$line" | grep 'inet addr:' | grep 'Bcast:' |
			grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | awk 'NR==1{print $1}')
		if [[ "$match" != "" ]]; then
			xtty_debug "got IP address: $match"
			eval "$output_ip='$match'"
			return 0
		fi
	done
	if xis_unset "$P_TTY_SHELL_OUT"; then
		eval "$output_ip='no response from device'"
	elif xis_true "$have_eth"; then
		eval "$output_ip='device have no IP address'"
	else
		eval "$output_ip='no response from ifconfig'"
	fi
	return 1
}

function xtty_resolve_ip() {
	local output_ip="$1" retries="$2" try_login=false
	if [[ "$retries" == "" ]] || [[ "$retries" -le "0" ]]; then
		retries="10"
	fi
	xtty_resolve_port
	if xis_failed; then
		return 1
	fi
	while [[ "$retries" -gt "0" ]]; do
		eval "$output_ip=''"
		xtty_peek_ip "$output_ip" "$try_login"
		if xis_succeeded; then
			return 0
		fi
		sleep 1.0
		P_TTY_DEBUG=true
		try_login=true
		retries=$((retries - 1))
	done
	return 1
}

P_VSCODE_CONFIG_PATH="$P_TEMP_DIR/config-vscode.ini"

function xdiscard_target_config() {
	rm "$P_VSCODE_CONFIG_PATH"
}

function xresolve_target_config() {
	TARGET_HOSTNAME="$TARGET_IPADDR"
	TARGET_MACADDR=""
	local config_hash force="$1"
	P_RESOLVE_REASON=""
	if xis_true "$force"; then
		P_RESOLVE_REASON="forced by rebuild"
	elif ! xis_file_exists "$P_VSCODE_CONFIG_PATH"; then
		P_RESOLVE_REASON="new configuration"
	else
		function load_config_hash() {
			CONFIG_HASH=""
			# shellcheck disable=SC1090
			source "$P_VSCODE_CONFIG_PATH"
			echo "$CONFIG_HASH"
		}
		config_hash="$(load_config_hash)"
		if xis_ne "$config_hash" "$P_CONFIG_HASH"; then
			P_RESOLVE_REASON="configuration changed"
		fi
	fi
	if xis_set "$P_RESOLVE_REASON"; then
		xdebug "Creating target config for '$TARGET_IPADDR' in $P_VSCODE_CONFIG_PATH, reason: $P_RESOLVE_REASON"
		xclean_directories "$P_CACHEDB_DIR" "$P_UPLOAD_DIR" "$P_SCRIPTS_DIR"
		if xhas_prefix "$TARGET_IPADDR" "/dev/"; then
			TTY_PORT="$TARGET_IPADDR"
		fi
		if xis_eq "$TARGET_IPADDR" "tty"; then
			local target_ip=""
			xtty_resolve_ip "target_ip" "$TTY_RETRY"
			if xis_failed; then
				if xis_set "$target_ip"; then
					xfatal "Unable to get IP from TTY $(xdecorate "$TTY_PORT"): $target_ip"
				else
					xfatal "Unable to get IP from TTY $(xdecorate "$TTY_PORT")"
				fi
			fi
			TARGET_IPADDR="$target_ip"
		elif ! xis_ipv4_addr "$TARGET_IPADDR"; then
			local found=false mac_addr
			if xhas_prefix "$TARGET_IPADDR" "ASSET-"; then
				# Not implemented because of missing Jira login/password credentials.
				xfatal "Failed to resolve asset addrress for $(xdecorate "$TARGET_IPADDR"): Not implemented."
			fi
			if xis_mac_addr "$TARGET_IPADDR"; then
				mac_addr="$(xto_lowercase "$TARGET_IPADDR")"
				function resolve_ip_from_mac_addr() {
					xexec "$P_CANFAIL" ip neighbor "|" grep -i "$mac_addr" "|" \
						awk "'{ print \$1 ; exit }'"
					if xis_eq "$EXEC_STATUS" "0" && xis_ipv4_addr "$EXEC_STDOUT"; then
						TARGET_IPADDR="$EXEC_STDOUT"
						TARGET_HOSTNAME="$EXEC_STDOUT"
						TARGET_MACADDR="$mac_addr"
						found=true
					fi
				}
				function refresh_arg_cache_table() {
					local network filter="inet (addr:)?([0-9]+\\.){3}[0-9]+"
					for network in $(ifconfig | grep -oE "$filter" | awk "{print \$2}"); do
						if xis_ne "$network" "127.0.0.1"; then
							xexec "$P_CANFAIL" nmap -sP "$network"
						fi
					done
				}
				resolve_ip_from_mac_addr
				if xis_false "$found"; then
					refresh_arg_cache_table
					resolve_ip_from_mac_addr
				fi
			else
				local hostnames=("$TARGET_IPADDR.$TARGET_DOMAIN" "$TARGET_IPADDR")
				for hostname in "${hostnames[@]}"; do
					xexec "$P_CANFAIL" getent hosts "$hostname" "|" awk "'{ print \$1 ; exit }'"
					if xis_eq "$EXEC_STATUS" "0" && xis_ipv4_addr "$EXEC_STDOUT"; then
						TARGET_IPADDR="$EXEC_STDOUT"
						TARGET_HOSTNAME="$hostname"
						found=true
						break
					fi
				done
			fi
			if xis_false "$found"; then
				xfatal "Unable resolve IP for target MAC '$TARGET_IPADDR'."
			fi
		fi
		xssh "$P_CANFAIL" "uname -m"
		local target_mach="$EXEC_STDOUT" target_stderr="$EXEC_STDERR"
		if xis_ne "$EXEC_STATUS" "0"; then
			xexec "$P_CANFAIL" timeout 1 ping -c 1 "$TARGET_IPADDR"
			if xis_set "$target_stderr"; then
				xerror "$target_stderr"
			fi
			if xis_ne "$EXEC_STATUS" "0"; then
				xfatal "Target IP address $(xdecorate "$TARGET_IPADDR") is not accessible (no ping, status $(xexec_status "$EXEC_STATUS"))"
			else
				xfatal "Failed to resolve machine type for $(xdecorate "$TARGET_IPADDR")"
			fi
		fi
		if xis_ne "$P_TARGET_PLATFORM" "$target_mach"; then
			xerror "Unexpected target $(xhyperlink "http://$TARGET_IPADDR") architecture $(xdecorate "$target_mach"), expected $(xdecorate "$P_TARGET_PLATFORM")"
			xerror "Probably invalid values in $(xdecorate TARGET_ARCH) and $(xdecorate BUILDROOT_DIR) variables"
			xfatal "Check contents of the $(xhyperlink "file://./.vscode/config-user.ini") or $(xhyperlink "file://./.vscode/config.ini")"
		fi
		function resolve_binary() {
			local enable_option="$1" binary_name="$2" target_path="$3"
			if xis_false "${!enable_option}"; then
				return 0
			fi
			local missing=()
			if ! xis_executable "$binary_name"; then
				xsuggest_to_install "$binary_name"
				missing+=("host system")
			fi
			if xis_set "$target_path"; then
				local command="$binary_name --version &>/dev/null" text
				local status="/var/tmp/goflame-$binary_name.status"
				xssh "$P_CANFAIL" "$command && echo $? >$status && cat $status && rm $status"
				if xis_ne "$EXEC_STDOUT" "0"; then
					if xis_unset "${missing[*]}"; then
						local source="./.vscode/scripts/overlay/$binary_name-$P_TARGET_PLATFORM" target="$target_path/$binary_name"
						if xis_file_exists "$source"; then
							xecho "Installing $(xdecorate "$binary_name-$P_TARGET_PLATFORM") to target path $(xdecorate "$target")..."
							xscp "$source" ":$target"
						fi
					fi
					xssh "$P_CANFAIL" "$command && echo $? >$status && cat $status && rm $status"
					if xis_ne "$EXEC_STDOUT" "0"; then
						missing+=("target device")
					fi
				fi
				xdebug "Resolved $binary_name method status: $(xexec_status "$EXEC_STDOUT")"
			fi
			if xis_set "${missing[*]}"; then
				xwarn "Disabling $enable_option: $(xdecorate "$binary_name") is not installed on the $(xjoin_strings " and " "${missing[@]}")."
				export "$enable_option"="false"
			fi
		}
		resolve_binary "USE_RSYNC_METHOD" "$USE_RSYNC_BINARY" "/usr/bin"
		resolve_binary "USE_PIGZ_COMPRESSION" "$USE_PIGZ_BINARY" ""
		# prepare runtime scripts
		local exec_args=" \n"
		for item in "${TARGET_EXEC_ARGS[@]}"; do
			exec_args="$exec_args\t\"$item\"\n"
		done
		local supress=" \n"
		for item in "${TARGET_SUPRESS_MSSGS[@]}"; do
			supress="$supress\t\"$item\"\n"
		done
		xexec cp "$PWD/.vscode/scripts/dlv-loop.sh" "$P_SCRIPTS_DIR/dlv-loop.sh"
		xexec cp "$PWD/.vscode/scripts/dlv-exec.sh" "$P_SCRIPTS_DIR/dlv-exec.sh"
		xsed_replace "__TARGET_IPPORT__" "$TARGET_IPPORT" "$P_SCRIPTS_DIR/dlv-loop.sh"
		xsed_replace "__TARGET_BINARY_PATH__" "$TARGET_BIN_DESTIN" "$P_SCRIPTS_DIR/dlv-exec.sh"
		xsed_replace "__TARGET_BINARY_ARGS__" "${exec_args:1}" "$P_SCRIPTS_DIR/dlv-exec.sh"
		xsed_replace "__TARGET_SUPRESS_MSSGS__" "${supress:1}" "$P_SCRIPTS_DIR/dlv-loop.sh" "$P_SCRIPTS_DIR/dlv-exec.sh"
		cat <<EOF >"$P_VSCODE_CONFIG_PATH"
# Machine generated file. Do not modify.
# Variables TARGET_IPADDR and TARGET_IPPORT shold not be quoted.
TARGET_IPADDR=$TARGET_IPADDR
TARGET_IPPORT=$TARGET_IPPORT
TARGET_HOSTNAME="$TARGET_HOSTNAME"
TARGET_MACADDR="$TARGET_MACADDR"
TARGET_USER="$TARGET_USER"
TARGET_PASS="$TARGET_PASS"
TARGET_TTYPORT="$TTY_PORT"
USE_RSYNC_METHOD="$USE_RSYNC_METHOD"
USE_PIGZ_COMPRESSION="$USE_PIGZ_COMPRESSION"
CONFIG_HASH="$P_CONFIG_HASH"
EOF
	fi
	# shellcheck disable=SC1090
	source "$P_VSCODE_CONFIG_PATH"
	TARGET_HYPERLINK="$(xhyperlink "http://$TARGET_HOSTNAME")"
	if xis_ne "$TARGET_TTYPORT" ""; then
		TARGET_HYPERLINK="$(xhyperlink "http://$TARGET_IPADDR") (TTY $(xdecorate "$TARGET_TTYPORT"))"
	elif xis_ne "$TARGET_HOSTNAME" "$TARGET_IPADDR"; then
		TARGET_HYPERLINK="$TARGET_HYPERLINK (IP $TARGET_IPADDR)"
	elif xis_ne "$TARGET_MACADDR" ""; then
		TARGET_HYPERLINK="$TARGET_HYPERLINK (MAC $TARGET_MACADDR)"
	fi
}

function xrm() {
	local files=""
	for file in "$@"; do
		if xis_file_exists "$file"; then
			xdebug "Deleting '$file'"
			files="$files \"$file\""

		fi
	done
	if xis_set "$files"; then
		xexec rm -rf "$files"
	fi
}

function xcp() {
	xdebug "Copying $1 -> $2"
	cp -f "$1" "$2"
}

function xssh() {
	#xdebug "Target exec: $*"
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
	local host_args="$P_SSH_HOST_STDIO$P_SSH_HOST_POST"
	local target_pref="$P_SSH_TARGET_PREF$P_SSH_TARGET_STDIO"
	local target_args="$target_pref$P_SSH_TARGET_POST"
	if xis_set "$host_args" || xis_set "$target_args"; then
		local ssh_prefix="${P_SSH_HOST_STDIO}sshpass -p \"$TARGET_PASS\""
		local ssh_prefix="$ssh_prefix ssh ${SSH_FLAGS[*]} $TARGET_USER@$TARGET_IPADDR"
		if xis_true $USE_RSYNC_METHOD; then
			if xis_set "$target_pref"; then
				xexec "$ssh_prefix \"$target_pref\""
			fi
			xexec $USE_RSYNC_BINARY -azzPL --no-owner --no-group --no-perms \
				--inplace --partial --numeric-ids --stats --progress \
				-e "\"sshpass -p \"$TARGET_PASS\" ssh ${SSH_FLAGS[*]}\"" \
				"\"$P_UPLOAD_DIR/\"" "\"$TARGET_USER@$TARGET_IPADDR:/\""
			#xdebug "$EXEC_STDERR"
			#xdebug "$EXEC_STDOUT"
			if xis_set "$P_SSH_TARGET_POST"; then
				xexec "$ssh_prefix \"$P_SSH_TARGET_POST\""
			fi
		else
			if xis_set "$target_args"; then
				xexec "$ssh_prefix \"$target_args\""
			fi
		fi
		xexec "$P_SSH_HOST_POST"
	fi
	P_SSH_HOST_STDIO=""
	P_SSH_HOST_POST=""
	P_SSH_TARGET_STDIO=""
	P_SSH_TARGET_PREF=""
	P_SSH_TARGET_POST=""
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

	if xis_true "$frebuild" && xis_true "$REBUILD_FORCE_LINTERS"; then
		GOLANGCI_LINT_FILTER=true
		STATICCHECK_ENABLE=true
		GO_VET_ENABLE=true
		LLENCHECK_ENABLE=true
		PRECOMMIT_ENABLE=true
	fi

	xresolve_target_config "$frebuild"
	xecho "$* to $P_TARGET_PLATFORM host $TARGET_HYPERLINK"
	if xis_true "$fbuild" || xis_true "$frebuild"; then
		xbuild_project
	else
		xcheck_project
	fi

	if xis_false "$fdebug" && xis_true "$fexec"; then
		P_SSH_TARGET_PREF="rm -f \"$DLOOP_RESTART_FILE\"; $P_SSH_TARGET_PREF"
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
	xexecute_target_commands
	xservices_start
	xprocesses_start

	if xis_false "$fexec" && xis_false "$fdebug"; then
		P_SSH_TARGET_PREF="${P_SSH_TARGET_PREF}rm -f \"$DLOOP_ENABLE_FILE\"; "
		xexecute_target_commands_vargs "@echo 1 > $DLOOP_ENABLE_FILE"
	fi

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
		P_SSH_TARGET_PREF="${P_SSH_TARGET_PREF}pkill \"$procname\"; "
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
		one="$dir$one"
	elif [[ ! "$one" =~ ^\/.* ]]; then
		one="./$one"
	fi

	local two="$2"
	if [[ "$two" =~ ^\:.* ]]; then
		two="$dir$two"
	elif [[ ! "$two" =~ ^\/.* ]]; then
		two="./$two"
	fi

	xdebug "Target copy: $canfail $one -> $two"
	xexec "$canfail" sshpass -p "$TARGET_PASS" scp -C "${SCP_FLAGS[@]}" "$one" "$two"
}

function xfiles_delete() {
	# Delete files from DELETE_FILES
	xfiles_delete_vargs "${DELETE_FILES[@]}"
}

# shellcheck disable=SC2120
function xfiles_delete_vargs() {
	if xis_ne "$#" "0"; then
		P_SSH_TARGET_PREF="${P_SSH_TARGET_PREF}rm -f $(printf "'%s' " "$@"); "
		xecho "Removing $# files: $(xjoin_elements true "$@")"
	fi
}

function xclean_directories() {
	local clean=() create=()
	for path in "$@"; do
		create+=("$path")
		if xis_dir_exists "$path"; then
			clean+=("$path/*")
		fi
	done
	if xis_ne "${#clean[@]}" "0"; then
		xexec rm -rf "${clean[@]}"
	fi
	if xis_ne "${#create[@]}" "0"; then
		xexec mkdir -p "${create[@]}"
	fi
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
	if xis_eq "${#list[@]}" "0"; then
		return 0
	fi

	local uploading=false uploads=() skipped=() directories=() symlinks=""
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
			uploading=true
			local prefA="${fileA:0:1}"
			if xis_eq "$prefA" "?"; then
				fileA="${fileA:1}"
			fi
			if xis_file_exists "$PWD/$fileA"; then
				fileA="$PWD/$fileA"
			elif xis_file_exists "$fileA"; then
				:
			elif xis_eq "$prefA" "?"; then
				skipped+=("$fileA")
				continue
			else
				xerror "Unable to find \"$fileA\" for upload"
				exit "1"
			fi

			local name_hash file_hash
			name_hash=$(xhash_text "$fileA")
			file_hash=$(xhash_file "$fileA")
			#xecho "$name_hash :: $file_hash"

			if xis_false "$COPY_CACHE" || xis_ne "$(xcache_get "$name_hash")" "$file_hash"; then
				if xis_eq "${#directories[@]}" "0"; then
					directories+=("$P_UPLOAD_DIR")
				fi
				local backup_target="$P_UPLOAD_DIR/${fileB:1}"
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
			uploads+=("$fileB")
		fi
	done
	xclean_directories "${directories[@]}"
	if xis_ne "$symlinks" ""; then
		xexec "$symlinks"
	fi
	if xis_true "$uploading"; then
		if xis_ne "${#skipped[@]}" "0"; then
			xwarn "Skipping ${#skipped[@]} files: $(xjoin_elements false "${skipped[@]}")"
		fi
		if xis_ne "${#uploads[@]}" "0"; then
			local upload_method="unknown"
			if xis_false $USE_RSYNC_METHOD; then
				local pkg="gzip -5 --no-name"
				upload_method="ssh+gzip"
				if xis_true "$USE_PIGZ_COMPRESSION"; then
					pkg="$USE_PIGZ_BINARY --processes $(nproc) -9 --no-time --no-name"
					upload_method="ssh+$USE_PIGZ_BINARY"
				fi
				P_SSH_HOST_STDIO="tar -cf - -C \"$P_UPLOAD_DIR\" --dereference \".\" | $pkg - | "
				P_SSH_TARGET_STDIO="gzip -dc | tar --no-same-owner --no-same-permissions -xf - -C \"/\"; "
			else
				upload_method="$USE_RSYNC_BINARY"
			fi
			xecho "Uploading ${#uploads[@]} files via $upload_method: $(xjoin_elements true "${uploads[@]}")"
		fi
	else
		xecho "Downloading ${#uploads[@]} files: $(xjoin_elements true "${uploads[@]}")"
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
}

function xservices_stop() {
	# Stop services from SERVICES_STOP
	xservices_stop_vargs "${SERVICES_STOP[@]}"
}

# shellcheck disable=SC2120
function xservices_stop_vargs() {
	if xis_ne "$#" "0"; then
		for service in "$@"; do
			if xis_true "$USE_SERVICE_MASKS"; then
				P_SSH_TARGET_PREF="${P_SSH_TARGET_PREF}systemctl mask \"$service\"; "
			fi
			P_SSH_TARGET_PREF="${P_SSH_TARGET_PREF}systemctl stop \"$service\"; "
		done
		xecho "Stopping $# services: $(xjoin_elements true "$@")"
	fi
}

function xservices_start() {
	# Start services from SERVICES_START
	xservices_start_vargs "${SERVICES_START[@]}"
}

# shellcheck disable=SC2120
function xservices_start_vargs() {
	if xis_ne "$#" "0"; then
		for service in "$@"; do
			if xis_true "$USE_SERVICE_MASKS"; then
				P_SSH_TARGET_POST="${P_SSH_TARGET_POST}systemctl unmask \"$service\"; "
			fi
			P_SSH_TARGET_POST="${P_SSH_TARGET_POST}systemctl start \"$service\"; "
		done
		xecho "Starting $# services: $(xjoin_elements true "$@")"
	fi
}

function xprocesses_stop() {
	# Stop processes from PROCESSES_STOP
	xprocesses_stop_vargs "${PROCESSES_STOP[@]}"
}

# shellcheck disable=SC2120
function xprocesses_stop_vargs() {
	if xis_ne "$#" "0"; then
		for procname in "$@"; do
			P_SSH_TARGET_PREF="${P_SSH_TARGET_PREF}pkill \"$procname\"; "
		done
		xecho "Terminating $# processes: $(xjoin_elements true "$@")"
	fi
}

function xprocesses_start() {
	# Start processes from PROCESSES_START
	xprocesses_start_vargs "${PROCESSES_START[@]}"
}

# shellcheck disable=SC2120
function xprocesses_start_vargs() {
	if xis_ne "$#" "0"; then
		for procname in "$@"; do
			P_SSH_TARGET_POST="$P_SSH_TARGET_POST$procname; "
		done
		xecho "Starting $# processes: $(xjoin_elements true "$@")"
	fi
}

function xcreate_directories() {
	# Create directories from DIRECTORIES_CREATE
	xcreate_directories_vargs "${DIRECTORIES_CREATE[@]}"
}

# shellcheck disable=SC2120
function xcreate_directories_vargs() {
	if xis_ne "$#" "0"; then
		for dirname in "$@"; do
			P_SSH_TARGET_POST="${P_SSH_TARGET_POST}mkdir -p \"$dirname\"; "
		done
		xecho "Creating $# directories: $(xjoin_elements false "$@")"
	fi
}

function xexecute_target_commands() {
	# Create directories from DIRECTORIES_CREATE
	xexecute_target_commands_vargs "${EXECUTE_COMMANDS[@]}"
}

# shellcheck disable=SC2120
function xexecute_target_commands_vargs() {
	if xis_ne "$#" "0"; then
		local commands=()
		for command in "$@"; do
			if xis_eq "${command:0:1}" "@"; then
				command="${command:1}"
			else
				commands+=("${command%% *}")
			fi
			P_SSH_TARGET_POST="$P_SSH_TARGET_POST$command; "
		done
		if xis_ne "${#commands[@]}" "0"; then
			xecho "Executing ${#commands[@]} target commands: $(xjoin_elements false "${commands[@]}")"
		fi
	fi
}

P_GOCACHE_CLEANED=false

function xclean_gocache() {
	if xis_false "$CLEAN_GOCACHE" || xis_true "$P_GOCACHE_CLEANED"; then
		return 0
	fi
	P_GOCACHE_CLEANED=true
	xecho "Cleaning Go compiler & linters cache..."
	xclean_directories "$EXPORT_GOCACHE" "$HOME/.cache/go-build"
	xexec go clean -cache
	if xis_true "$GOLANGCI_LINT_ENABLE"; then
		xexec "$LOCAL_GOLANGCI_LINT" cache clean
	fi
}

function xtest_installed() {
	local enable_key="$1"
	local binary="$2"
	local instructions="$3"
	if ! xis_file_exists "$binary"; then
		xerror "Reqired binary $(xexecutable "$(basename -- "$binary")") is not installed."
		xerror "To disable this feature set $enable_key=false in 'config-user.ini'."
		xfatal "Check installation instructions: $(xhyperlink "$instructions")"
	fi
}

P_GOLANGCI_LINT_DONE=false
P_STATICCHECK_DONE=false
P_GO_VET_DONE=false
P_LLENCHECK_DONE=false
P_PRECOMMIT_DONE=false

function xreset_lint_state() {
	P_GOLANGCI_LINT_DONE=false
	P_STATICCHECK_DONE=false
	P_GO_VET_DONE=false
	P_LLENCHECK_DONE=false
	P_PRECOMMIT_DONE=false
}

function xload_lint_state() {
	local state=()
	IFS=' ' read -r -a state <<<"$(cat "$P_CACHEDB_DIR/__linters_result.state" 2>/dev/null)"
	if xis_eq "${#state[@]}" "5"; then
		P_GOLANGCI_LINT_DONE="${state[0]}"
		P_STATICCHECK_DONE="${state[1]}"
		P_GO_VET_DONE="${state[2]}"
		P_LLENCHECK_DONE="${state[3]}"
		P_PRECOMMIT_DONE="${state[4]}"
	else
		xreset_lint_state
	fi
}

function xsave_lint_state() {
	if xis_eq "$name_hash" ""; then
		return
	fi
	xcache_put "$name_hash" "$file_hash"
	local items=(
		"P_GOLANGCI_LINT_DONE"
		"P_STATICCHECK_DONE"
		"P_GO_VET_DONE"
		"P_LLENCHECK_DONE"
		"P_PRECOMMIT_DONE"
	)
	for item in "${items[@]}"; do
		if xis_file_exists "$P_CACHEDB_DIR/__res_$item"; then
			eval "$item"=true
		fi
	done
	local state=(
		"$P_GOLANGCI_LINT_DONE"
		"$P_STATICCHECK_DONE"
		"$P_GO_VET_DONE"
		"$P_LLENCHECK_DONE"
		"$P_PRECOMMIT_DONE"
	)
	echo "${state[@]}" >"$P_CACHEDB_DIR/__linters_result.state"
}

function xcheck_results() {
	if xis_ne "$EXEC_STATUS" "0"; then
		xtext "$RED" "$EXEC_STDOUT"
		xtext "$RED" "$EXEC_STDERR"
		eval "$1"=false
		if xis_true "$2"; then
			xerror "$3 warnings has been detected. Fix before continue (status $(xexec_status "$EXEC_STATUS"))."
			xsave_lint_state
			exit "$EXEC_STATUS"
		fi
	else
		xtext "" "$EXEC_STDOUT"
		xtext "" "$EXEC_STDERR"
		eval "$1"=true
		xexec "echo true >\"$P_CACHEDB_DIR/__res_$1\" 2>&1"
	fi
}

function xcheck_project() {
	local name_hash="" file_hash="" dir_hash="$P_CACHEDB_DIR/__project_checklist.log"
	local diff_filter_args=() diff_filter_command=""
	if xis_true "$GOLANGCI_LINT_ENABLE" || xis_true "$STATICCHECK_ENABLE" ||
		xis_true "$GO_VET_ENABLE" || xis_true "$LLENCHECK_ENABLE" ||
		xis_true "$PRECOMMIT_ENABLE"; then
		xexec find -L "." -type f "\(" -iname "\"*\"" ! -iname "\"$TARGET_BIN_SOURCE\"" "\)" \
			-not -path "\"./.git/*\"" -exec date -r {} \
			"\"+%m-%d-%Y %H:%M:%S\"" "\;" ">" "$dir_hash"
		xload_lint_state
		name_hash=$(xhash_text "$dir_hash")
		file_hash=$(xhash_file "$dir_hash")
		#xecho "$name_hash :: $file_hash"
		if xis_ne "$(xcache_get "$name_hash")" "$file_hash" || xis_true "$CLEAN_GOCACHE"; then
			xreset_lint_state
		fi
		if xis_true "$P_GOLANGCI_LINT_DONE" &&
			xis_true "$P_STATICCHECK_DONE" &&
			xis_true "$P_GO_VET_DONE" &&
			xis_true "$P_LLENCHECK_DONE" &&
			xis_true "$P_PRECOMMIT_DONE"; then
			return 0
		fi
		xexec rm -f "$P_CACHEDB_DIR/__res_P_GOLANGCI_LINT_DONE" \
			"$P_CACHEDB_DIR/__res_P_STATICCHECK_DONE" \
			"$P_CACHEDB_DIR/__res_P_GO_VET_DONE" \
			"$P_CACHEDB_DIR/__res_P_LLENCHECK_DONE" \
			"$P_CACHEDB_DIR/__res_P_PRECOMMIT_DONE"
		export PYTHONPYCACHEPREFIX="$P_TEMP_DIR/pycache"
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
	function run_golangci_lint() {
		if xis_true "$GOLANGCI_LINT_ENABLE" && xis_false "$P_GOLANGCI_LINT_DONE"; then
			xtest_installed "GOLANGCI_LINT_ENABLE" "$LOCAL_GOLANGCI_LINT" "https://golangci-lint.run/usage/install/"
			local linter_args=("${GOLANGCI_LINT_ARGUMENTS[@]}") linters_list=()
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
				#linter_args+=("--enable-all")
				#for linter in "${disabled_list[@]}"; do
				#	linter_args+=("-D" "$linter")
				#done
				xexec "$LOCAL_GOLANGCI_LINT" "help" "linters"
				local known_linters=() enabled_list=()
				readarray -t known_linters <<<"$EXEC_STDOUT"
				for linter_desc in "${known_linters[@]}"; do
					IFS=':'
					# shellcheck disable=SC2206
					linter_desc=($linter_desc)
					unset IFS
					if xis_eq "${#linter_desc[@]}" "0"; then
						continue
					fi
					linter=${linter_desc[0]}
					if xis_eq "$linter" "Enabled by default linters" ||
						xis_eq "$linter" "Disabled by default linters"; then
						continue
					fi
					if xis_eq "$linter" "Linters presets"; then
						break
					fi
					IFS=' '
					# shellcheck disable=SC2206
					linter_desc=($linter)
					unset IFS
					if xis_eq "${#linter_desc[@]}" "0"; then
						continue
					fi
					if xis_eq "${#linter_desc[@]}" "2" &&
						xis_eq "${linter_desc[1]}" "[deprecated]"; then
						continue
					fi
					linter="${linter_desc[0]}"
					enabled_list+=("$linter")
					#xecho "++$linter ${#linter_desc[@]} ${linter_desc[*]}"
					if ! xcontains "$linter" "${disabled_list[@]}"; then
						linter_args+=("-E" "$linter")
					fi
				done
				xsort_unique enabled_list "${enabled_list[@]}"
				for linter in "${enabled_list[@]}"; do
					if ! xcontains "$linter" "${disabled_list[@]}"; then
						linter_args+=("-E" "$linter")
					fi
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
			local scheck="$P_TEMP_DIR/golangci-lint.log"
			xecho "Running $(xdecorate "golangci-lint") (details: $(xhyperlink "file://$scheck"))"
			xexec "$P_CANFAIL" "$LOCAL_GOLANGCI_LINT" "run" "${linter_args[@]}" \
				"./..." ">" "$scheck" "2>&1"
			if xis_true "$GOLANGCI_LINT_FILTER"; then
				xexec "$P_CANFAIL" cat "$scheck" "|" "${diff_filter_command[@]}" -p -x -z
			else
				xexec "$P_CANFAIL" cat "$scheck" "|" "${diff_filter_command[@]}" -a -p -x -z
			fi
			xcheck_results "P_GOLANGCI_LINT_DONE" "$GOLANGCI_LINT_FAIL" "Golangci-lint"
		fi
	}
	function run_staticckeck() {
		if xis_true "$STATICCHECK_ENABLE" && xis_false "$P_STATICCHECK_DONE"; then
			xtest_installed "STATICCHECK_ENABLE" "$LOCAL_STATICCHECK" "https://staticcheck.dev/docs/"
			xexport_clean "${GOLANG_EXPORTS[@]}"
			local flags=() go_version
			go_version=$("$BUILDROOT_GOBIN" version)
			go_version=$(awk '{print $3}' <<<"$go_version")
			go_version="${go_version%.*}"
			flags+=("-go" "${go_version:2}")
			if xis_set "$STATICCHECK_CHECKS"; then
				flags+=("-checks" "$STATICCHECK_CHECKS")
			fi
			local scheck="$P_TEMP_DIR/staticcheck.log"
			xecho "Running $(xdecorate "staticcheck") (details: $(xhyperlink "file://$scheck"))"
			xexec "$P_CANFAIL" "$LOCAL_STATICCHECK" "${flags[@]}" "./..." "2>&1" ">" "$scheck"
			if xis_true "$STATICCHECK_FILTER"; then
				xexec "$P_CANFAIL" cat "$scheck" "|" "${diff_filter_command[@]}" -p -x \
					-e="\"$STATICCHECK_SUPRESS\""
			else
				xexec "$P_CANFAIL" cat "$scheck" "|" "${diff_filter_command[@]}" -a -p -x
			fi
			xcheck_results "P_STATICCHECK_DONE" "$STATICCHECK_FAIL" "Staticcheck"
		fi
	}
	function run_go_vet_check() {
		if xis_true "$GO_VET_ENABLE" && xis_false "$P_GO_VET_DONE"; then
			xecho "Running $(xdecorate "go vet") on $(xdecorate "$TARGET_BUILD_LAUNCHER")..."
			xexec "$P_CANFAIL" "$BUILDROOT_GOBIN" "vet" "${GO_VET_FLAGS[@]}" "./..."
			xcheck_results "P_GO_VET_DONE" "$GO_VET_FAIL" "Go-vet"
		fi
	}
	function run_llencheck() {
		if xis_true "$LLENCHECK_ENABLE" && xis_false "$P_LLENCHECK_DONE"; then
			local project_name
			project_name="$(basename -- "$PWD")"
			xecho "Running $(xdecorate "line-length-limit") check on $(xdecorate "$project_name")"
			if xis_true "$LLENCHECK_FILTER"; then
				xexec "$P_CANFAIL" "${diff_filter_command[@]}" \
					-l="$LLENCHECK_LIMIT" -t="$LLENCHECK_TABWIDTH" "${diff_filter_args[@]}"
			else
				xexec "$P_CANFAIL" "${diff_filter_command[@]}" \
					-a -l="$LLENCHECK_LIMIT" -t="$LLENCHECK_TABWIDTH" "${diff_filter_args[@]}"
			fi
			xcheck_results "P_LLENCHECK_DONE" "$LLENCHECK_FAIL" "Line-length-limit"
		fi
	}
	function run_precommit_check() {
		if xis_true "$PRECOMMIT_ENABLE" && xis_false "$P_PRECOMMIT_DONE"; then
			local project_name
			project_name="$(basename -- "$PWD")"
			xecho "Running $(xdecorate "pre-commit-checks") check on $(xdecorate "$project_name")"
			xexec "$P_CANFAIL" "pre-commit" "run" -a
			xcheck_results "P_PRECOMMIT_DONE" "$PRECOMMIT_FAIL" "Pre-commit-checks"
		fi
	}
	if xis_true "$USE_ASYNC_LINTERS"; then
		SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
		source "$SCRIPT_DIR/go-job-pool.sh"
		job_pool_init "$(nproc)" 0
		job_pool_run run_golangci_lint
		job_pool_run run_staticckeck
		job_pool_run run_go_vet_check
		job_pool_run run_llencheck
		job_pool_run run_precommit_check
		job_pool_wait
		job_pool_shutdown
	else
		run_golangci_lint
		run_staticckeck
		run_go_vet_check
		run_llencheck
		run_precommit_check
	fi
	xsave_lint_state
}

function xbuild_project() {
	xclean_gocache
	xcheck_project
	#xdebug "TARGET_BUILD_GOFLAGS: ${TARGET_BUILD_GOFLAGS[*]}"
	#xdebug "TARGET_BUILD_LDFLAGS: ${TARGET_BUILD_LDFLAGS[*]}"
	local flags=("build" "${TARGET_BUILD_GOFLAGS[@]}")
	if xis_ne "${#TARGET_BUILD_LDFLAGS[@]}" "0"; then
		flags+=("-ldflags \"${TARGET_BUILD_LDFLAGS[@]}\"")
	fi
	if xis_set "$TARGET_BUILD_LAUNCHER"; then
		flags+=("$TARGET_BUILD_LAUNCHER")
	fi

	xexport_apply "${GOLANG_EXPORTS[@]}"
	xexec "$BUILDROOT_GOBIN" "${flags[@]}"
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

	local features_on_set=() features_on_err=()
	for feature in "${CAMERA_FEATURES_ON[@]}"; do
		local pattern="\"$feature\": set to True"
		if grep -i -q "$pattern" <<<"$response"; then
			features_on_set+=("$feature")
		else
			features_on_err+=("$feature")
		fi
	done

	local features_off_set=() features_off_err=()
	for feature in "${CAMERA_FEATURES_OFF[@]}"; do
		local pattern="\"$feature\": set to False"
		if grep -i -q "$pattern" <<<"$response"; then
			features_off_set+=("$feature")
		else
			features_off_err+=("$feature")
		fi
	done

	local features_set=""
	if xis_ne "${#features_on_set[@]}" "0"; then
		features_set="$features_set; TRUE: $(xjoin_elements true "${features_on_set[@]}")"
	fi
	if xis_ne "${#features_off_set[@]}" "0"; then
		features_set="$features_set; FALSE: $(xjoin_elements true "${features_off_set[@]}")"
	fi

	local features_err=""
	if xis_ne "${#features_on_err[@]}" "0"; then
		features_err="$features_err; TRUE: $(xjoin_elements true "${features_on_err[@]}")"
	fi
	if xis_ne "${#features_off_err[@]}" "0"; then
		features_err="$features_err; FALSE: $(xjoin_elements true "${features_off_err[@]}")"
	fi

	if xis_set "$features_set"; then
		xecho "Camera features set to ${features_set:2}"
	fi
	if xis_set "$features_err"; then
		xwarn "Failed to set camera features to ${features_err:2}"
	fi
}

function xtruncate_text_file() {
	local name="$1"
	local limit="$2"
	local target="$3"
	if ! xis_file_exists "$name"; then
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
	COPY_FILES+=(
		"?$P_SCRIPTS_DIR/dlv-loop.sh|:/usr/bin/dl"
		"?$P_SCRIPTS_DIR/dlv-exec.sh|:/usr/bin/de"
		"?$PWD/.vscode/scripts/onvifd-install.sh|:/usr/bin/oi"
	)
}

function xistall_ssh_key() {
	if xis_false "$INSTALL_SSH_KEYS"; then
		return
	fi
	local key_a="$HOME/.ssh/goflame-key"
	local key_b="$HOME/.ssh/goflame-key.pub"
	if ! xis_file_exists "$key_a" || ! xis_file_exists "$key_b"; then
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
