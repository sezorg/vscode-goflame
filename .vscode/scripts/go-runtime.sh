#!/usr/bin/env bash
# Copyright 2025 RnD Center "ELVEES", JSC
#
# GO compiler wrapper environment
# Lookup for unnecessary complex variable references: \$\{\w+\}([^\w]|$)
#
# Log messages are stored into file:///var/tmp/goflame/go-wrapper.log

set -euo pipefail

# shellcheck disable=SC2064
trap "trap - SIGTERM && kill -- -$$ >/dev/null 2>&1" SIGINT SIGTERM EXIT

CE=$'\u1B[' # Color escape
RED="${CE}31m"
GREEN="${CE}32m"
ORANGE="${CE}33m"
BLUE="${CE}34m"
PURPLE="${CE}35m"
CIAN="${CE}36m"
LTGRAY="${CE}37m"
GRAY="${CE}90m"
BOLD="${CE}1m"
UNDERLINE="${CE}4m"
LINK="$BLUE$UNDERLINE"
PREF="$ORANGE"
NC="${CE}0m"
NCC="${CE}0m"
EP="" # echo prefix
PI="\`"
PO="'"

P_COLOR_FILTER="s/\x1B\[([0-9]{1,3}(;[0-9]{1,3})*)?[mGK]//g"
P_ELAPSED_PREFIX=""
P_ELAPSED_COLOR=""

P_EMIT_XLAT_BASE=()
P_EMIT_XLAT_FULL=()
P_EMIT_XLAT="full" # full|base|none
P_EMIT_PREFIX=""
P_IGNORE_PATTERN=""
P_DEBUG_TTY=false
P_DEBUG_GOENV=false
P_DEBUG_BUILDENV=false
P_MESSAGE_SOURCE=$(basename -- "$0")
P_MESSAGE_SOURCE="${P_MESSAGE_SOURCE%.*}"
P_TIME_STARTED="$(date +%s.%N)"
P_TIME_CON_OUT=""
P_TIME_LOG_OUT=""
P_START_CONSOLE="true" # true/false/auto/kde/konsole/gnome/gnome-terminal

P_VSCODE_DIR="$PWD/.vscode"
P_GOFLAME_DIR="/var/tmp/goflame"
P_CACHEDB_DIR="$P_GOFLAME_DIR/cachedb"
P_STATUS_DIR="$P_GOFLAME_DIR/status"
P_SCRIPTS_DIR="$P_GOFLAME_DIR/scripts"
P_UPLOAD_DIR="$P_GOFLAME_DIR/upload"
P_GO_EXEC_STUB="go-exec-stub"
P_ALWAYS_BUILD=false

P_MODE_BUILD=false
P_MODE_REBUILD=false
P_MODE_LINT=false
P_MODE_DEBUG=false
P_MODE_EXEC=false
P_MODE_TEST=false

mkdir -p "$P_GOFLAME_DIR" "$P_CACHEDB_DIR" "$P_STATUS_DIR" "$P_UPLOAD_DIR"

WRAPPER_LOGFILE="$P_GOFLAME_DIR/go-wrapper.log"
P_ECHO_ENABLED=false
P_DEBUG_ENABLED=false

TOOLCHAIN_DIR="UNKNOWN-TOOLCHAIN_DIR"
TOOLCHAIN_GOBIN="go"

EXPORT_GOROOT="UNKNOWN-GOROOT"
EXPORT_GOTOOLDIR="UNKNOWN-GOTOOLDIR"
EXPORT_GOPATH="UNKNOWN-GOPATH"
EXPORT_GOMODCACHE="UNKNOWN-GOMODCACHE"
EXPORT_GOCACHE="UNKNOWN-GOCACHE"
EXPORT_GOENV="UNKNOWN-GOENV"

DLOOP_ENABLE_FILE="/tmp/dlv-loop-enable"
DLOOP_STATUS_FILE="/tmp/dlv-loop-status"
DLOOP_RESTART_FILE="/tmp/dlv-loop-restart"

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

function xis_lt() {
	[[ "$1" -lt "$2" ]]
}

function xis_ge() {
	[[ "$1" -ge "$2" ]]
}

function xis_gt() {
	[[ "$1" -gt "$2" ]]
}

function xis_array() {
	[[ "$(declare -p "$1")" =~ "declare -a" ]]
}

function xis_function() {
	[[ -n "$(LC_ALL=C type -t "$1")" ]] && [[ "$(LC_ALL=C type -t "$1")" = "function" ]]
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

function xsed_escape() {
	printf '%s' "$*" | sed -e 's/[\/&-\"]/\\&/g'
}

function xvar() {
	local base="$1" suffix="$2" composite
	composite="${base}_$(xstring_to_uppercase "$suffix")"
	if [[ -v "$composite" ]]; then
		echo "${!composite}"
		return 0
	fi
	echo "${!base}"
	return 1
}

function xstring_to_lowercase() {
	local input_string="$1"
	echo "${input_string,,}"
}

function xstring_to_uppercase() {
	local input_string="$1"
	echo "${input_string^^}"
}

function xstring_begins_with() {
	case "$1" in
	"$2"*)
		return 0
		;;
	esac
	return 1
}

function xstring_contains() {
	case "$1" in
	*"$2"*)
		return 0
		;;
	esac
	return 1
}

function xarray_contains() {
	local value="$1" element
	shift
	for element; do
		xis_eq "$element" "$value" &&
			return 0
	done
	return 1
}

function xarray_sort_unique() {
	local output="$1"
	shift
	readarray -t "$output" < <(printf "%s\n" "$@" | sort -u)
}

function xarray_remove_duplicates() {
	local -n filtered_result="$1"
	shift
	declare -A duplicates
	filtered_result=()
	for item in "$@"; do
		if xis_eq "${duplicates["$item"]+abc}" ""; then
			filtered_result+=("$item")
		fi
		duplicates["$item"]=1
	done
	unset duplicates

}

function xarray_join {
	local delimiter=${1-} format=${2-}
	if shift 2; then
		printf "%s" "$format" "${@/#/$delimiter}"
	fi
}

function xjoin_elements() {
	local basename="$1" result=""
	shift
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

function xsplit() {
	local input="$3"
	if xis_eq "$1" $'\n'; then
		input="${input//$'\r\n'/$'\n'}"
		input="${input//$'\n\r'/$'\n'}"
	fi
	readarray -d "$1" -t "$2" < <(printf '%s' "$input")
}

function xreverse() {
	local output="$1"
	shift
	readarray -t "$output" < <(printf '%s' "${BASH_ARGV[@]}")
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

function xcolorize_strings() {
	local input="$*" open_color="$RED" open_alt="$ORANGE" close_color="$NC" color modified=false
	local index=0 count="${#input}" output="" skip_next="" close_next="" string mode=""
	while xis_lt "$index" "$count"; do
		curr="${input:$index:1}"
		case "$curr" in
		"m")
			if [[ "$output" =~ ^.*("$CE"[0-9]+)$ ]]; then
				close_color="${BASH_REMATCH[1]}m"
			fi
			;;
		"\\")
			if [[ "$mode" == "\"" ]]; then
				output+="$curr"
				index=$((index + 1))
				if xis_ge "$index" "$count"; then
					break
				fi
				curr="${input:$index:1}"
			fi
			;;
		"\"" | "'" | "\`")
			if xis_set "$mode" && xis_ne "$mode" "$curr"; then
				output+="$curr"
				index=$((index + 1))
				continue
			fi

			if xis_set "$skip_next"; then
				mode=""
				skip_next=""
			elif xis_set "$close_next"; then
				string="${output:$close_next}"
				color="$open_color"
				if xis_eq "$color" "$close_color"; then
					color="$open_alt"
				fi
				output="${output:0:$close_next}$color${string//$NC/$color}"
				curr+="$close_color"
				close_next=""
				modified=true
				mode=""
			elif [[ "$output" =~ ^.*"$CE"[0-9]+m$ ]]; then
				mode="$curr"
				skip_next="$curr"
			else
				mode="$curr"
				close_next="${#output}"
			fi
			;;
		esac
		output+="$curr"
		index=$((index + 1))
	done
	if xis_false "$modified"; then
		echo "$input"
	elif xis_ne "$close_color" "$NC"; then
		echo "$output$NC"
	else
		echo "$output"
	fi
}

function xemit_xlat() {
	local output="$1" result=() pattern="s/__IN__\\([^a-zA-Z0-9 \-_$]*.*\\)/\__OUT__\\1/"
	shift
	P_EMIT_XLAT_TAB=()
	while [[ $# -gt 0 ]]; do
		local name="$1" value="$2"
		if xis_set "$value"; then
			local value="${pattern//__IN__/$(xsed_escape "$value")}"
			P_EMIT_XLAT_TAB+=("-e" "${value//__OUT__/$BLUE\$$name$NC}")
			result+=("-e" "${value//__OUT__/$(xsed_escape "$name")}")
		fi
		shift
		shift
	done
	readarray -t "$output" < <(printf "%s\n" "${result[@]}")
}

function xemit() {
	local echo_enabled="$1"
	shift
	local time_stamp actual_time elapsed_time input="$P_EMIT_PREFIX$*"
	input="${input//$'\r'/\\r}"
	input="${input//$'\n'/\\n}"
	if xstring_contains "$input" "$HOME"; then
		if xis_eq "${#P_EMIT_XLAT_FULL[@]}" "0"; then
			local pre="$BLUE\$" out="$NC"
			xemit_xlat P_EMIT_XLAT_BASE \
				"${pre}TOOLCHAIN$out" "$TOOLCHAIN_DIR" \
				"${pre}PWD$out" "$PWD" \
				"${pre}HOME$out" "$HOME"
			xemit_xlat P_EMIT_XLAT_FULL \
				"${pre}GOTOOLDIR$out" "$EXPORT_GOTOOLDIR" \
				"${pre}GOMODCACHE$out" "$EXPORT_GOMODCACHE" \
				"${pre}GOCACHE$out" "$EXPORT_GOCACHE" \
				"${pre}GOPATH$out" "$EXPORT_GOPATH" \
				"${pre}GOENV$out" "$EXPORT_GOENV" \
				"${pre}GOROOT$out" "$EXPORT_GOROOT"
			P_EMIT_XLAT_FULL+=("${P_EMIT_XLAT_BASE[@]}")
		fi
		case "$P_EMIT_XLAT" in
		"full")
			input="$(sed "${P_EMIT_XLAT_FULL[@]}" <<<"$input")"
			;;
		"base")
			input="$(sed "${P_EMIT_XLAT_BASE[@]}" <<<"$input")"
			;;
		esac
	fi
	input="$(xcolorize_strings "$input")"
	input=" $GRAY""[$P_MESSAGE_SOURCE]$NC $input"
	if xis_set "$input" && xis_set "$P_IGNORE_PATTERN"; then
		input=$(grep -v "$P_IGNORE_PATTERN" <<<"$input")
		if xis_unset "$input"; then
			return 0
		fi
	fi
	time_stamp="$(date '+%d/%m/%Y %H:%M:%S.%N')"
	time_stamp="${time_stamp:0:-6}"
	actual_time="$(date +%s.%N)"
	if xis_unset "$P_TIME_LOG_OUT"; then
		P_TIME_LOG_OUT="$actual_time"
		echo >&2 "" >>"$WRAPPER_LOGFILE"
	fi
	elapsed_time=" +$(xformat_time "$P_TIME_LOG_OUT" "$actual_time")"
	P_TIME_LOG_OUT="$actual_time"
	echo "$time_stamp$elapsed_time$input" | sed -r "$P_COLOR_FILTER" >>"$WRAPPER_LOGFILE"
	if xis_true "$echo_enabled"; then
		if xis_unset "$P_TIME_CON_OUT"; then
			P_TIME_CON_OUT="$actual_time"
			if ! xstring_contains "$-" "x"; then
				printf "\033c" >&2
				:
			fi
		fi
		elapsed_time=" +$(xformat_time "$P_TIME_CON_OUT" "$actual_time")"
		P_TIME_CON_OUT="$actual_time"
		echo >&2 "$EP$GREEN$time_stamp$BLUE$elapsed_time$NC$input$NCC"
	fi
}

P_ASYNC_EXIT_STATUS="$P_GOFLAME_DIR/cachedb/__async_exit_status"
rm -rf "$P_ASYNC_EXIT_STATUS"

