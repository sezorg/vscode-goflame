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

usage() {
	local filename
	filename=$(basename "$0")
	log "Usage: $filename sd-card [zuul-uuid] [rootfs]"
	log "where:"
	log "    sd-card     sd card device /dev/XXX"
	log "    zuul-uuid   zuul periodic build pipeline identifier (UUID)"
	log "    rootfs      rootfs file name"
}

run() {
	local outer="fatal"
	if [[ "$1" == "safe" ]]; then
		shift
		outer="error"
	fi
	set +e
	output=$(eval "$* 2>&1")
	status="$?"
	set -e
	if [[ "$status" != "0" ]]; then
		if [[ "$output" != "" ]]; then
			error "$* (status $status)"
			"$outer" "$output"
		else
			"$outer" "$* (status $status)"
		fi
	fi
	return "$status"
}

download_file() {
	logn "Downloading $1... "
	local target
	target=$(basename "$1")
	if ! run safe wget --quiet "$zuul_source/$1" -O "$download_dir/$target"; then
		log "FAILED"
		fatal "Faild to download '$zuul_source/$1'."
	fi
	log "OK"
}

arg_sd_device=""
arg_zuul_uuid=""
arg_rootfs_squashfs_path=""
arg_format_mmc_path=""

while :; do
	case "$1" in
	-f)
		arg_format_mmc_path="$2"
		shift
		shift
		if [[ ! -f "$arg_format_mmc_path" ]]; then
			fatal "Argument '-f': unable to find file '$arg_format_mmc_path'."
		fi
		;;
	*)
		break
		;;
	esac
done

case $# in
2)
	arg_sd_device="/dev/$1"
	arg_zuul_uuid="$2"
	if [[ -f "$arg_zuul_uuid" ]]; then
		arg_rootfs_squashfs_path="$arg_zuul_uuid"
		arg_zuul_uuid=""
	fi
	;;
3)
	arg_sd_device="/dev/$1"
	arg_zuul_uuid="$2"
	arg_rootfs_squashfs_path="$3"
	if [[ ! -f "$arg_rootfs_squashfs_path" ]]; then
		fatal "Rootfs file '$arg_rootfs_squashfs_path' does not exists"
	fi
	;;
*)
	error "Incorrect number of arguments"
	usage
	exit 1
	;;
esac

arg_zuul_uuid="${arg_zuul_uuid:0:7}"
zuul_project="ecam03-dev-buildroot-build"
#zuul_peek="http://zuul.elvees.com/t/nto7/builds?job_name=$zuul_project&pipeline=periodic&skip=0"
zuul_base="http://zuul.elvees.com:8000/periodic/gerrit.elvees.com/ecam03/buildroot/master"
zuul_source="$zuul_base/$zuul_project/$arg_zuul_uuid/artifacts/images"
download_dir="/var/tmp/mcom03-sd-update"
format_mmc_name="format-mmc.sh"
rootfs_squashfs_name="rootfs.squashfs"

run mkdir -p "$download_dir"
run rm -rf "${download_dir:?}/"*

if [[ "$arg_zuul_uuid" != "" ]]; then
	if [[ "$arg_format_mmc_path" == "" ]]; then
		download_file "$format_mmc_name"
		arg_format_mmc_path="$download_dir/$format_mmc_name"
		run chmod +x "$arg_format_mmc_path"
	fi
	if [[ "$arg_rootfs_squashfs_path" = "" ]]; then
		download_file "$rootfs_squashfs_name"
		arg_rootfs_squashfs_path="$download_dir/$rootfs_squashfs_name"
	fi
fi

if [[ "$arg_format_mmc_path" == "" ]]; then
	fatal "File '$format_mmc_name' not specified. Use either '-f' or ZUUL UUID to obtain it."
elif [[ ! -f "$arg_format_mmc_path" ]]; then
	fatal "File '$arg_format_mmc_path' not exists."
fi
if [[ ! -f "$arg_rootfs_squashfs_path" ]]; then
	fatal "Rootfs file '$arg_rootfs_squashfs_path' does not exists"
fi

log "Creating new BOOT image on '$arg_sd_device'..."
if [[ "$(whoami | awk '{print $1}')" != "root" ]]; then
	sudo "$arg_format_mmc_path" "$arg_rootfs_squashfs_path" "$arg_sd_device"
else
	"$arg_format_mmc_path" "$arg_rootfs_squashfs_path" "$arg_sd_device"
fi
