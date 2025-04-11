#!/usr/bin/env bash
# Copyright 2025 RnD Center "ELVEES", JSC
#
# GO compiler wrapper.

set -euo pipefail

# shellcheck disable=SC2064
trap "trap - SIGTERM && kill -- -$$ >/dev/null 2>&1" SIGINT SIGTERM EXIT

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/go-runtime.sh"

P_LOCAL_COMMAND=""
P_BUILD_COMMANDS=()

function xparse_go_arguments() {
	local original=("$@") result=() next_item="" this_item="" prev_item=""
	for next_item in "$@"; do
		local skip_item=false
		prev_item="$this_item"
		this_item="$next_item"
		case "$this_item" in
		"${BASH_SOURCE[0]}")
			this_item="$LOCAL_DLVBIN"
			;;
		"build")
			P_BUILD_COMMANDS+=("[ECHO]" "[REBUILD]")
			;;
		"install" | "env" | "version" | "list")
			P_LOCAL_COMMAND="$this_item"
			;;
		"--echo")
			P_BUILD_COMMANDS+=("[ECHO]")
			skip_item=true
			;;
		"--goflame-build")
			P_BUILD_COMMANDS+=("[ECHO]" "[BUILD]")
			skip_item=true
			;;
		"--goflame-debug")
			P_BUILD_COMMANDS+=("[ECHO]" "[BUILD]" "[DEBUG]")
			skip_item=true
			;;
		"--goflame-exec-start")
			P_BUILD_COMMANDS+=("[ECHO]" "[BUILD]" "[EXEC-START]")
			skip_item=true
			;;
		"--goflame-exec-stop")
			P_BUILD_COMMANDS+=("[ECHO]" "[EXEC-STOP]")
			skip_item=true
			;;
		"--goflame-lint")
			P_BUILD_COMMANDS+=("[ECHO]" "[LINT]")
			skip_item=true
			;;
		"--goflame-tests")
			P_BUILD_COMMANDS+=("[ECHO]" "[HOST]" "[BUILD]" "[TESTS]")
			skip_item=true
			;;
		"--goflame-host-debug")
			P_BUILD_COMMANDS+=("[ECHO]" "[HOST]" "[BUILD]" "[DEBUG]")
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

if xis_set "$P_LOCAL_COMMAND"; then
	xdebug "Executing \"$P_LOCAL_COMMAND\" command on local Go."
	xexec "$(which go)" "$@"
	xexec_exit
fi

if xis_ne "${#P_BUILD_COMMANDS[@]}" "0"; then
	if xis_unset "$TARGET_BINARY_NAME"; then
		xerror "Invalid configuration: variable $(xdecorate "TARGET_BINARY_NAME") is not set"
		exit "1"
	fi
	xperform_build_and_deploy "${P_BUILD_COMMANDS[@]}"
else
	# Execute original Golang command
	xbuild_environment_prepare
	xbuild_environment_export
	xprint "$TOOLCHAIN_GOBIN $*"
	xexec "$TOOLCHAIN_GOBIN" "$@"
	xexec_exit
fi