function xasync_exit() {
	local status="$*" loaded=()
	if xis_unset "$status"; then
		if ! xis_file_exists "$P_ASYNC_EXIT_STATUS"; then
			return
		fi
		eval "loaded=($(cat "$P_ASYNC_EXIT_STATUS"))"
		status="1"
		P_ELAPSED_PREFIX="ERROR: "
		P_ELAPSED_COLOR="$RED"
		if xis_ge "${#loaded[@]}" "1"; then
			status="${loaded[0]}"
		fi
		if xis_ge "${#loaded[@]}" "2"; then
			P_ELAPSED_PREFIX="${loaded[1]}"
		fi
		if xis_ge "${#loaded[@]}" "3"; then
			P_ELAPSED_COLOR="${loaded[2]}"
		fi
	fi
	echo "\"$status\" \"$P_ELAPSED_PREFIX\" \"$P_ELAPSED_COLOR\"" >"$P_ASYNC_EXIT_STATUS"
	exit "$status"
}

function xprint() {
	xemit "$P_ECHO_ENABLED" "$*"
}

function xdebug() {
	xemit "$P_DEBUG_ENABLED" "DEBUG: $*"
}

function xwarn() {
	xemit true "${ORANGE}WARNING: ${*//$NC/$NC$ORANGE}"
}

function xerror() {
	P_ELAPSED_PREFIX="ERROR: "
	P_ELAPSED_COLOR="$RED"
	xemit true "${RED}ERROR: ${*//$NC/$NC$RED}"
}

function xfatal() {
	P_ELAPSED_PREFIX="FATAL: "
	P_ELAPSED_COLOR="$RED"
	xemit true "${RED}FATAL: ${*//$NC/$NC$RED}"
	xasync_exit "1"
}

function xclean() {
	local input="$*"
	input="${input//$'\r'/}"
	input="${input//$'\n'/}"
	echo "$input"
}

function xtext() {
	local filter="$1" color="$2" source lines processed=() code_link prefix
	shift
	shift
	source="$*"
	if xis_unset "$source"; then
		return 0
	fi
	xsplit $'\n' lines "$source"
	for line in "${lines[@]}"; do
		line="${line//$'\r'/}"
		if xis_unset "$line"; then
			continue
		fi
		if xis_true "$filter" && xarray_contains "$line" "${processed[@]}"; then
			continue
		fi
		processed+=("$line")
		line="${line//$NC/$NC$color}"
		code_link="${line%% *}"
		# shellcheck disable=SC2001
		prefix=$(sed 's/:.*//' <<<"$code_link")
		if xis_file_exists "./$prefix"; then
			xprint "$LINK$code_link$NC$color${line:${#code_link}}"
		else
			xprint "$color$line$NC"
		fi
	done
}

function xdecorate() {
	echo "$GRAY$PI$*$PO$NC"
}

function xstring() {
	echo "\"${*//$'"'/\\\"}\""
}

function xcolor() {
	echo "$(xxd -p -u <<<"$*")$NC"
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

function xproject_name() {
	printf "%s" "$(xdecorate "$(basename -- "$PWD")")"
}

function xelapsed() {
	local end_time
	end_time="$(date +%s.%N)"
	xprint "$P_ELAPSED_COLOR${P_ELAPSED_PREFIX}Total runtime:" \
		"$(xformat_time "$P_TIME_STARTED" "$end_time")" \
		"(details: $(xhyperlink "file:///var/tmp/goflame/go-wrapper.log")$P_ELAPSED_COLOR)"
}

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
		xprint "Error on or near line $parent_lineno: $message; exiting with status $code"
	else
		xprint "Error on or near line $parent_lineno; exiting with status $code"
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

# Benchmarking SSH connection: What is the fastest cipher algorithm for RPi?
# https://blog.twogate.com/entry/2020/07/30/benchmarking-ssh-connection-what-is-the-fastest-cipher
#
# Following ciphers/MACs/KEXes are obtained from ECAM03DM-r1.0.
# See "tools/ssh-bench.sh" script for more details.

SCP_CIPHERS=(
	"chacha20-poly1305@openssh.com"
	"aes128-gcm@openssh.com"
	"aes192-ctr,aes128-ctr"
	"aes256-gcm@openssh.com,aes256-ctr"
)

SCP_MACS=(
	"hmac-sha2-512-etm@openssh.com"
	"hmac-sha2-256"
	"umac-128@openssh.com"
	"umac-128-etm@openssh.com"
	"hmac-sha1-etm@openssh.com"
	"hmac-sha2-512"
	"umac-64@openssh.com"
	"hmac-sha1"
	"umac-64-etm@openssh.com"
	"hmac-sha2-256-etm@openssh.com"
)

SCP_KEXES=(
	"ecdh-sha2-nistp256"
	"diffie-hellman-group14-sha256"
	"curve25519-sha256@libssh.org"
	"curve25519-sha256"
	"ecdh-sha2-nistp521"
	"diffie-hellman-group16-sha512"
	"ecdh-sha2-nistp384"
	"diffie-hellman-group18-sha512"
	"diffie-hellman-group-exchange-sha256"
)

SCP_FLAGS=(
	-T
	-o ProxyCommand=none
	-o StrictHostKeyChecking=no
	-o UserKnownHostsFile=/dev/null
	-o ConnectTimeout=5
	-o ConnectionAttempts=1
	-o ServerAliveInterval=1
	-o ServerAliveCountMax=2
	-o Compression=no
	-o Ciphers="$(xarray_join "," "${SCP_CIPHERS[@]:0:3}")"
	-o MACs="$(xarray_join "," "${SCP_MACS[@]:0:3}")"
	-o KexAlgorithms="$(xarray_join "," "${SCP_KEXES[@]:0:3}")"
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

TARGET_GOCXX=""
TARGET_DOMAIN="UNKNOWN-TARGET_DOMAIN"
TARGET_ADDR="UNKNOWN-TARGET_ADDR"
TARGET_PORT="UNKNOWN-TARGET_PORT"
TARGET_USER="UNKNOWN-TARGET_USER"
TARGET_PASS="UNKNOWN-TARGET_PASS"
TARGET_BUILD_LAUNCHER=""
TARGET_BINARY_NAME=""
TARGET_BINARY_PATH=""
TARGET_BINARY_ARGS=()
TARGET_SUPPRESS_MSSGS=()

TARGET_BUILD_GOFLAGS=()
TARGET_BUILD_GOTAGS=()
TARGET_BUILD_LDFLAGS=()

TTY_PORT="auto" # пустая строка или "auto" - автоматическое определение
TTY_MASK="ttyUSB*"
TTY_SPEED="115200"
TTY_PICOCOM="picocom"
TTY_DIRECT=false
TTY_USER=""
TTY_PASS=""
TTY_DELAY="300" # milliseconds
TTY_RETRY="3"

TOOLCHAIN_DIR="UNKNOWN-TOOLCHAIN_DIR"
CLEAN_GOCACHE=false
GIT_COMMIT_FILTER="" #
ENABLE_LINTERS=true
GOLANGCI_LINT_ENABLE=false
GOLANGCI_LINT_LINTERS=()
GOLANGCI_LINT_ARGUMENTS=()
GOLANGCI_LINT_FILTER=true
GOLANGCI_LINT_FAIL=false
GOLANGCI_LINT_SUPPRESS=()
STATICCHECK_ENABLE=false
STATICCHECK_CHECKS="all"
STATICCHECK_FILTER=true
STATICCHECK_SUPPRESS=()
STATICCHECK_GO_VERSION=""
STATICCHECK_FAIL=true
GO_VET_ENABLE=false
GO_VET_FILTER=true
GO_VET_FLAGS=("-composites=true")
GO_VET_FAIL=true
LLENCHECK_ENABLE=false
LLENCHECK_TABWIDTH=4
LLENCHECK_LIMIT=100
LLENCHECK_FILTER=true
LLENCHECK_FAIL=true
LLENCHECK_SUPPRESS=("ghdrcheck")
PRECOMMIT_ENABLE=false
PRECOMMIT_FAIL=true

USE_GO_VERSION=default
USE_HTTP_PROXY=
USE_RSYNC_METHOD=true
USE_RSYNC_BINARY="rsync"
USE_PIGZ_COMPRESSION=true
USE_PIGZ_BINARY="pigz"
USE_ASYNC_LINTERS=true
USE_NO_COLORS=false
USE_SERVICE_MASKS=false
USE_OVERLAY_DIR=""
USE_SHELL_TIMEOUT=10
USE_GOLANG_TIMEOUT=300
INSTALL_KEYBINDINGS=true
INSTALL_SSH_KEYS=false

# Compiler messages to be ignored
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

# Web-interface features ON and OFF
WEB_FEATURES_ON=()
WEB_FEATURES_OFF=()

LOCAL_GOPATH="$(go env GOPATH)"
LOCAL_STATICCHECK="$LOCAL_GOPATH/bin/staticcheck"
LOCAL_GOLANGCI_LINT_PATH="$LOCAL_GOPATH/bin/golangci-lint"

P_CONFIG_INI_LOADED=false
P_CONFIG_FILES=("project.default" "project.conf" "project.user")
for config_file in "${P_CONFIG_FILES[@]}"; do
	if xis_file_exists "$P_VSCODE_DIR/$config_file"; then
		# shellcheck disable=SC1090
		source "$P_VSCODE_DIR/$config_file"
		P_CONFIG_INI_LOADED=true
	fi
done

function xconfig_files() {
	local count="${#P_CONFIG_FILES[@]}" text=""
	local index="$count"
	while xis_gt "$index" "0"; do
		index=$((index - 1))
		if xis_set "$text"; then
			if xis_eq "$index" "0"; then
				text+=" or "
			else
				text+=", "
			fi
		fi
		text+="$(xhyperlink "file://.vscode/${P_CONFIG_FILES[$index]}")"
	done
	echo "$text"
}

P_IGNORE_PATTERN="$(printf "\n%s" "${MESSAGES_IGNORE[@]}")"
P_IGNORE_PATTERN="${P_IGNORE_PATTERN:1}"
P_TARGET_HYPERLINK="UNKNOWN-TARGET"

if xis_true "$USE_NO_COLORS"; then
	CE="" RED="" GREEN="" ORANGE="" BLUE="" GRAY="" UNDERLINE="" LINK="" NC="" NCC=""
	# shellcheck disable=SC2034
	PURPLE="" CIAN="" LTGRAY="" BOLD=""
fi

function xis_host_target() {
	xis_eq "$TARGET_ARCH" "host"
}

function xresolve_target_arch() {
	local required="$1"
	if ! xis_defined TARGET_ARCH || xis_unset "$TARGET_ARCH"; then
		TARGET_ARCH=""
		if xis_file_exists "$TOOLCHAIN_DIR/bin/arm-buildroot-linux-gnueabihf-gcc"; then
			TARGET_ARCH="armv7l"
		elif xis_file_exists "$TOOLCHAIN_DIR/bin/aarch64-buildroot-linux-gnu-gcc"; then
			TARGET_ARCH="aarch64"
		elif xis_true "$required"; then
			if ! xis_dir_exists "$TOOLCHAIN_DIR"; then
				P_EMIT_XLAT="none" xfatal "Toolchain $(xdecorate "TOOLCHAIN_DIR") does not" \
					"exist: $(xstring "$TOOLCHAIN_DIR")."
			else
				P_EMIT_XLAT="none" xfatal "Can not determine target architecture from" \
					"$(xdecorate "TOOLCHAIN_DIR"): $(xstring "$TOOLCHAIN_DIR")."
			fi
		fi
	fi
}

function xbuild_environment_init() {
	local init_value="$1" variable_name
	shift
	case "$init_value" in
	"()")
		while [[ "$#" != "0" ]]; do
			variable_name="EXPORT_$1"
			declare -ga "$variable_name=()"
			shift
		done
		;;
	"")
		while [[ "$#" != "0" ]]; do
			variable_name="EXPORT_$1"
			declare -g "$variable_name=\"\""
			shift
		done
		;;
	*)
		while [[ "$#" != "0" ]]; do
			variable_name="EXPORT_$1"
			declare -g "$variable_name"
			declare -n "source_ref=$variable_name"
			source_ref="$init_value"
			shift
		done
		;;
	esac
}

