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
	"$TARGET_BIN_DESTIN"
)

# List of files to be copied, "source|target"
COPY_FILES+=(
	#".vscode/data/onvifd_debug.service|:/usr/lib/systemd/system/onvifd_debug.service"
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
CLEAN_GOCACHE=true

# Disable chache then building workspace.
COPY_CACHE=n

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
	"webrtc"
)

# Advised target stripts that the initial upload deploy is complete.
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

SRCIPT_ARGS=("$@")
HAVE_BUILD_COMMAND=false
HAVE_LOCAL_COMMAND=

function xparse_go_arguments() {
	local modified=false result=() item="" prev_item=""
	xdebug "Go Args: ${SRCIPT_ARGS[*]}"
	for ((i = 0; i < ${#SRCIPT_ARGS[@]}; i++)); do
		prev_item="$item"
		item="${SRCIPT_ARGS[$i]}"
		if [[ "$item" == "$EXPORT_DLVBIN" ]]; then
			result+=("$LOCAL_DLVBIN")
			modified=true
		elif [[ "$item" == "build" ]]; then
			XECHO_ENABLED=true
			result+=("$item")
			modified=true
			HAVE_BUILD_COMMAND=true
		elif [[ "$item" == "./..." ]] ||
			[[ "$prev_item" == "build" && -d "$item" ]] ||
			[[ "$prev_item" == "build" && -f "$item" ]]; then
			if xis_true "$HAVE_BUILD_COMMAND"; then
				modified=true
			else
				result+=("$item")
			fi
		elif [[ "$item" == "install" ]]; then
			xset HAVE_LOCAL_COMMAND="$item"
			result+=("$item")
		elif [[ "$item" == "env" ]]; then
			xset HAVE_LOCAL_COMMAND="$item"
			result+=("$item")
		elif [[ "$item" == "version" ]]; then
			xset HAVE_LOCAL_COMMAND="$item"
			result+=("$item")
		elif [[ "$item" == "list" ]]; then
			xset HAVE_LOCAL_COMMAND="$item"
			result+=("$item")
		elif [[ "$item" == "--echo" ]]; then
			xset XECHO_ENABLED=true
			modified=true
		elif [[ "$item" == "--debug" ]]; then
			xset XDEBUG_ENABLED=true
			modified=true
		elif [[ "$item" == "--trace" ]]; then
			set -x
			modified=true
		else
			result+=("$item")
		fi
	done

	if xis_true "$modified"; then
		if xis_true "$HAVE_BUILD_COMMAND"; then
			# force debug build
			result+=("${TARGET_BUILD_FLAGS[@]}")
		fi
		SRCIPT_ARGS=("${result[@]}")
		xdebug "Modified args: $BUILDROOT_GOBIN ${SRCIPT_ARGS[*]}"
		return 0
	fi
	return 1
}

if xparse_go_arguments; then
	set "${SRCIPT_ARGS[@]}"
	xdebug "New Args: $*"
fi

if xis_set "$HAVE_LOCAL_COMMAND"; then
	xdebug "Executing \"$HAVE_LOCAL_COMMAND\" command on local Go."
	xexec "$LOCAL_GOBIN" "$@"
	xexit
fi

# Check configuration.
if [[ ! -f "$BUILDROOT_GOBIN" ]]; then
	xerror "Can not find Go executable at \"$BUILDROOT_GOBIN\"."
	xerror "Check BUILDROOT_DIR variable in your \"config-user.ini\" or \"config.ini\"."
	if [[ -d "$BUILDROOT_DIR" ]]; then
		lookup_dir=$(find "$BUILDROOT_DIR" -name "using-buildroot-toolchain.txt" -maxdepth 5)
		xdebug "Actual BUILDROOT_DIR=\"$BUILDROOT_DIR\""
		xdebug "Found buildroot doc file: $lookup_dir"
		if xis_set "$lookup_dir"; then
			lookup_dir="$(dirname "$lookup_dir")"
			lookup_dir="$(dirname "$lookup_dir")"
			lookup_dir="$(dirname "$lookup_dir")"
			xecho "HINT: Set BUILDROOT_DIR=\"$lookup_dir\"."
		fi
	fi
	exit "1"
fi

# Execute original Golang command
xexport_apply "${GOLANG_EXPORTS[@]}"
xexec "$BUILDROOT_GOBIN" "$@"

if xis_true "$HAVE_BUILD_COMMAND"; then
	if [[ "$EXEC_STATUS" == "0" ]]; then
		if [[ -f "./$TARGET_BIN_SOURCE" ]]; then
			xprepare_runtime_scripts
			xperform_build_and_deploy "[REBUILD]" \
				"Rebuild & install $(xdecorate "$TARGET_BIN_NAME") to remote host $TARGET_HYPERLINK"
			exit "0"
		else
			xerror "Main executable $(xdecorate "$TARGET_BIN_SOURCE") does not exist"
			exit "1"
		fi
	fi
fi

xexit
