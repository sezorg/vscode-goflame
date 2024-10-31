#!/usr/bin/env bash
# Copyright 2024 RnD Center "ELVEES", JSC
#
# GCC toolchaun wrapper
#
# Log messages are stored into file:///var/tmp/goflame/go-wrapper.log

set -euo pipefail

P_TEMP_DIR="/var/tmp/goflame"
P_VSCODE_CONFIG_PATH="$P_TEMP_DIR/vscode-target.conf"

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
		tool_path="\$BUILDROOT_DIR${tool_path:${#HOST_BUILDROOT}}"
	fi
	time_stamp="$(date '+%d/%m/%Y %H:%M:%S.%N')"
	log_prefix="${time_stamp:0:-6} +00.000s [go-toolchain-wrapper]"
	echo "$log_prefix $tool_path $* >> ${args[*]}" >>/var/tmp/goflame/go-wrapper.log 2>&1
fi

"$0.br_real" "${args[@]}"