function xbuild_environment_prepare() {
	local build_gocxx build_goarch
	case "$TARGET_ARCH" in
	"armv7l")
		build_gocxx="arm-buildroot-linux-gnueabihf"
		build_goarch="arm"
		;;
	"aarch64")
		build_gocxx="aarch64-buildroot-linux-gnu"
		build_goarch="arm64"
		;;
	"host")
		build_gocxx="gcc"
		build_goarch="amd64"
		;;
	*) xfatal "Can not determine compiler for TARGET_ARCH=$(xstring "$TARGET_ARCH")" ;;
	esac

	if ! xis_defined TARGET_GOCXX || xis_unset "$TARGET_GOCXX"; then
		TARGET_GOCXX="$build_gocxx"
	fi

	# Enable debugging of the toolchain-wrapper set by BR_COMPILER_PARANOID_UNSAFE_PATH buildroot
	# configuration parameter.
	# shellcheck disable=SC2034
	EXPORT_BR2_DEBUG_WRAPPER="2"

	# shellcheck disable=SC2034
	EXPORT_GOPROXY="$GOPROXY"
	# shellcheck disable=SC2034
	EXPORT_GODEBUG="$GODEBUG"
	# shellcheck disable=SC2034
	EXPORT_GO111MODULE="on"
	# shellcheck disable=SC2034
	EXPORT_GOWORK="off"
	# shellcheck disable=SC2034
	EXPORT_GOVCS="*:all"
	# shellcheck disable=SC2034
	EXPORT_GOOS="linux"
	# shellcheck disable=SC2034
	EXPORT_GOARCH="$build_goarch"
	# shellcheck disable=SC2034
	EXPORT_GOFLAGS="-mod=mod" # "-mod=vendor"

	if ! xis_host_target; then
		EXPORT_GOROOT="$TOOLCHAIN_DIR/go" # 1.19

		TOOLCHAIN_GOBIN="$EXPORT_GOROOT/bin/go"
		EXPORT_GOPATH="$HOME/go/goflame/go-path"
		EXPORT_GOMODCACHE="$EXPORT_GOPATH/pkg/mod"
		EXPORT_GOCACHE="$EXPORT_GOPATH/cache"
		EXPORT_GOENV="$EXPORT_GOPATH/env"

		# shellcheck disable=SC2034
		EXPORT_CGO_ENABLED="1"
		local cgo_cyyflags=("-g" "-O2" "-I" "$TOOLCHAIN_DIR/include/libxml2")
		# shellcheck disable=SC2034
		EXPORT_CGO_CFLAGS=("${cgo_cyyflags[@]}")
		# shellcheck disable=SC2034
		EXPORT_CGO_CXXFLAGS=("${cgo_cyyflags[@]}")
		# shellcheck disable=SC2034
		EXPORT_CGO_LDFLAGS=()
		# shellcheck disable=SC2034
		EXPORT_CC="$TOOLCHAIN_DIR/bin/$TARGET_GOCXX-gcc"
		# shellcheck disable=SC2034
		EXPORT_CXX="$TOOLCHAIN_DIR/bin/$TARGET_GOCXX-g++"
	else
		EXPORT_GOROOT="?unset"
		EXPORT_GOPATH="?unset"
		EXPORT_GOMODCACHE="?unset"
		EXPORT_GOCACHE="?unset"
		EXPORT_GOENV="?unset"

		if ! xis_file_exists "$TOOLCHAIN_GOBIN"; then
			TOOLCHAIN_GOBIN="$(which "$TOOLCHAIN_GOBIN")"
		fi
	fi

}

function xbuild_environment_export() {
	local sources=() unset_list=()
	xsplit $'\n' sources "$(compgen -v | grep -E "^EXPORT_.*")"
	declare -A assignee
	for source in "${sources[@]}"; do
		local source_type source_ref source_array=() target="${source:7}" target_type="" target_ref
		declare -n "source_ref=$source"
		local source_value="${source_ref[*]}"
		if xis_eq "$source_value" "?keep"; then
			continue
		fi
		if xis_eq "$source_value" "?unset"; then
			unset_list+=("$target")
			eval "unset $target"
			continue
		fi
		source_type="$(declare -p "$source" 2>/dev/null)"
		case "$source_type" in
		"declare -- "*)
			assignee["${target}"]+=", $source=$source_value"
			declare -gx "$target"
			declare -n "target_ref=$target"
			target_ref="$source_value"
			;;
		"declare -a "*)
			source_array=("${source_ref[@]}")
			assignee["${target}"]+=", $source=(${source_array[*]})"
			declare -gx "$target"
			declare -n "target_ref=$target"
			target_ref="${source_array[*]}"
			;;
		*)
			xwarn "Unknown type of the variable $(xdecorate "$source"): '$source_type'"
			;;
		esac
	done
	if xis_true "$P_DEBUG_GOENV"; then
		xdebug "Exporting Golang environment:"
		xdebug "    Unset: $(xarray_join ", " "${unset_list[@]}")"
		for target in "${!assignee[@]}"; do
			declare -n "target_ref=$target"
			xdebug "    $target <- ${assignee["$target"]:2}"
		done
	fi
}

# To view Golang environment: $ go env
xbuild_environment_init "?unset" GOSUMDB GOTOOLDIR GOVERSION GOEXPERIMENT GOTMPDIR

xresolve_target_arch false

function xapply_composite_variables() {
	local sources suffixes=() suffix arch_suffix postfix
	arch_suffix="_$(xstring_to_uppercase "$TARGET_ARCH")"
	suffixes+=("$arch_suffix")
	if xis_true "$P_MODE_DEBUG"; then
		suffixes+=("_DEBUG" "_DEBUG$arch_suffix")
	fi
	if xis_true "$P_MODE_EXEC"; then
		suffixes+=("_EXEC" "_EXEC$arch_suffix")
	fi
	if xis_true "$P_MODE_TEST"; then
		suffixes+=("_TEST" "_TEST$arch_suffix")
	fi
	if xis_true "$P_MODE_BUILD"; then
		suffixes+=("_BUILD" "_BUILD$arch_suffix")
	fi
	if xis_true "$P_MODE_REBUILD"; then
		suffixes+=("_REBUILD" "_REBUILD$arch_suffix")
	fi
	if xis_true "$P_MODE_LINT"; then
		suffixes+=("_LINT" "_LINT$arch_suffix")
	fi
	filter="^.*($(xarray_join "|" "${suffixes[@]}"))$"
	xsplit $'\n' sources "$(compgen -v | grep -E "$filter")"
	declare -A assignee
	for suffix in "${suffixes[@]}"; do
		for source in "${sources[@]}"; do
			if [[ ! "$source" =~ ^(P_)?(.*)"$suffix"$ ]]; then
				continue
			fi
			if xis_set "${BASH_REMATCH[1]}"; then
				continue
			fi
			local source_ref target="${BASH_REMATCH[2]}" target_ref
			if [[ "$target" =~ $filter ]]; then
				continue
			fi
			declare -n "source_ref=$source" "target_ref=$target"

			case "$(declare -p "$target" 2>/dev/null)" in
			"declare -- "*)
				assignee["${target}"]+=", $source=$source_ref"
				target_ref="$source_ref"
				;;
			"declare -a "*)
				local action="" source_array=()
				if xis_ne "${#source_ref[@]}" "0"; then
					action="${source_ref[0]}"
				fi
				case "$action" in
				"[prepend]")
					source_array=("${source_ref[@]:1}")
					xarray_remove_duplicates "$target" "${source_array[@]}" "${target_ref[@]}"
					;;
				"[replace]")
					source_array=("${source_ref[@]:1}")
					xarray_remove_duplicates "$target" "${source_array[@]}"
					;;
				*)
					source_array=("${source_ref[@]}")
					xarray_remove_duplicates "$target" "${target_ref[@]}" "${source_array[@]}"
					;;
				esac
				assignee["${target}[]"]+=", $source=[$(xarray_join "," "${source_array[@]}")]"
				;;
			*)
				xwarn "Unknown type of the variable $(xdecorate "$source")"
				;;
			esac
		done
	done
	if xis_true "$P_DEBUG_BUILDENV"; then
		postfix="$(xarray_join "," "${suffixes[@]}")"
		xdebug "Substituting configuration variables by suffixes: $postfix:"
		for target in "${!assignee[@]}"; do
			xdebug "    $target <- ${assignee["$target"]:2}"
		done
	fi
}

EXEC_STDOUT=
EXEC_STDERR=
EXEC_STATUS=

function xexestat() {
	local prefix="$1" stdout="$2" stderr="$3" status="$4"
	if xis_ne "$status" "0"; then
		local needStatus=true
		if xis_set "$stdout"; then
			xprint "$prefix STATUS $(xexec_status "$status"), STDOUT: $stdout"
			needStatus=false
		fi
		if xis_set "$stderr"; then
			xprint "$prefix STATUS $(xexec_status "$status"), STDERR: $stderr"
			needStatus=false
		fi
		if xis_true "$needStatus"; then
			xprint "$prefix STATUS: $(xexec_status "$status")"
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
	lookup=$(dnf search "$executable" --color never 2>/dev/null | awk 'FNR>=2{ print $1 }')
	xsplit $'\n' packages "$lookup"
	lookup="$executable."
	for package in "${packages[@]}"; do
		if xstring_begins_with "$package" "$lookup"; then
			suggest="Try to install it with: ${GRAY}dnf install $(xexecutable_plain "$package")"
			xprint "Command $(xexecutable "$executable") not found. $suggest"
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
	local canfail="" command plain_text executable base timeout=""
	if xis_canfail "${1:-}"; then
		canfail="${1:-}"
		shift
	fi
	command="$*"
	if xis_unset "$command"; then
		return 0
	fi
	plain_text=$(xargs <<<"$command" 2>/dev/null)
	executable="${plain_text%% *}"
	if xis_set "$USE_SHELL_TIMEOUT" && ! xis_function "$executable"; then
		base="$(basename -- "$executable")"
		case "$base" in
		"cat" | "cp" | "dig" | "echo" | "find" | "gobrew" | "grep" | "gzip" | "ip" | "ln" | \
			"mkdir" | "mv" | "nmap" | "picocom" | "pigz" | "ping" | "pip3" | "rm" | "sed" | \
			"ssh-keygen" | "stty" | "tail" | "tar" | "timeout" | "touch") ;;
		"python3" | "rsync" | "sshpass")
			timeout="$USE_SHELL_TIMEOUT"
			;;
		"go" | "dlv" | "golangci-lint" | "pre-commit" | "staticcheck")
			timeout="$USE_GOLANG_TIMEOUT"
			;;
		*)
			if ! timeout="$(xvar USE_SHELL_TIMEOUT "$base")"; then
				xwarn "WARNING: Unknown timeout for executable: $base"
			fi
			;;
		esac
		if xis_ne "$timeout" ""; then
			command="timeout --kill-after=$timeout $timeout $command"
		fi
	fi
	xdebug "Exec: $command"
	xfset "+e"
	{
		EXEC_STDOUT=$(chmod u+w /dev/fd/3 && eval "$command" 2>/dev/fd/3)
		EXEC_STATUS=$?
		EXEC_STDERR=$(cat <&3)
	} 3<<EOF
EOF
	xfunset
	if xis_ne "$EXEC_STATUS" "0" && xis_unset "$canfail"; then
		local prefix message
		prefix="$executable"
		plain_text="${plain_text:${#executable}}"
		xerror "Failed to execute: $(xstring "$prefix")$GRAY$plain_text"
		message=$(xsuggest_to_install_message "$executable")
		if xis_set "$message"; then
			xdebug "$EXEC_STDERR"
			xdebug "$EXEC_STDOUT"
			xerror "$message"
		else
			xtext false "$RED" "$EXEC_STDERR"
			xtext false "$RED" "$EXEC_STDOUT"
		fi
		xerror "Terminating with status $(xexec_status "$EXEC_STATUS")"
		xasync_exit "$EXEC_STATUS"
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
	"23") message="rsync failed" ;;
	"125") message="out of memory" ;;
	"126") message="command cannot execute" ;;
	"127") message="command not found" ;;
	"128") message="invalid argument" ;;
	"130") message="terminated by Ctrl-C" ;;
	"137") message="process killed by timeout" ;;
	esac
	if xis_set "$message"; then
		echo "$BLUE$EXEC_STATUS$NC: $message"
	else
		echo "$BLUE$EXEC_STATUS$NC"
	fi
}

