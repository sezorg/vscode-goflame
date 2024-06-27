#!/bin/bash

set -euo pipefail

log() {
	echo "$*"
}

logn() {
	echo -n "$*"
}

debug() {
	if [[ "$arg_debug_mode" != "" ]]; then
		log "DEBUG: $*"
	fi
}

error() {
	log "  **** Error: $*"
}

fatal() {
	error "$*"

}

usage() {
	local filename
	filename=$(basename "$0")
	log "Usage: $filename [-r] [-c] [-d] [-f <format-mmc.sh>] [<sd-card>] [<swu-file>]"
	log "where:"
	log "    -r                  create recovery partition"
	log "    -m                  create MBR partition table (defaults to GPT)"
	log "    -c                  clean any cached data, force download"
	log "    -d                  enable debug messages"
	log "    -f <format-mmc.sh>  name of the script should be executed to flash MMC"
	log "    sd-card             optional sd card device /dev/<sd-card>"
	log "    swu-file            local or remote swu file"
	log ""
	log "examples:"
	log "    $filename sda 6cba2361dc4f4e258dc258b425828f4a"
	log "    $filename -f ./my-format-mmc.sh sda 6cba2361dc4f4e258dc258b425828f4a"
	log "    $filename -f ./my-format-mmc.sh sda ./my-rootfs.squashfs"
}

arg_mmc_name=""
arg_swu_file=""
arg_format_mmc_path=""
arg_create_recovery=""
arg_create_mbr=""
arg_purge_cache=""
arg_debug_mode=""

while [[ "$#" != "0" ]]; do
	case "$1" in
	-f)
		arg_format_mmc_path="$2"
		shift
		shift
		if [[ ! -f "$arg_format_mmc_path" ]]; then
			fatal "Argument '-f': unable to find file '$arg_format_mmc_path'."
		fi
		;;
	-r)
		arg_create_recovery="true"
		shift
		;;
	-m)
		arg_create_mbr="true"
		shift
		;;
	-c)
		arg_purge_cache="1"
		shift
		;;
	-d)
		arg_debug_mode="1"
		shift
		;;
	*)
		break
		;;
	esac
done

case $# in
1)
	arg_mmc_name=""
	arg_swu_file="$1"
	;;
2)
	arg_mmc_name="$1"
	arg_swu_file="$2"
	;;
*)
	error "Incorrect number of arguments"
	usage
	exit 1
	;;
esac

#
# --- target_mmc_device ---
#

target_mmc_device=""

function resolve_target_mmc_device() {
	local text all_devices=() removable_path removable_list=()
	if [[ "$arg_mmc_name" == "" ]]; then
		local filter="{if (\$2 == \"usb\" && \$1 ~ /^\// ) { print \$1 }}"
		text="$(lsblk -p -S -o NAME,TRAN | awk "$filter")"
		#text="$(lsblk -p -o NAME,TRAN | awk '{if (($2 == "usb" || $2 == "nvme") && $1 ~ /^\// ) { print $1 }}')"
		readarray -d $'\n' -t "all_devices" < <(printf '%s' "$text")
		for device in "${all_devices[@]}"; do
			debug "Found generic device: $device"
			removable_path="/sys/block/$(basename "$device")/removable"
			if [[ -f "$removable_path" ]]; then
				if [[ "$(cat "$removable_path" 2>/dev/null)" == "1" ]]; then
					debug "Found removable device: $device"
					removable_list+=("$device")
				fi
			fi
		done
		if [[ "${#removable_list[@]}" == "0" ]]; then
			fatal "No removable storage devices found."
		elif [[ "${#removable_list[@]}" == "1" ]]; then
			target_mmc_device="${removable_list[0]}"
		else
			error "Found ${#removable_list[@]} removable storage devices: ${removable_list[*]}"
			fatal "Specify which one to use with command line."
		fi
	else
		target_mmc_device="/dev/$arg_mmc_name"
		removable_path="/sys/block/$arg_mmc_name/removable"
		if [[ ! -f "$removable_path" ]]; then
			fatal "Device '$target_mmc_device' semms not removable or not mounted."
		fi
		if [[ "$(cat "$removable_path" 2>/dev/null)" != "1" ]]; then
			fatal "Device '$target_mmc_device' is not removable."
		fi
	fi
}

