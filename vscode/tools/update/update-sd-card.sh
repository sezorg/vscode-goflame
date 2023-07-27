#!/bin/bash

set -euo pipefail

log() {
	echo "$*"
}

logn() {
	echo -n "$*"
}

error() {
	log "  **** Error: $*"
}

fatal() {
	error "$*"
	exit 1
}

if [ "$(whoami | awk '{print $1}')" != "root" ]; then
	error "*** must run script with sudo"
	exit
fi

usage() {
	local filename
	filename=$(basename "$0")
	log "Usage: $filename sd-card zuul-uuid"
	log "where:"
	log "    sd-card     sd card device /dev/XXX"
	log "    zuul-uuid   zuul periodic build pipeline identifier (UUID)"
}

run() {
	output=$(eval "$* 2>&1")
	status="$?"
	if [ "$status" != "0" ]; then
		error "$* (status $status)"
		if [ "$output" != "" ]; then
			error "$output"
		fi
	fi
	return "$status"
}

runv() {
	log ">>> $*"
	eval "$*"
	status="$?"
	if [ "$status" != "0" ]; then
		error "$* (status $status)"
	fi
	return "$status"
}

check_removeble_block_device() {
	if ! run udevadm info -q path -n "$1"; then
		fatal "Device \"$1\" does not exists."
	fi
	local complete_path="$output"
	if ! run udevadm info -a -p "$complete_path"; then
		fatal "Device \"$1\" at \"$complete_path\" is not valid device."
	fi
	local complete_info="$output" subsystems=""
	subsystems=$(grep "SUBSYSTEMS==\"usb\"" <<<"$complete_info" || true)
	if [ "$subsystems" = "" ]; then
		fatal "Device \"$1\" does not semss to be a USB/SD-Card."
	fi
}

download_file() {
	logn "Downloading $1... "
	local target
	target=$(basename "$1")
	if ! run wget --quiet "$zuul_source/$1" -O "$download_dir/$target"; then
		log "FAILED"
		fatal "Faild to download \"$zuul_source$1\"."
	fi
	log "OK"
}

cmdexists() {
	hash "$1" 2>/dev/null
}

erase_filesystem() {
	#log "Erasing partition $1"
	wipefs -a "$1" >/dev/null 2>&1 || true
}

unmount_partition() {
	if cmdexists udisksctl; then
		udisksctl unmount -b "$1" >/dev/null 2>&1 || true
	elif cmdexists systemd-umount; then
		systemd-umount "$1" >/dev/null 2>&1 || true
	else
		umount "$1" >/dev/null 2>&1 || true
	fi
}

unmount_block_device() {
	local device="$1" erase="$2" partitions
	partitions="$(fdisk -l "$device" | grep "^$device" | cut -f1 -d' ' || true)"
	mapfile -t partitions <<<"$partitions"
	#echo "partitions=${partitions[*]}"
	local postfix="."
	if [ "${#partitions[@]}" != "0" ]; then
		postfix=":"
	fi
	log "Unmounting block device \"$device\"$postfix"
	for partition in "${partitions[@]}"; do
		unmount_partition "$partition"
		rm -rf "$partition" || true
		[ "$erase" ] && erase_filesystem "$partition"
		log "    * partition $partition - OK"
	done
	[ "$erase" ] && erase_filesystem "$device"
}

getpart() {
	local partprefix=
	[[ "$1" =~ [0-9]$ ]] && partprefix=p
	echo "$1$partprefix$2"
}

supress_mssgs=(
	"Changes will remain in memory only"
	"Be careful before using the write command."
	"Command (m for help)"
	"   p   primary"
	"   e   extended"
	"Select (default p)"
	"Syncing disks"
	"records in"
	"records out"
)
supress_pattern="$(printf "\n%s" "${supress_mssgs[@]}")"
supress_pattern="${supress_pattern:1}"

if [ "$#" != 2 ]; then
	error "Inavlid number of arguments."
	usage
	exit 1
fi

target_device="/dev/$1"
zuul_uuid="$2"
zuul_uuid="${zuul_uuid:0:7}"

zuul_project="ecam03-dev-buildroot-build"
#zuul_peek="http://zuul.elvees.com/t/nto7/builds?job_name=$zuul_project&pipeline=periodic&skip=0"
zuul_base="http://zuul.elvees.com:8000/periodic/gerrit.elvees.com/ecam03/buildroot/master"
zuul_source="$zuul_base/$zuul_project/$zuul_uuid/artifacts/images"
download_dir="/var/tmp/mcom03-sd-update"
rootfs_name="rootfs.squashfs"
rootfs_path="$download_dir/$rootfs_name"

check_removeble_block_device "$target_device"
mkdir -p "$download_dir"
rm -rf "${download_dir:?}/"*
download_file "format-mmc.sh"
download_file "$rootfs_name"
chmod +x "$download_dir/format-mmc.sh"

rootfs_size=$(du -b "$rootfs_path" | cut -f1)
#rootfs_org_size=$(du -b "$rootfs_path" | cut -f1)
#rootfs_block_size=$((4 * 1024 * 1024))
#rootfs_blocks=$((("$rootfs_org_size" + "$rootfs_block_size" - 1) / "$rootfs_block_size"))
#rootfs_size=$(("$rootfs_blocks" * "$rootfs_block_size"))
#echo "$rootfs_org_size" $rootfs_block_size $rootfs_blocks $rootfs_size
#run dd if=/dev/zero of="$rootfs_path" bs=1 count=1 seek=$(("$rootfs_size" - 1))

unmount_block_device "$target_device" true
log "Creating new BOOT image on \"$target_device\"..."
"$download_dir/format-mmc.sh" "$rootfs_path" "$target_device" 2>&1 |
	grep -v -e "$supress_pattern" -e '^[[:space:]]*$'
sync

log "Calculating MD5 for \"$rootfs_name\", size $rootfs_size bytes"
rootfs_md5=$(dd if="$rootfs_path" status=none | md5sum)

veryfy_partition() {
	local partition_id partition_md5
	partition_id="$(getpart "$target_device" "$1")"
	logn "    * partition $partition_id - "
	partition_md5=$(dd if="$partition_id" bs="$rootfs_size" count="1" iflag=direct 2>"$download_dir/dd_status" | md5sum)
	if [ "$partition_md5" != "$rootfs_md5" ]; then
		log "FAILED"
		error "Failed to verify \"$partition_id\" MD5"
		error "$(cat "$download_dir/dd_status")"
		fatal "Calculated ${partition_md5:0:32} != expected ${rootfs_md5:0:32}"
	fi
	log "OK"
	log "      $(grep -v -e "$supress_pattern" <"$download_dir/dd_status")"
}

log "Verifying block device \"$target_device\":"
veryfy_partition 1
veryfy_partition 2

log "Operation successfully completed"
#eject "$target_device"