function xexec_exit() {
	xdebug "Finishing wrapper with STDOUT, STDERR & STATUS=$(xexec_status "$EXEC_STATUS")"
	if xis_false "$P_ECHO_ENABLED"; then
		if xis_set "$EXEC_STDOUT"; then
			echo "$EXEC_STDOUT"
		fi
		if xis_set "$EXEC_STDERR"; then
			echo "$EXEC_STDERR" 1>&2
		fi
		if xis_unset "$EXEC_STATUS"; then
			xfatal "Missing EXEC_STATUS to exit"
		fi
	fi
	xasync_exit "$EXEC_STATUS"
}

P_OPTIONS_STACK=()

function xfset() {
	local old_options
	old_options="$(set +o)"
	P_OPTIONS_STACK+=("$old_options")
	for opt in "$@"; do
		set "$opt"
	done
}

function xfunset() {
	local old_options="${P_OPTIONS_STACK[-1]}"
	set +vx
	eval "$old_options"
	unset "P_OPTIONS_STACK[-1]"
}

function xresolve_buildroot_real_compilers() {
	local real="$$1.br_real"
	if xis_file_exists "$real"; then
		echo "$real"
	fi
	echo "$1"
}

# Override toolchain-wrapper set by BR_COMPILER_PARANOID_UNSAFE_PATH buildroot
# configuration parameter.
function xoverride_toolchain_wrapper() {
	local force="$1" toolchain_wrapper="$TOOLCHAIN_DIR/bin/toolchain-wrapper"
	if xis_file_exists "$toolchain_wrapper"; then
		if ! xis_file_exists "$toolchain_wrapper.org"; then
			xdebug "Backup and setting up toolchain-wrapper: $toolchain_wrapper"
			xexec cp -f "$toolchain_wrapper" "$toolchain_wrapper.pre"
			xexec cp -f "$P_VSCODE_DIR/scripts/go-toolchain-wrapper.sh" "$toolchain_wrapper"
			xexec mv "$toolchain_wrapper.pre" "$toolchain_wrapper.org"
		elif xis_true "$force"; then
			xdebug "Forced setting up toolchain-wrapper: $toolchain_wrapper"
			xexec cp -f "$P_VSCODE_DIR/scripts/go-toolchain-wrapper.sh" "$toolchain_wrapper"
		fi
	fi
}

xoverride_toolchain_wrapper false

P_CONFIG_HASH=""

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

P_TTY_SHELL_OUT=""

function xtty_debug() {
	if xis_true "$P_DEBUG_TTY"; then
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
		local all_ports ports=() search_mask="$TTY_MASK"
		all_ports="$(find /dev -name "$TTY_MASK" -print)"
		xsplit $'\n' ports "$all_ports"
		if xis_eq "${#ports[@]}" "0"; then
			xfatal "Unable to find USB TTY port (search mask: $(xstring "$search_mask"))"
		elif xis_eq "${#ports[@]}" "1"; then
			TTY_PORT="${ports[0]}"
		else
			xfatal "To many USB TTY ports: ${#ports[@]} (search mask: $(xstring "$search_mask"))"
		fi
		xtty_debug "resolved port: $TTY_PORT"
	fi
	xprint "Resolving device IP from TTY $(xdecorate "$TTY_PORT")..."
	if xis_true "$TTY_DIRECT"; then
		xexec stty -F "$TTY_PORT" raw -echo "$TTY_SPEED"
	fi
}

function xtty_shell() {
	local text
	text="$(printf "%s\r" "$@" "")"
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

function xtty_fatal() {
	xfatal "Device on $(xdecorate "$TTY_PORT") login failed: $*."
}

function xtty_peek_ip() {
	local output="$1" retries="$2" prompt=true ifconfig=false error="" have_eth=false
	local step="1" max_steps="5" lines=() line=""
	P_TTY_SHELL_OUT=""
	while xis_unset "$error"; do
		if xis_true "$prompt"; then
			prompt=false
			if ! xtty_shell ""; then
				error="failed to send command to device"
				break
			fi
		fi
		if xis_true "$ifconfig"; then
			ifconfig=false
			if ! xtty_shell "ifconfig"; then
				error="failed to 'ifconfig' send command to device"
				break
			fi
			xsplit $'\n' lines "$P_TTY_SHELL_OUT"
			for line in "${lines[@]}"; do
				match=$(echo "$line" | grep 'Link encap:Ethernet')
				if xis_set "$match"; then
					have_eth=true
				fi
				match=$(echo "$line" | grep 'inet addr:' | grep 'Bcast:' |
					grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b" | awk 'NR==1{print $1}')
				if [[ "$match" != "" ]]; then
					xtty_debug "got IP address: $match"
					eval "$output='$match'"
					return 0
				fi
			done
			if xis_false "$have_eth"; then
				error="device have no Ethernet?"
			else
				error="device have no IP address"
			fi
			break
		fi
		xtty_debug "step $step/$max_steps; output: '$P_TTY_SHELL_OUT'"
		case "$P_TTY_SHELL_OUT" in
		*"#"*)
			xtty_debug "got command prompt"
			ifconfig=true
			;;
		*"=>"*)
			xtty_debug "got bootup prompt"
			xtty_fatal "login failed: U-Boot command prompt mode, please boot up and continue."
			;;
		*"login: bad"*)
			xtty_debug "got login bad salt message"
			xtty_fatal "login failed: probably release firmware."
			;;
		*"Login incorrect"*)
			xtty_debug "got login incorrect message"
			xtty_fatal "login failed: incorrect user/pass credentials."
			;;
		*"login:"*)
			xtty_debug "got login prompt"
			if ! xtty_exchange "$TTY_USER" "Password:"; then
				error="login failed: missing prompt after password"
			fi
			;;
		*"Password:"*)
			xtty_debug "got password prompt"
			if ! xtty_exchange "$TTY_PASS" "#"; then
				if xstring_contains "$P_TTY_SHELL_OUT" "login: bad"; then
					eval "$retries='1'"
					error="login failed: authorization failed (bad salt)"
				else
					error="login failed: missing '#' prompt after password"
				fi
			fi
			xtty_debug "got command after login"
			ifconfig=true
			;;
		"")
			xtty_debug "got empty TTY response"
			error="no response from device"
			;;
		*)
			xtty_debug "got invalid/unknown TTY response: $P_TTY_SHELL_OUT"
			error="invalid/unknown response from device: $P_TTY_SHELL_OUT"
			;;
		esac
		step=$((step + 1))
		if [[ "$step" -gt "$max_steps" ]]; then
			error="max TTY retry/steps reached"
		fi
	done
	if xis_unset "$error" && xis_unset "$P_TTY_SHELL_OUT"; then
		error="no response from device"
	fi
	eval "$output='$error'"
	return 1
}

function xtty_resolve_ip() {
	local output="$1" retries="$TTY_RETRY"
	xtty_debug "Retries initial: $retries"
	if ! xtty_resolve_port; then
		return 1
	fi
	while xis_ne "$retries" "0"; do
		eval "$output=''"
		xtty_peek_ip "$output" "retries"
		if xis_succeeded; then
			return 0
		fi
		sleep 0.1
		P_DEBUG_TTY=true
		retries=$((retries - 1))
		xtty_debug "Retries left: $retries"
	done
	return 1
}

P_RESOLVE_REASON=""
P_TARGET_CONFIG_PATH="$P_GOFLAME_DIR/vscode-target.conf"

function xdiscard_target_config() {
	rm "$P_TARGET_CONFIG_PATH"
}

function xsave_target_config() {
	cat <<EOF >"$P_TARGET_CONFIG_PATH"
# Machine generated file. Do not modify.
# Variables TARGET_ADDR and TARGET_PORT should not be quoted.
HOST_BUILDROOT="$TOOLCHAIN_DIR"
TARGET_ADDR=$TARGET_ADDR
TARGET_PORT=$TARGET_PORT
TARGET_HOSTNAME="$TARGET_HOSTNAME"
TARGET_MACADDR="$TARGET_MACADDR"
TARGET_USER="$TARGET_USER"
TARGET_PASS="$TARGET_PASS"
TARGET_TTYPORT="$TARGET_TTYPORT"
TARGET_BINARY_NAME=$TARGET_BINARY_NAME
TARGET_BINARY_PATH=$TARGET_BINARY_PATH
USE_HTTP_PROXY="$USE_HTTP_PROXY"
USE_RSYNC_METHOD="$USE_RSYNC_METHOD"
USE_PIGZ_COMPRESSION="$USE_PIGZ_COMPRESSION"
CONFIG_HASH="$P_CONFIG_HASH"
GO_EXEC_STUB=$P_GOFLAME_DIR/$P_GO_EXEC_STUB
EOF
}

P_PYTHON_EXEC=()

function xpython_prepare() {
	if xis_eq "${#P_PYTHON_EXEC[@]}" ""0; then
		export PYTHONPYCACHEPREFIX="$P_GOFLAME_DIR/pycache"
		if [[ ! -d "$PYTHONPYCACHEPREFIX" ]]; then
			xexec mkdir -p "$PYTHONPYCACHEPREFIX"
		fi
		P_PYTHON_EXEC=(python3 "-X" "pycache_prefix=$(xstring "$PYTHONPYCACHEPREFIX")")
	fi
}

function xpython_exec() {
	local canfail=""
	if xis_canfail "${1:-}"; then
		canfail="${1:-}"
		shift
	fi
	xpython_prepare
	xexec "$canfail" "${P_PYTHON_EXEC[@]}" "$@"
}

function xresolve_target_config() {
	TARGET_HOSTNAME="$TARGET_ADDR"
	TARGET_MACADDR=""
	TARGET_TTYPORT=""
	P_RESOLVE_REASON=""
	if xis_true "$P_MODE_REBUILD"; then
		P_RESOLVE_REASON="forced by rebuild"
	elif ! xis_file_exists "$P_TARGET_CONFIG_PATH"; then
		P_RESOLVE_REASON="new configuration"
	else
		function xload_target_config_with_hash() {
			CONFIG_HASH=""
			# shellcheck disable=SC1090
			source "$P_TARGET_CONFIG_PATH"
			echo "$CONFIG_HASH"
		}
		local config_hash
		config_hash="$(xload_target_config_with_hash)"
		if xis_ne "$config_hash" "$P_CONFIG_HASH"; then
			P_RESOLVE_REASON="configuration changed"
		fi
	fi
	if xis_set "$P_RESOLVE_REASON"; then
		P_MODE_REBUILD=true
		xdebug "Creating target config for '$TARGET_ADDR' in $(xstring "$P_TARGET_CONFIG_PATH")," \
			"reason: $P_RESOLVE_REASON"
		xclean_directories "$P_CACHEDB_DIR" "$P_STATUS_DIR" "$P_UPLOAD_DIR" "$P_SCRIPTS_DIR"
		xresolve_remote_config
		xoverride_toolchain_wrapper true
		xsave_target_config
	fi
	# shellcheck disable=SC1090
	source "$P_TARGET_CONFIG_PATH"
	P_TARGET_HYPERLINK="$(xhyperlink "http://$TARGET_HOSTNAME")"
	if xis_ne "$TARGET_TTYPORT" ""; then
		P_TARGET_HYPERLINK="$(xhyperlink "http://$TARGET_ADDR")"
		P_TARGET_HYPERLINK="$P_TARGET_HYPERLINK (TTY $(xdecorate "$TARGET_TTYPORT"))"
	elif xis_ne "$TARGET_HOSTNAME" "$TARGET_ADDR"; then
		P_TARGET_HYPERLINK="$P_TARGET_HYPERLINK (IP $(xdecorate "$TARGET_ADDR"))"
	elif xis_ne "$TARGET_MACADDR" ""; then
		P_TARGET_HYPERLINK="$P_TARGET_HYPERLINK (MAC $(xdecorate "$TARGET_MACADDR"))"
	fi
}

