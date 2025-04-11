#!/usr/bin/env bash
# Copyright 2025 RnD Center "ELVEES", JSC
#
# GCC toolchain wrapper

set -euo pipefail

P_GOFLAME_DIR="/var/tmp/goflame"
P_VSCODE_CONFIG_PATH="$P_GOFLAME_DIR/vscode-target.conf"

function xstring_begins_with() {
	case "$1" in
	"$2"*)
		return 0
		;;
	esac
	return 1
}

function xis_file_exists() {
	[[ -f "$*" ]]
}

args=()
for arg in "$@"; do
	if ! xstring_begins_with "$arg" "-I/usr/include"; then
		args+=("$arg")
	fi
done

if xis_file_exists "$P_VSCODE_CONFIG_PATH"; then
	HOST_BUILDROOT="-"
	# shellcheck disable=SC1090
	source "$P_VSCODE_CONFIG_PATH"
	tool_path="$0"
	if xstring_begins_with "$tool_path" "$HOST_BUILDROOT/"; then
		tool_path="\$TOOLCHAIN_DIR${tool_path:${#HOST_BUILDROOT}}"
	fi
	time_stamp="$(date '+%d/%m/%Y %H:%M:%S.%N')"
	log_prefix="${time_stamp:0:-6} +00.000s [go-toolchain-wrapper]"
	echo "$log_prefix $tool_path $* >> ${args[*]}" >>/var/tmp/goflame/go-wrapper.log 2>&1
fi

"$0.br_real" "${args[@]}"