resolve_target_mmc_device

debug "Using MMC device: $target_mmc_device"

function begins_with() {
	case "$1" in
	"$2"*)
		true
		;;
	*)
		false
		;;
	esac
}

download_target=""
download_dir="/var/tmp/mcom03-sd-update"
mkdir -p "$download_dir"
if [[ "$arg_purge_cache" != "" ]]; then
	rm -rf "${download_dir:?}/"* >/dev/null 2>&1
fi

download_file() {
	local source="$1" target prefix
	prefix=$(echo -n "$(dirname "$source")" | md5sum)
	prefix="${prefix:0:8}"
	target=$(basename "$source")
	download_target="$download_dir/$prefix-$target"
	debug "download_target=$download_target"
	if [[ -f "$download_target" ]]; then
		log "Using $target from cache... OK"
		return
	fi
	if ! wget -q --show-progress "$source" -O "$download_target.part"; then
		fatal "Failed to download '$source'."
	fi
	mv "$download_target.part" "$download_target"
}

#
# --- arg_format_mmc_path ---
#

function resolve_format_mmc_path() {
	local format_mmc_name="format-mmc.sh" source
	if [[ "$arg_format_mmc_path" == "" ]]; then
		source="$(dirname "$arg_swu_file")/$format_mmc_name"
		if [[ -f "$source" ]]; then
			arg_format_mmc_path="$source"
			debug "Using FMMC: $arg_format_mmc_path..."
		elif begins_with "$arg_swu_file" "http"; then
			download_file "$source"
			arg_format_mmc_path="$download_target"
			chmod +x "$arg_format_mmc_path"
			debug "Using FMMC: $source..."
		elif [[ -f "./$format_mmc_name" ]]; then
			arg_format_mmc_path="./$format_mmc_name"
			debug "Using FMMC: $format_mmc_name from current directory..."
		fi

	fi
	if [[ ! -f "$arg_format_mmc_path" ]]; then
		fatal "Failed to resolve '$format_mmc_name' stript."
	fi
}

resolve_format_mmc_path

#
# --- source_swu_path ---
#

source_swu_path=""

function resolve_source_swu_path() {
	local source="$arg_swu_file"
	if [[ -f "$arg_swu_file" ]]; then
		source_swu_path="$source"
		debug "Using SWU: $source_swu_path..."
	elif begins_with "$arg_swu_file" "http"; then
		download_file "$arg_swu_file"
		source_swu_path="$download_target"
		debug "Using SWU: $arg_swu_file..."
	fi
	if [[ ! -f "$source_swu_path" ]]; then
		fatal "Failed to resolve '$source_swu_path' SWU file."
	fi
}

resolve_source_swu_path

filter_messages=(
	" blocks"
	" records in"
	" records out"
	"GPT fdisk"
	"Command (? for help)"
	"Recovery/transformation command"
	"MBR command (? for help)"
	"Finalize and exit? (Y/N)"
)
filter_pattern="$(printf "\n%s" "${filter_messages[@]}")"
filter_pattern="${filter_pattern:1}"

filter_output() {
	grep -v -e "$filter_pattern" -e '^[[:space:]]*$'
}

log "Flashing $(basename "$arg_swu_file") image to '$target_mmc_device'..."
format_mmc_args_list=()
if [[ "$arg_create_recovery" != "" ]]; then
	format_mmc_args_list+=("-r")
fi
format_mmc_args_list+=(
	"$source_swu_path"
	"$target_mmc_device"
)
(sudo "$arg_format_mmc_path" "${format_mmc_args_list[@]}") 2>&1 | filter_output
if [[ "$arg_create_mbr" != "" ]]; then
	(
		sudo gdisk "$target_mmc_device" <<EOF
r
g
w
y
EOF
	) 2>&1 | filter_output
fi

fdisk -l "$target_mmc_device"