function xresolve_remote_config() {
	if xis_host_target; then
		TARGET_HOSTNAME="$(hostname)"
		TARGET_ADDR="127.0.0.1"
		return
	fi
	if xis_eq "$TARGET_ADDR" "tty" || xstring_begins_with "$TARGET_ADDR" "/dev/"; then
		local target_ip=""
		if xstring_begins_with "$TARGET_ADDR" "/dev/"; then
			TTY_PORT="$TARGET_ADDR"
		fi
		if ! xtty_resolve_ip "target_ip"; then
			if xis_set "$target_ip"; then
				xfatal "Unable to get IP from TTY $(xdecorate "$TTY_PORT"): $target_ip"
			else
				xfatal "Unable to get IP from TTY $(xdecorate "$TTY_PORT")"
			fi
		fi
		TARGET_TTYPORT="$TTY_PORT"
		TARGET_ADDR="$target_ip"
	elif ! xis_ipv4_addr "$TARGET_ADDR"; then
		local found=false mac_addr
		if xstring_begins_with "$TARGET_ADDR" "ASSET-"; then
			# Not implemented because of missing Jira login/password credentials.
			xfatal "Failed to resolve asset address for $(xdecorate "$TARGET_ADDR"):" \
				"Not implemented."
		fi
		local target_type="host"
		if xis_mac_addr "$TARGET_ADDR"; then
			target_type="MAC"
			mac_addr="$(xstring_to_lowercase "$TARGET_ADDR")"
			function resolve_ip_from_mac_addr() {
				xexec "$P_CANFAIL" ip neighbor "|" grep -i "$mac_addr" "|" \
					awk "'{ print \$1 ; exit }'"
				if xis_eq "$EXEC_STATUS" "0" && xis_ipv4_addr "$EXEC_STDOUT"; then
					TARGET_ADDR="$EXEC_STDOUT"
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
			local host_names=("$TARGET_ADDR.$TARGET_DOMAIN" "$TARGET_ADDR")
			for hostname in "${host_names[@]}"; do
				xexec "$P_CANFAIL" dig +short "$hostname" "|" awk "'{ print \$1 ; exit }'"
				if xis_eq "$EXEC_STATUS" "0" && xis_ipv4_addr "$EXEC_STDOUT"; then
					TARGET_ADDR="$EXEC_STDOUT"
					TARGET_HOSTNAME="$hostname"
					found=true
					break
				fi
			done
		fi
		if xis_false "$found"; then
			xfatal "Unable resolve IP for target $target_type '$TARGET_ADDR'."
		fi
	fi
	xssh "uname -m"
	local target_mach="$EXEC_STDOUT" target_stderr="$EXEC_STDERR"
	if xis_ne "$EXEC_STATUS" "0"; then
		xexec "$P_CANFAIL" timeout 1 ping -c 1 "$TARGET_ADDR"
		if xis_set "$target_stderr"; then
			xerror "$target_stderr"
		fi
		if xis_ne "$EXEC_STATUS" "0"; then
			xfatal "Target IP address $(xdecorate "$TARGET_ADDR") is not accessible" \
				"(no ping, status $(xexec_status "$EXEC_STATUS"))"
		else
			xfatal "Failed to resolve machine type for $(xdecorate "$TARGET_ADDR")"
		fi
	fi
	if xis_ne "$TARGET_ARCH" "$target_mach"; then
		xerror "Unexpected target $(xhyperlink "http://$TARGET_ADDR") architecture" \
			"$(xdecorate "$target_mach"), expected $(xdecorate "$TARGET_ARCH")"
		xerror "Probably invalid values in $(xdecorate TARGET_ARCH) and" \
			"$(xdecorate TOOLCHAIN_DIR) variables"
		xfatal "Check contents of the $(xhyperlink "file://.vscode/config-user.ini") or" \
			"$(xhyperlink "file://.vscode/config.ini")"
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
					local source="$P_VSCODE_DIR/bin/$binary_name-$TARGET_ARCH"
					local target="$target_path/$binary_name"
					if xis_file_exists "$source"; then
						xprint "Installing $(xdecorate "$binary_name-$TARGET_ARCH") to" \
							"target path $(xdecorate "$target")..."
						xscp "$source" ":$target"
					else
						xwarn "Failed to install $(xdecorate "$binary_name") to target path" \
							"$(xdecorate "$target"): $(xdecorate "$source") not found"
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
			xwarn "Disabling $enable_option: $(xdecorate "$binary_name") is not installed on" \
				" the $(xarray_join " and " "${missing[@]}")."
			export "$enable_option"="false"
		fi
	}
	resolve_binary "USE_RSYNC_METHOD" "$USE_RSYNC_BINARY" "/usr/bin"
	resolve_binary "USE_PIGZ_COMPRESSION" "$USE_PIGZ_BINARY" ""
	local exec_args=" \n" suppress=" \n" pattern
	for item in "${TARGET_BINARY_ARGS[@]}"; do
		exec_args="$exec_args\t\"$item\"\n"
	done
	for item in "${TARGET_SUPPRESS_MSSGS[@]}"; do
		suppress="$suppress\t\"$item\"\n"
	done
	xexec cp "$P_VSCODE_DIR/scripts/go-delve-loop.sh" "$P_SCRIPTS_DIR/"
	pattern=$(
		xsed_pattern \
			"__TARGET_PORT__" "$TARGET_PORT" \
			"__TARGET_BINARY_NAME__" "$TARGET_BINARY_NAME" \
			"__TARGET_BINARY_PATH__" "$TARGET_BINARY_PATH" \
			"__TARGET_BINARY_ARGS__" "$(xsed_array "" "${TARGET_BINARY_ARGS[@]}")" \
			"__TARGET_SUPPRESS_MSSGS__" "$(xsed_array "" "${TARGET_SUPPRESS_MSSGS[@]}")" \
			"__DLOOP_ENABLE_FILE__" "$DLOOP_ENABLE_FILE" \
			"__DLOOP_STATUS_FILE__" "$DLOOP_STATUS_FILE" \
			"__DLOOP_RESTART_FILE__" "$DLOOP_RESTART_FILE"
	)
	xsed_replace "$pattern" "$P_SCRIPTS_DIR/go-delve-loop.sh"
}

function xis_console_session_active() {
	if xproject_get_done "console_active"; then
		return 0
	fi
	xssh "$P_CANFAIL" "/usr/bin/dl --check-active"
	if xis_eq "$EXEC_STDOUT" "active"; then
		xproject_set_done "console_active"
		return 0
	fi
	return 1
}

function xtask_check_console_active() {
	if xis_unset "$P_START_CONSOLE" || xis_eq "$P_START_CONSOLE" "false"; then
		return
	fi
	xis_console_session_active
}

function xtask_ensure_console_active() {
	local terminals=() processed=() terminal command status
	if xis_unset "$P_START_CONSOLE" || xis_eq "$P_START_CONSOLE" "false"; then
		return
	fi
	if xis_console_session_active; then
		return
	fi
	xprint "Starting debug console on $BLUE$TARGET_ARCH$NC target " \
		"$(xhyperlink "http://$TARGET_HOSTNAME")"
	for terminal in "$P_START_CONSOLE" "$XDG_CURRENT_DESKTOP"; do
		case "$(xstring_to_lowercase "$terminal")" in
		*"kde"* | *"konsole"*) terminals+=("konsole") ;;
		*"gnome"*) terminals+=("gnome-terminal") ;;
		"auto" | "true") ;;
		*) xwarn "Unsupported/unknown desktop environment or terminal: $terminal" ;;
		esac
	done
	for terminal in "${terminals[@]}" "konsole" "gnome-terminal"; do
		if xarray_contains "$terminal" "${processed[@]}"; then
			continue
		fi
		processed+=("$terminal")
		if xis_unset "$(which "$terminal")"; then
			continue
		fi
		command="sshpass -p \"$TARGET_PASS\" ssh ${SSH_FLAGS[*]} \"$TARGET_USER@$TARGET_ADDR\" 'dl'"
		case "$terminal" in
		"konsole")
			nohup "$terminal" --new-tab -e "$command" >/dev/null 2>&1 &
			;;
		"gnome-terminal")
			nohup "$terminal" -- bash -c "$command; exec bash" >/dev/null 2>&1 &
			;;
		*) xfatal "Unsupported/unknown terminal: $terminal" ;;
		esac
		status="$?"
		if xis_eq "$status" "0"; then
			break
		fi
	done
	if xis_eq "$status" "0"; then
		status="inactive"
		for ((i = 0; i < 10; i++)); do
			if xis_console_session_active; then
				status="active"
				break
			fi
			sleep 0.1
		done
	fi
	if xis_ne "$status" "active"; then
		xerror "Unable to start $(xdecorate "dlv") on the $(xdecorate "$TARGET_ADDR")"
		xfatal "Process $(xdecorate "dlv") seems to be inactive (status $status)."
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
	local canfail=
	if xis_canfail "${1:-}"; then
		canfail="${1:-}"
		shift
	fi
	xexec "$canfail" sshpass -p "$TARGET_PASS" ssh "${SSH_FLAGS[@]}" \
		"$TARGET_USER@$TARGET_ADDR" "\"$*\""
}

P_SSH_HOST_STDIO=""
P_SSH_HOST_POST=""
P_SSH_TARGET_STDIO=""
P_SSH_TARGET_PREF="" # mount -o remount,rw /;
P_SSH_TARGET_POST=""
P_SSH_COPY_FILES=false
P_SSH_DEBUG_FILES=false

function xremote_flash_pending_commands() {
	local host_args="$P_SSH_HOST_STDIO$P_SSH_HOST_POST"
	local target_pref="$P_SSH_TARGET_PREF$P_SSH_TARGET_STDIO"
	local target_args="$target_pref$P_SSH_TARGET_POST"
	if xis_set "$host_args" || xis_set "$target_args"; then
		local ssh_prefix="${P_SSH_HOST_STDIO}sshpass -p \"$TARGET_PASS\""
		local ssh_prefix="$ssh_prefix ssh ${SSH_FLAGS[*]} $TARGET_USER@$TARGET_ADDR"
		if xis_true "$USE_RSYNC_METHOD" && xis_true "$P_SSH_COPY_FILES"; then
			if xis_set "$target_pref"; then
				xexec "$ssh_prefix \"$target_pref\""
			fi
			xexec $USE_RSYNC_BINARY -azzPL --no-owner --no-group --no-perms \
				--inplace --partial --numeric-ids --stats --progress \
				-e "\"sshpass -p \"$TARGET_PASS\" ssh ${SSH_FLAGS[*]}\"" \
				"\"$P_UPLOAD_DIR/\"" "\"$TARGET_USER@$TARGET_ADDR:/\""
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
	P_SSH_COPY_FILES=false
}

function xforce_linters() {
	GOLANGCI_LINT_ENABLE=true
	STATICCHECK_ENABLE=true
	GO_VET_ENABLE=true
	LLENCHECK_ENABLE=true
	PRECOMMIT_ENABLE=true
	xlint_reset_results
}

function xreset_build_flags() {
	P_MODE_BUILD=false
	P_MODE_REBUILD=false
	P_MODE_DEBUG=false
	P_MODE_LINT=false
	P_MODE_EXEC=false
	P_MODE_TEST=false
}

