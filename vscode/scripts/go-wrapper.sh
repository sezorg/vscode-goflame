#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# GO compiler wrapper.
#
# Log messages are stored into file:///var/tmp/goflame/go-wrapper.log

set -euo pipefail

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/go-runtime.sh"

# List of services to be stopped
SERVICES_STOP+=(
	"onvifd"
	#"onvifd-debug"
)

# List of services to be started
SERVICES_START+=(
	#"nginx"
)

# List of process names to be stopped
PROCESSES_STOP+=(
	"dlv"
	"$TARGET_BIN_SOURCE"
	"$TARGET_BIN_NAME"
)

# List of processed to be started, executable with args
PROCESSES_START+=(
)

DIRECTORIES_CREATE+=(
	#"/tmp/nginx/"
)

# List of files to be deleted
DELETE_FILES+=(
	#"$TARGET_BIN_DESTIN"
)

# List of files to be copied, "source|target"
COPY_FILES+=(
	"$TARGET_BIN_SOURCE|:$TARGET_BIN_DESTIN"
	#"init/onvifd.conf|:/etc/onvifd.conf"
	#"init/onvifd.service|:/usr/lib/systemd/system/onvifd.service"
	#"init/users.toml|:/var/lib/onvifd/users.toml"
)
if [[ "$TARGET_ARCH" != "arm" ]]; then
	COPY_FILES+=(
		"$BUILDROOT_TARGET_DIR/usr/bin/dlv|:/usr/bin/dlv"
	)
fi

# Очистка кеша Golang
#CLEAN_GOCACHE=true

# Disable cache while building workspace.
COPY_CACHE=false

# Enable camera feature
CAMERA_FEATURES_ON+=(
	"actionengine"
	"archive"
	"audio"
	"ddns"
	"ipfiltering"
	"mse"
	"videoanalytics"
)

# Disable camera feature
CAMERA_FEATURES_OFF+=(
	#"webrtc"
)

# Advised target scripts that the initial upload deploy is complete.
EXECUTE_COMMANDS+=(
)

xunreferenced \
	"${SERVICES_STOP[@]}" \
	"${SERVICES_START[@]}" \
	"${PROCESSES_STOP[@]}" \
	"${PROCESSES_START[@]}" \
	"${DELETE_FILES[@]}" \
	"${COPY_FILES[@]}" \
	"${CAMERA_FEATURES_ON[@]}"

P_LOCAL_COMMAND=""
P_BUILD_COMMANDS=()

function xparse_go_arguments() {
	local original=("$@") result=() next_item="" this_item="" prev_item=""
	for next_item in "$@"; do
		local skip_item=false
		prev_item="$this_item"
		this_item="$next_item"
		case "$this_item" in
		"$SCRIPT_DIR/dlv-wrapper.sh")
			this_item="$LOCAL_DLVBIN"
			;;
		"build")
			XECHO_ENABLED=true
			P_BUILD_COMMANDS+=("[REBUILD]")
			;;
		"install" | "env" | "version" | "list")
			P_LOCAL_COMMAND="$this_item"
			;;
		"--echo")
			XECHO_ENABLED=true
			skip_item=true
			;;
		"--debug")
			XDEBUG_ENABLED=true
			skip_item=true
			;;
		"--trace")
			set -x
			skip_item=true
			;;
		"--goflame-check")
			P_BUILD_COMMANDS+=("[CHECK]")
			skip_item=true
			;;
		"./...")
			if xis_ne "${#P_BUILD_COMMANDS[@]}" "0"; then
				skip_item=true
			fi
			;;
		*)
			if xis_eq "$prev_item" "build"; then
				if xis_dir_exists "$this_item" || xis_file_exists "$this_item"; then
					skip_item=true
				fi
			fi
			;;
		esac
		if xis_false "$skip_item"; then
			result+=("$this_item")
		fi
	done

	xdebug "Go wrapper args: original: '${original[*]}'; modified: '${result[*]}'"
	set "${result[@]}"
}

xparse_go_arguments "$@"

if [[ ! -f "$BUILDROOT_GOBIN" ]]; then
	xerror "Can not find Go executable at \"$BUILDROOT_GOBIN\"."
	xerror "Check BUILDROOT_DIR variable in your $(xconfig_files)."
	if [[ -d "$BUILDROOT_DIR" ]]; then
		lookup_dir=$(find "$BUILDROOT_DIR" -name "using-buildroot-toolchain.txt" -maxdepth 5)
		xdebug "Actual BUILDROOT_DIR=\"$BUILDROOT_DIR\""
		xdebug "Found buildroot doc file: $lookup_dir"
		if xis_set "$lookup_dir"; then
			lookup_dir="$(dirname "$lookup_dir")"
			lookup_dir="$(dirname "$lookup_dir")"
			lookup_dir="$(dirname "$lookup_dir")"
			xprint "HINT: Set BUILDROOT_DIR=$(xstring "$lookup_dir")."
		fi
	fi
	exit "1"
fi

if xis_set "$P_LOCAL_COMMAND"; then
	xdebug "Executing \"$P_LOCAL_COMMAND\" command on local Go."
	xexec "$LOCAL_GOBIN" "$@"
	xexec_exit
fi

if xis_ne "${#P_BUILD_COMMANDS[@]}" "0"; then
	if [[ -f "./$TARGET_BIN_SOURCE" ]]; then
		xprepare_runtime_scripts
		xperform_build_and_deploy "${P_BUILD_COMMANDS[@]}" \
			"Rebuild & install $(xdecorate "$TARGET_BIN_NAME")"
		exit "0"
	elif xis_unset "$TARGET_BIN_SOURCE"; then
		xerror "Invalid configuration: variable $(xdecorate "TARGET_BIN_SOURCE") is not set"
		exit "1"
	else
		xerror "Main executable $(xdecorate "$TARGET_BIN_SOURCE") does not exist"
		exit "1"
	fi
else
	# Execute original Golang command
	xprint "$BUILDROOT_GOBIN $*"
	xexport_apply "${GOLANG_EXPORTS[@]}"
	xexec "$BUILDROOT_GOBIN" "$@"

fi

xexec_exit