function xscp() {
	local canfail=
	if xis_canfail "${1:-}"; then
		canfail="${1:-}"
		shift
	fi

	local dir="$TARGET_USER@$TARGET_ADDR"

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

	if xis_set "$canfail"; then
		xdebug "Target copy: $canfail $one -> $two"
	else
		xdebug "Target copy: $one -> $two"
	fi
	xexec "$canfail" sshpass -p "$TARGET_PASS" scp -C "${SCP_FLAGS[@]}" "$one" "$two"
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

function xremote_delete_files() {
	if xis_ne "$#" "0"; then
		P_SSH_TARGET_PREF+="rm -f $(printf "'%s' " "$@"); "
		xprint "Removing $# files: $(xjoin_elements true "$@")"
	fi
}

function xremote_copy_files() {
	local canfail=
	if xis_canfail "${1:-}"; then
		canfail="${1:-}"
		shift
	fi

	local list=("$@")
	if xis_eq "${#list[@]}" "0"; then
		return 0
	fi

	local files=() uploading=false uploads=() skipped=() directories=() symlinks=""
	for pair in "${list[@]}"; do
		xsplit "|" files "$pair"
		if xis_ne "${#files[@]}" "2"; then
			xfatal "Invalid copy command: \"$pair\""
		fi
		local fileA="${files[0]}" fileB="${files[1]}"
		if [[ "$fileB" =~ ^\:.* ]]; then
			uploading=true
			local prefA="${fileA:0:1}"
			if xis_eq "$prefA" "?"; then
				fileA="${fileA:1}"
			fi
			local platform=""
			if [[ "$fileA" =~ ^.*# ]]; then
				platform="${BASH_REMATCH[0]}"
				fileA="${fileA:${#platform}}"
				if xis_ne "$platform" "$TARGET_ARCH#"; then
					skipped+=("$platform$(basename -- "$fileA")")
					continue
				fi
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
				xasync_exit "1"
			fi

			local name_hash file_hash
			name_hash=$(xhash_text "$fileA")
			file_hash=$(xhash_file "$fileA")

			if xis_false "$COPY_CACHE" || xis_ne "$(xcache_get "$name_hash")" "$file_hash"; then
				if xis_eq "${#directories[@]}" "0"; then
					directories+=("$P_UPLOAD_DIR")
				fi
				local backup_target="$P_UPLOAD_DIR/${fileB:1}"
				backup_target="${backup_target//\/\//\/}"
				local backup_subdir
				backup_subdir=$(dirname "$backup_target")
				if ! xarray_contains "$backup_subdir" "${directories[@]}"; then
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
			xwarn "Skipping ${#skipped[@]} files: $(xjoin_elements true "${skipped[@]}")"
		fi
		if xis_ne "${#uploads[@]}" "0"; then
			local upload_method="unknown"
			if xis_false $USE_RSYNC_METHOD; then
				local pkg="gzip -5 --no-name" tar_args="--no-same-owner --no-same-permissions"
				upload_method="ssh+gzip"
				if xis_true "$USE_PIGZ_COMPRESSION"; then
					pkg="$USE_PIGZ_BINARY --processes $(nproc) -9 --no-time --no-name"
					upload_method="ssh+$USE_PIGZ_BINARY"
				fi
				P_SSH_HOST_STDIO="tar -cf - -C \"$P_UPLOAD_DIR\" --dereference \".\" | $pkg - | "
				P_SSH_TARGET_STDIO="gzip -dc | tar $tar_args -xf - -C \"/\"; "
			else
				upload_method="$USE_RSYNC_BINARY"
			fi
			P_SSH_COPY_FILES=true
			xprint "Uploading ${#uploads[@]} files via $upload_method:" \
				"$(xjoin_elements true "${uploads[@]}")"
		fi
	else
		xprint "Downloading ${#uploads[@]} files: $(xjoin_elements true "${uploads[@]}")"
	fi

	for pair in "${list[@]}"; do
		xsplit "|" files "$pair"
		if xis_ne "${#files[@]}" "2"; then
			xfatal "Invalid copy command: \"$pair\""
		fi
		local fileA="${files[0]}" fileB="${files[1]}"
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

function xremote_stop_services() {
	if xis_ne "$#" "0"; then
		for service in "$@"; do
			P_SSH_TARGET_PREF+="systemctl stop \"$service\"; "
			if xis_true "$USE_SERVICE_MASKS"; then
				P_SSH_TARGET_PREF+="systemctl mask \"$service\"; "
			fi
		done
		xprint "Stopping $# services: $(xjoin_elements true "$@")"
	fi
}

function xremote_start_services() {
	if xis_ne "$#" "0"; then
		for service in "$@"; do
			if xis_true "$USE_SERVICE_MASKS"; then
				P_SSH_TARGET_POST+="systemctl unmask \"$service\"; "
			fi
			P_SSH_TARGET_POST+="systemctl start \"$service\"; "
		done
		xprint "Starting $# services: $(xjoin_elements true "$@")"
	fi
}

function xremote_stop_processes() {
	if xis_ne "$#" "0"; then
		for proc_name in "$@"; do
			P_SSH_TARGET_PREF+="pkill \"$proc_name\" || true; "
		done
		xprint "Terminating $# processes: $(xjoin_elements true "$@")"
	fi
}

function xremote_start_processes() {
	if xis_ne "$#" "0"; then
		for proc_name in "$@"; do
			P_SSH_TARGET_POST+="$proc_name; "
		done
		xprint "Starting $# processes: $(xjoin_elements true "$@")"
	fi
}

function xremote_create_directories() {
	if xis_ne "$#" "0"; then
		for dirname in "$@"; do
			P_SSH_TARGET_POST+="mkdir -p \"$dirname\"; "
		done
		xprint "Creating $# directories: $(xjoin_elements false "$@")"
	fi
}

function xremote_execute_commands() {
	if xis_ne "$#" "0"; then
		local commands=()
		for command in "$@"; do
			if xis_eq "${command:0:1}" "@"; then
				command="${command:1}"
			else
				commands+=("${command%% *}")
			fi
			P_SSH_TARGET_POST+="$command; "
		done
		if xis_ne "${#commands[@]}" "0"; then
			xprint "Executing ${#commands[@]} target commands:" \
				"$(xjoin_elements false "${commands[@]}")"
		fi
	fi
}

function xtest_binary_installed() {
	local enable_key="$1"
	local binary="$2"
	local instructions="$3"
	if ! xis_file_exists "$binary"; then
		xerror "Required binary $(xexecutable "$(basename -- "$binary")") is not installed."
		xerror "To disable this feature set $enable_key=false in 'config-user.ini'."
		xfatal "Check installation instructions: $(xhyperlink "$instructions")"
	fi
}

function xextract_golang_version() {
	case "$1" in
	"default")
		echo ""
		;;
	"")
		local golang_version
		golang_version=$("$TOOLCHAIN_GOBIN" version)
		golang_version=$(awk '{print $3}' <<<"$golang_version")
		golang_version="${golang_version%.*}"
		echo "${golang_version:2}"
		;;
	*)
		echo "$1"
		;;
	esac
}

function xasync_exec() {
	if xis_true "$USE_ASYNC_LINTERS"; then
		job_pool_run "$@"
	else
		"$@"
	fi
}

P_PROJECT_TIMESTAMP=""
P_PROJECT_DONE_PREF="done_"

function xproject_file() {
	echo "$P_STATUS_DIR/$P_PROJECT_DONE_PREF$(xstring_to_lowercase "$1")"
}

function xproject_get_done() {
	xis_eq "$(cat "$(xproject_file "$1")" 2>/dev/null)" "$P_PROJECT_TIMESTAMP"
}

function xproject_set_done() {
	echo "$P_PROJECT_TIMESTAMP" >"$(xproject_file "$1")"
}

P_LINT_DIFF_FILTER=()
P_LINT_DIFF_ARGS=()

function xlint_reset_results() {
	xexec rm -rf "$P_STATUS_DIR/$P_PROJECT_DONE_PREF*"
}

function xlint_process_result() {
	local color="$1" state="$2" fail="$3" title="$4"
	if xis_ne "$EXEC_STATUS" "0"; then
		xtext true "$color" "$EXEC_STDOUT"
		xtext true "$color" "$EXEC_STDERR"
		if xis_true "$fail"; then
			xerror "$title errors has been detected. Fix before continue" \
				"(status $(xexec_status "$EXEC_STATUS"))."
			xasync_exit "$EXEC_STATUS"
		fi
	else
		xproject_set_done "$state"
		xtext true "" "$EXEC_STDOUT"
		xtext true "" "$EXEC_STDERR"
	fi
}

function xlint_run_golangci_lint() {
	if xis_false "$GOLANGCI_LINT_ENABLE" || xproject_get_done "GOLANGCI_LINT"; then
		return 0
	fi
	xtest_binary_installed "GOLANGCI_LINT_ENABLE" "$LOCAL_GOLANGCI_LINT_PATH" \
		"https://golangci-lint.run/usage/install/"
	local linter_args=("${GOLANGCI_LINT_ARGUMENTS[@]}") linters_list=()
	xarray_sort_unique linters_list "${GOLANGCI_LINT_LINTERS[@]}"
	if xarray_contains "all" "${linters_list[@]}"; then
		local disabled_list=("${GOLANGCI_LINT_SUPPRESS[@]}")
		for linter in "${linters_list[@]}"; do
			if xis_eq "$linter" "all" || xis_eq "$linter" "-all"; then
				continue
			fi
			if [[ "$linter" == -* ]]; then
				disabled_list+=("${linter:1}")
			fi
		done
		xarray_sort_unique disabled_list "${disabled_list[@]}"
		xexec "$LOCAL_GOLANGCI_LINT_PATH" "help" "linters"
		local known_linters=() enabled_list=()
		xsplit $'\n' known_linters "$EXEC_STDOUT"
		for linter_desc in "${known_linters[@]}"; do
			xsplit ":" linter_desc "$linter_desc"
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
			xsplit " " linter_desc "$linter"
			if xis_eq "${#linter_desc[@]}" "0"; then
				continue
			fi
			if xis_eq "${#linter_desc[@]}" "2" &&
				xis_eq "$(xclean "${linter_desc[1]}")" "[deprecated]"; then
				continue
			fi
			linter="$(xclean "${linter_desc[0]}")"
			if xis_unset "$linter"; then
				continue
			fi
			if ! xarray_contains "$linter" "${disabled_list[@]}"; then
				enabled_list+=("$linter")
			fi
		done
		xarray_sort_unique enabled_list "${enabled_list[@]}"
		for linter in "${enabled_list[@]}"; do
			linter_args+=("-E" "$linter")
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
	local lint_out="$P_GOFLAME_DIR/golangci-lint.log"
	xprint "Running $(xdecorate "golangci-lint") (details: $(xhyperlink "file://$lint_out"))"
	xexec "$P_CANFAIL" "$LOCAL_GOLANGCI_LINT_PATH" "run" "${linter_args[@]}" \
		"./..." ">" "$lint_out" "2>&1"
	if xis_true "$GOLANGCI_LINT_FILTER"; then
		xexec "$P_CANFAIL" cat "$lint_out" "|" "${P_LINT_DIFF_FILTER[@]}" \
			--parse-stdin --exclude-non-prefixed --exclude-nolint \
			"--prefix=${PREF}golangci$NC"
	else
		xexec "$P_CANFAIL" cat "$lint_out" "|" "${P_LINT_DIFF_FILTER[@]}" \
			--parse-stdin --exclude-non-prefixed --exclude-nolint \
			"--prefix=${PREF}golangci$NC" --print-all
	fi
	xlint_process_result "$RED" "GOLANGCI_LINT" "$GOLANGCI_LINT_FAIL" "Golangci-lint"
}

function xlint_run_staticckeck() {
	if xis_false "$STATICCHECK_ENABLE" || xproject_get_done "STATICCHECK"; then
		return 0
	fi
	xtest_binary_installed "STATICCHECK_ENABLE" "$LOCAL_STATICCHECK" \
		"https://staticcheck.dev/docs/"
	local flags=() golang_version request_version="$STATICCHECK_GO_VERSION"
	if xis_unset "$request_version"; then
		request_version="$USE_GO_VERSION"
	fi
	golang_version=$(xextract_golang_version "$request_version")
	if xis_set "$golang_version"; then
		flags+=("-go" "$golang_version")
	fi
	if xis_set "$STATICCHECK_CHECKS"; then
		flags+=("-checks" "$STATICCHECK_CHECKS")
	fi
	local lint_out="$P_GOFLAME_DIR/staticcheck.log" suppress_string
	xprint "Running $(xdecorate "staticcheck") (details: $(xhyperlink "file://$lint_out"))"
	xexec "$P_CANFAIL" "$LOCAL_STATICCHECK" "-version" "2>&1" ">" "$lint_out"
	xexec "$P_CANFAIL" "$LOCAL_STATICCHECK" "${flags[@]}" "./..." "2>&1" ">>" "$lint_out"
	suppress_string="$(xarray_join "),(" "${STATICCHECK_SUPPRESS[@]}")"
	if xis_set "$suppress_string"; then
		suppress_string="($suppress_string)"
	fi
	if xis_true "$STATICCHECK_FILTER"; then
		xexec "$P_CANFAIL" cat "$lint_out" "|" "${P_LINT_DIFF_FILTER[@]}" \
			--parse-stdin --exclude-non-prefixed "--prefix=${PREF}statickcheck$NC" \
			--exclude-list="\"$suppress_string\""
	else
		xexec "$P_CANFAIL" cat "$lint_out" "|" "${P_LINT_DIFF_FILTER[@]}" \
			--parse-stdin --exclude-non-prefixed "--prefix=${PREF}statickcheck$NC" \
			--exclude-list="\"$suppress_string\"" --print-all
	fi
	xlint_process_result "$RED" "STATICCHECK" "$STATICCHECK_FAIL" "Staticcheck"
}

function xlint_run_go_vet_check() {
	if xis_false "$GO_VET_ENABLE" || xproject_get_done "GO_VET"; then
		return 0
	fi
	local log="$P_GOFLAME_DIR/go-vet.log"
	xprint "Running $(xdecorate "go vet") (details: $(xhyperlink "file://$log"))"
	xexec "$P_CANFAIL" "$TOOLCHAIN_GOBIN" "vet" "${GO_VET_FLAGS[@]}" "./..." "2>&1" ">" "$log"
	if xis_true "$GO_VET_FILTER"; then
		xexec "$P_CANFAIL" cat "$log" "|" "${P_LINT_DIFF_FILTER[@]}" \
			--parse-stdin --exclude-non-prefixed "--prefix=${PREF}go-vet$NC"
	else
		xexec "$P_CANFAIL" cat "$log" "|" "${P_LINT_DIFF_FILTER[@]}" \
			--parse-stdin --exclude-non-prefixed "--prefix=${PREF}go-vet$NC" --print-all
	fi
	xlint_process_result "$RED" "GO_VET" "$GO_VET_FAIL" "Go-vet"
}

function xlint_run_llencheck() {
	if xis_false "$LLENCHECK_ENABLE" || xproject_get_done "LLENCHECK"; then
		return 0
	fi
	xprint "Running $(xdecorate "line-length-limit") check on $(xproject_name)"
	local suppress=()
	if xis_ne "${#LLENCHECK_SUPPRESS[@]}" "0"; then
		suppress=("--nolint" "$(xarray_join "," "${LLENCHECK_SUPPRESS[@]}")")
	fi
	if xis_true "$LLENCHECK_FILTER"; then
		xexec "$P_CANFAIL" "${P_LINT_DIFF_FILTER[@]}" --line-length-limit="$LLENCHECK_LIMIT" \
			--tab-width="$LLENCHECK_TABWIDTH" "${suppress[@]}" "${P_LINT_DIFF_ARGS[@]}" \
			"--prefix=${PREF}llen$NC"
	else
		xexec "$P_CANFAIL" "${P_LINT_DIFF_FILTER[@]}" --line-length-limit="$LLENCHECK_LIMIT" \
			--tab-width="$LLENCHECK_TABWIDTH" "${suppress[@]}" "${P_LINT_DIFF_ARGS[@]}" \
			"--prefix=${PREF}llen$NC" --print-all
	fi
	xlint_process_result "$RED" "LLENCHECK" "$LLENCHECK_FAIL" "Line-length-limit"
}

function xlint_run_precommit_check() {
	if xis_false "$PRECOMMIT_ENABLE" || xproject_get_done "PRECOMMIT"; then
		return 0
	fi
	xprint "Running $(xdecorate "pre-commit-checks") check on $(xproject_name)"
	local gobrew_bin gobrew_name="gobrew" gobrew_bin_dir="$HOME/.gobrew/bin" golang_version
	gobrew_bin="$gobrew_name"
	if ! xis_executable "$gobrew_bin"; then
		gobrew_bin="$gobrew_bin_dir/$gobrew_name"
		if ! xis_executable "$gobrew_bin"; then
			gobrew_bin=""
		fi
	fi
	local gobrew_args=()
	EXEC_STATUS=""
	if xis_set "$gobrew_bin"; then
		golang_version=$(xextract_golang_version "$USE_GO_VERSION")
		if xis_unset "$golang_version"; then
			golang_version="latest"
		fi
		if xis_set "$USE_HTTP_PROXY"; then
			gobrew_args+=("$P_CANFAIL")
		fi
		xexec "${gobrew_args[@]}" "$gobrew_bin" "use" "$golang_version"
		if xis_ne "$EXEC_STATUS" "0" && xis_set "$USE_HTTP_PROXY"; then
			export http_proxy="$USE_HTTP_PROXY"
			export https_proxy="$USE_HTTP_PROXY"
			export ftp_proxy="$USE_HTTP_PROXY"
			xexec "$gobrew_bin" "use" "$golang_version"
		fi
	fi
	if xis_eq "$EXEC_STATUS" "0"; then
		export SKIP=go-prepare-gobrew
		xexec "$P_CANFAIL" "pre-commit" "run" -a
		unset SKIP
	else
		xexec "$P_CANFAIL" "pre-commit" "run" -a
	fi
	local lines=() output="" index line="" failed=false
	xsplit $'\n' lines "$EXEC_STDOUT"
	for line in "${lines[@]}"; do
		if [[ "$line" == *"...Passed" ]]; then
			line="$NC${line//\.\.\.Passed/\.\.\.${GREEN}Passed$NC}"
			failed=false
		elif [[ "$line" == *"...Failed" ]] || xis_true "$failed"; then
			line="$RED$line$NC"
			failed=true
		fi
		output+="$line"$'\n'
	done
	EXEC_STDOUT="$output"
	xlint_process_result "" "PRECOMMIT" "$PRECOMMIT_FAIL" "Pre-commit-checks"
}

function xlint_async_prepare() {
	xpython_prepare
	P_LINT_DIFF_ARGS=()
	if xis_set "$GIT_COMMIT_FILTER"; then
		export P_LINT_DIFF_ARGS+=("-c=$GIT_COMMIT_FILTER")
	fi
	export P_LINT_DIFF_FILTER=("${P_PYTHON_EXEC[@]}"
		"$P_VSCODE_DIR/scripts/py-diff-check.py" "${P_LINT_DIFF_ARGS[@]}"
	)
}

function xcompile_exec_stub() {
	if [[ -f "$P_GOFLAME_DIR/$P_GO_EXEC_STUB" ]] && xis_false "$P_MODE_REBUILD"; then
		return
	fi
	xexec cp "$P_VSCODE_DIR/scripts/go-exec-stub.go" "$P_GOFLAME_DIR/$P_GO_EXEC_STUB.go"
	pattern=$(
		xsed_pattern \
			"__TARGET_ADDR__" "$TARGET_ADDR" \
			"__TARGET_PORT__" "$TARGET_PORT" \
			"__TARGET_USER__" "$TARGET_USER" \
			"__TARGET_PASS__" "$TARGET_PASS" \
			"__DLOOP_ENABLE_FILE__" "$DLOOP_ENABLE_FILE" \
			"__DLOOP_STATUS_FILE__" "$DLOOP_STATUS_FILE" \
			"__DLOOP_RESTART_FILE__" "$DLOOP_RESTART_FILE" \
			"\"__SCP_FLAGS__\"," "$(xsed_array "," "${SCP_FLAGS[@]}")"
	)
	xsed_replace "$pattern" "$P_GOFLAME_DIR/$P_GO_EXEC_STUB.go"
	xexec go build -o "$P_GOFLAME_DIR/$P_GO_EXEC_STUB" "$P_GOFLAME_DIR/$P_GO_EXEC_STUB.go"
}

function xtask_compile_project() {
	if xis_true "$P_MODE_REBUILD" || xis_true "$P_MODE_EXEC"; then
		xcompile_exec_stub
	fi
	if xproject_get_done "BUILD" && xis_false "$P_MODE_REBUILD"; then
		return
	fi
	if xis_true "$P_DEBUG_BUILDENV"; then
		xdebug "Build environment:"
		xdebug "    TARGET_BUILD_GOFLAGS: ${TARGET_BUILD_GOFLAGS[*]}"
		xdebug "    TARGET_BUILD_GOTAGS: ${TARGET_BUILD_GOTAGS[*]}"
		xdebug "    TARGET_BUILD_LDFLAGS: ${TARGET_BUILD_LDFLAGS[*]}"
	fi
	local go_args=()
	if xis_false "$P_MODE_TEST"; then
		go_args=("build" "${TARGET_BUILD_GOFLAGS[@]}" "-o" "$TARGET_BINARY_NAME")
	else
		go_args=("test" -C "$PWD" "-covermode=count" "-o" "$PWD/tests/")
	fi
	if xis_ne "${#TARGET_BUILD_GOTAGS[@]}" "0"; then
		go_args+=("-tags=$(xarray_join "," "${TARGET_BUILD_GOTAGS[@]}")")
	fi
	if xis_ne "${#TARGET_BUILD_LDFLAGS[@]}" "0"; then
		go_args+=("-ldflags \"${TARGET_BUILD_LDFLAGS[@]}\"")
	fi
	if xis_false "$P_MODE_TEST"; then
		if xis_set "$TARGET_BUILD_LAUNCHER"; then
			go_args+=("$TARGET_BUILD_LAUNCHER")
		fi
	else
		go_args+=("./...")
		xexec "$P_CANFAIL" rm -rf "$PWD/tests/*"
	fi

	if xis_false "$P_MODE_TEST"; then
		xbuild_environment_prepare
		xbuild_environment_export

		if xis_true "$P_DEBUG_GOENV"; then
			xprint "Current buildroot configuration:"
			P_EMIT_XLAT="none"
			P_EMIT_PREFIX="  " xprint "TOOLCHAIN_DIR=$(xstring "$TOOLCHAIN_DIR")"
			P_EMIT_XLAT="full" xprint "Golang version (\"$TOOLCHAIN_GOBIN\" version):"
			P_EMIT_XLAT="base"
			P_EMIT_PREFIX="  " xtext false "$NC" "$("$TOOLCHAIN_GOBIN" version)"
			P_EMIT_XLAT="full" xprint "Delve version (\"dlv\" version):"
			P_EMIT_XLAT="base"
			P_EMIT_PREFIX="  " xtext false "$NC" "$(dlv version)"
			xprint "Read back Golang environment:"
			P_EMIT_PREFIX="  " xtext false "$NC" "$("$TOOLCHAIN_GOBIN" env)"
			P_EMIT_XLAT="full"
		fi
	fi

	if xis_true "$CLEAN_GOCACHE"; then
		xprint "Cleaning Go compiler & linters cache..."
		xclean_directories "$EXPORT_GOCACHE" "$HOME/.cache/go-build"
		xexec go clean -cache
		if xis_true "$GOLANGCI_LINT_ENABLE"; then
			xexec "$LOCAL_GOLANGCI_LINT_PATH" cache clean
		fi
	fi
	if xis_false "$P_MODE_TEST"; then
		xexec "$TOOLCHAIN_GOBIN" "${go_args[@]}" "2>&1" "|" "${P_LINT_DIFF_FILTER[@]}" \
			--parse-stdin --exclude-non-prefixed "--prefix=${PREF}go-build$NC" \
			--print-all --print-any
	else
		xexec "$TOOLCHAIN_GOBIN" "${go_args[@]}"
	fi
	xlint_process_result "$RED" "BUILD" "true" "Go-compiler"
}

function xtask_compile_go_exec_stub() {
	if [[ -f "$P_GOFLAME_DIR/$P_GO_EXEC_STUB" ]] && xis_false "$P_MODE_REBUILD"; then
		return
	fi
	xexec cp "$P_VSCODE_DIR/scripts/go-exec-stub.go" "$P_GOFLAME_DIR/$P_GO_EXEC_STUB.go"
	pattern=$(
		xsed_pattern \
			"__TARGET_ADDR__" "$TARGET_ADDR" \
			"__TARGET_PORT__" "$TARGET_PORT" \
			"__TARGET_USER__" "$TARGET_USER" \
			"__TARGET_PASS__" "$TARGET_PASS" \
			"__DLOOP_ENABLE_FILE__" "$DLOOP_ENABLE_FILE" \
			"__DLOOP_STATUS_FILE__" "$DLOOP_STATUS_FILE" \
			"__DLOOP_RESTART_FILE__" "$DLOOP_RESTART_FILE" \
			"\"__SCP_FLAGS__\"," "$(xsed_array "," "${SCP_FLAGS[@]}")"
	)
	xsed_replace "$pattern" "$P_GOFLAME_DIR/$P_GO_EXEC_STUB.go"
	xexec go build -o "$P_GOFLAME_DIR/$P_GO_EXEC_STUB" "$P_GOFLAME_DIR/$P_GO_EXEC_STUB.go"
}

function xtask_apply_web_features() {
	if xis_host_target; then
		return
	fi
	local feature_args=""
	for feature in "${WEB_FEATURES_ON[@]}"; do
		feature_args="$feature_args&$feature=true"
	done
	for feature in "${WEB_FEATURES_OFF[@]}"; do
		feature_args="$feature_args&$feature=false"
	done
	if xis_unset "$feature_args"; then
		return 0
	fi
	local timeout=10
	local wget_command=(timeout "$timeout" wget --no-proxy "--timeout=$timeout"
		-q -O - "\"http://$TARGET_ADDR/cgi/features.cgi?${feature_args:1}\"")
	xexec "${wget_command[*]}"
	local response="${EXEC_STDOUT//[$'\t\r\n']/}"
	xdebug "WGET response: $response"

	local features_on_set=() features_on_err=()
	for feature in "${WEB_FEATURES_ON[@]}"; do
		local pattern="\"$feature\": set to True"
		if grep -i -q "$pattern" <<<"$response"; then
			features_on_set+=("$feature")
		else
			features_on_err+=("$feature")
		fi
	done

	local features_off_set=() features_off_err=()
	for feature in "${WEB_FEATURES_OFF[@]}"; do
		local pattern="\"$feature\": set to False"
		if grep -i -q "$pattern" <<<"$response"; then
			features_off_set+=("$feature")
		else
			features_off_err+=("$feature")
		fi
	done

	local features_set="" state_true="${BLUE}true${NC}" state_false="${BLUE}false${NC}"
	if xis_ne "${#features_on_set[@]}" "0"; then
		features_set="$features_set; $state_true: $(xjoin_elements true "${features_on_set[@]}")"
	fi
	if xis_ne "${#features_off_set[@]}" "0"; then
		features_set="$features_set; $state_false: $(xjoin_elements true "${features_off_set[@]}")"
	fi

	local features_err=""
	if xis_ne "${#features_on_err[@]}" "0"; then
		features_err="$features_err; $state_true: $(xjoin_elements true "${features_on_err[@]}")"
	fi
	if xis_ne "${#features_off_err[@]}" "0"; then
		features_err="$features_err; $state_false: $(xjoin_elements true "${features_off_err[@]}")"
	fi

	if xis_set "$features_set"; then
		xprint "Web-interface features set to ${features_set:2}"
	fi
	if xis_set "$features_err"; then
		xwarn "Failed to set Web-interface features to ${features_err:2}"
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
	xdebug "Truncating $WRAPPER_LOGFILE from $actual to $target limit, threshold $limit."
	xexec "cp \"$name\" \"$tmp_name\""
	local offset=$((actual - target))
	xexec "tail -$offset \"$tmp_name\" > \"$name\""
	xexec "rm -rf \"$tmp_name\""
}

function xtruncate_log_file() {
	xtruncate_text_file "$WRAPPER_LOGFILE" 5000 300
}

xtruncate_log_file

function xsed_array() {
	local delimiter="$1" output="\n"
	shift
	for item in "$@"; do
		output+="\t\"$item\"$delimiter\n"
	done
	echo "$output"
}

function xsed_pattern() {
	local result=()
	while [[ $# -gt 0 ]]; do
		result+=("-e" "\"s/$(xsed_escape "$1")/$(xsed_escape "$2")/g\"")
		shift
		shift
	done
	echo "${result[*]}"
}

function xsed_replace() {
	local pattern="$1"
	shift
	for file in "$@"; do
		xexec sed -i "$pattern" "$file"
	done
}

function xprepare_runtime_scripts() {
	COPY_FILES+=(
		"?$P_SCRIPTS_DIR/go-delve-loop.sh|:/usr/bin/dl"
		"?$P_VSCODE_DIR/scripts/onvifd-install.sh|:/usr/bin/oi"
	)
	P_SSH_DEBUG_FILES=true
	if xis_set "$USE_OVERLAY_DIR"; then
		local file_list files=() prefix target
		local paths=("$USE_OVERLAY_DIR/common" "$USE_OVERLAY_DIR/$TARGET_ARCH")
		for path in "${paths[@]}"; do
			if ! xis_dir_exists "$path"; then
				continue
			fi
			file_list="$(find "$path" -type f -print)"
			xsplit $'\n' files "$file_list"
			prefix="${#path}"
			for file in "${files[@]}"; do
				target=${file:$prefix}
				if xis_ne "$target" "/README.rst"; then
					COPY_FILES+=("?$file|:$target")
				fi
			done
		done
	fi
}

function xtask_install_vscode_keybindings() {
	if xis_false "$INSTALL_KEYBINDINGS"; then
		return
	fi
	xexec mkdir -p "$HOME/.config/Code/User"
	xpython_exec "$P_CANFAIL" "$P_VSCODE_DIR/scripts/py-keybindings.py" \
		"$HOME/.config/Code/User/keybindings.json" \
		"$P_VSCODE_DIR/keybindings.json"
	if xis_ne "$EXEC_STATUS" "0"; then
		xpython_exec "-m" "ensurepip" "--default-pip"
		xpython_exec "-m" "pip" "install" "jstyleson"
		xpython_exec "$P_VSCODE_DIR/scripts/py-keybindings.py" \
			"$HOME/.config/Code/User/keybindings.json" \
			"$P_VSCODE_DIR/keybindings.json"
	fi
}

function xtask_install_ssh_keys() {
	if xis_host_target || xis_false "$INSTALL_SSH_KEYS"; then
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
	EXECUTE_COMMANDS+=()
}

function xperform_build_and_deploy() {
	if xis_false "$P_CONFIG_INI_LOADED"; then
		xerror "Unable to load configuration from $(xconfig_files)."
		xfatal "See documentation for more details."
	fi

	xreset_build_flags
	xprepare_runtime_scripts

	local args=()
	xarray_remove_duplicates args "$@"
	xdebug "Build & deploy: ${args[*]}"
	local remote_run_mode="" exec_stop_mode=false
	while [[ "$#" != "0" ]]; do
		case "$1" in
		"[BUILD]")
			P_MODE_BUILD=true
			;;
		"[REBUILD]")
			P_MODE_REBUILD=true
			remote_run_mode="debug"
			;;
		"[LINT]")
			P_MODE_REBUILD=true
			P_MODE_LINT=true
			;;
		"[DEBUG]")
			P_MODE_DEBUG=true
			remote_run_mode="debug"
			;;
		"[TESTS]")
			P_MODE_TEST=true
			TARGET_ARCH="host"
			;;
		"[EXEC-START]")
			P_MODE_EXEC=true
			remote_run_mode="exec"
			;;
		"[EXEC-STOP]")
			exec_stop_mode=true
			remote_run_mode="exec"
			;;
		"[HOST]")
			TARGET_ARCH="host"
			;;
		"[ECHO]")
			P_ECHO_ENABLED=true
			;;
		*)
			xfatal "Invalid argument: $0"
			;;
		esac
		shift
	done

	xresolve_target_arch true

	if xis_host_target; then
		remote_run_mode=""
	fi

	local config=("$PWD" "$TARGET_ARCH")
	if xis_dir_exists "$P_VSCODE_DIR"; then
		config+=(
			"$(
				find -L "$P_VSCODE_DIR/scripts" \
					-type f -printf "%p %TY-%Tm-%Td %TH:%TM:%TS %Tz\n"
			)"
			"$(
				find -L "$P_VSCODE_DIR" -maxdepth 1 \
					-type f -printf "%p %TY-%Tm-%Td %TH:%TM:%TS %Tz\n"
			)"
		)
	fi

	P_CONFIG_HASH=$(md5sum <<<"${config[*]}")
	P_CONFIG_HASH="${P_CONFIG_HASH:0:32}"

	if xis_false "$P_ALWAYS_BUILD"; then
		local dir_hash="$P_STATUS_DIR/project_timestamps.log"
		xexec find -L "." -type f "\(" -iname "\"*\"" ! -iname "\"$TARGET_BINARY_NAME\"" "\)" \
			-not -path "\"./.git/*\"" -not -path "\"./tests/*\"" " \
		"-exec date -r {} "\"+%m-%d-%Y %H:%M:%S\"" "\;" ">" "$dir_hash"
		P_PROJECT_TIMESTAMP="$(xhash_file "$dir_hash")"
	else
		P_PROJECT_TIMESTAMP="$(xhash_text "$(date +"%T.%N")")"
	fi

	xresolve_target_config
	xapply_composite_variables

	if xis_true "$P_MODE_REBUILD"; then
		xpython_exec "-m" "pip" "install" "unidiff"
	fi

	local mode_message="Building" mode_deploy="" mode_article="to"
	if xis_true "$P_MODE_DEBUG"; then
		mode_message="Debugging"
		mode_article="on"
	elif xis_true "$P_MODE_TEST"; then
		mode_message="Building tests"
		mode_article="for"
	elif xis_true "$P_MODE_EXEC"; then
		mode_message="Building & running"
		mode_article="on"
	elif xis_true "$exec_stop_mode"; then
		mode_message="Terminating"
		mode_deploy=""
		mode_article="on"
	elif xis_true "$P_MODE_LINT"; then
		mode_message="Linting"
		mode_article="at"
	elif xis_true "$P_MODE_REBUILD"; then
		mode_message="Rebuilding"
		mode_deploy=" & deploying"
	elif xis_true "$P_MODE_BUILD"; then
		mode_message="Building"
		mode_deploy=" & deploying"
	fi
	if xis_host_target; then
		mode_deploy=""
	fi
	mode_message+="$mode_deploy $(xdecorate "$TARGET_BINARY_NAME")"
	if ! xis_host_target; then
		mode_message+=" $mode_article $BLUE$TARGET_ARCH$NC target $P_TARGET_HYPERLINK"
	fi
	if xis_set "$P_RESOLVE_REASON"; then
		mode_message+=", $P_RESOLVE_REASON"
	fi
	xprint "$mode_message"

	#
	# Async tasks
	#

	xlint_async_prepare

	if xis_true "$P_DEBUG_GOENV"; then
		USE_ASYNC_LINTERS=false
	fi
	if xis_true "$USE_ASYNC_LINTERS"; then
		# shellcheck disable=SC1091
		source "$P_VSCODE_DIR/scripts/go-job-pool.sh"
		job_pool_init "$(nproc)" 0
	fi

	if xis_true "$P_MODE_REBUILD" || xis_true "$P_MODE_BUILD"; then
		COPY_FILES+=(
			"$TARGET_BINARY_NAME|:$TARGET_BINARY_PATH/$TARGET_BINARY_NAME"
		)
		xasync_exec xtask_compile_project
	fi

	if xis_true "$ENABLE_LINTERS"; then
		xasync_exec xlint_run_staticckeck
		xasync_exec xlint_run_golangci_lint
		xasync_exec xlint_run_go_vet_check
		xasync_exec xlint_run_llencheck
		xasync_exec xlint_run_precommit_check
	fi

	if xis_true "$P_MODE_REBUILD"; then
		xasync_exec xtask_apply_web_features
		xasync_exec xtask_install_vscode_keybindings
		xasync_exec xtask_install_ssh_keys
	fi

	if xis_set "$remote_run_mode"; then
		xasync_exec xtask_check_console_active
	fi

	if xis_true "$USE_ASYNC_LINTERS"; then
		job_pool_wait
		job_pool_shutdown
	fi

	xasync_exit

	#
	# Ssh commands
	#

	if ! xis_host_target; then
		if xis_true "$P_MODE_REBUILD"; then
			P_SSH_TARGET_PREF+="rm -f \"$DLOOP_ENABLE_FILE\" \"$DLOOP_RESTART_FILE\"; "
		fi
		if xis_true "$exec_stop_mode"; then
			P_SSH_TARGET_PREF="rm -f \"$DLOOP_RESTART_FILE\"; $P_SSH_TARGET_PREF"
			P_SSH_TARGET_PREF+="pkill \"$TARGET_BINARY_NAME\" || true; "
		elif xis_eq "$remote_run_mode" "exec"; then
			P_SSH_TARGET_PREF="rm -f \"$DLOOP_RESTART_FILE\"; $P_SSH_TARGET_PREF"
			xremote_execute_commands "@echo 1 > $DLOOP_RESTART_FILE"
		else
			xremote_stop_services "${SERVICES_STOP[@]}"
			xremote_stop_processes "${PROCESSES_STOP[@]}"
			xremote_delete_files "${DELETE_FILES[@]}"
			xremote_create_directories "${DIRECTORIES_CREATE[@]}"
			xremote_copy_files "${COPY_FILES[@]}"
			xremote_execute_commands "${EXECUTE_COMMANDS[@]}"
			xremote_start_services "${SERVICES_START[@]}"
			xremote_start_processes "${PROCESSES_START[@]}"
		fi

		P_SSH_TARGET_PREF+="echo \"$remote_run_mode\" > \"$DLOOP_ENABLE_FILE\"; "
	fi

	xremote_flash_pending_commands
	if xis_set "$remote_run_mode"; then
		xtask_ensure_console_active
		if xis_true "$P_MODE_DEBUG" && xis_true "$P_SSH_DEBUG_FILES"; then
			sleep 0.4
		fi
	fi
}
