#!/bin/bash

set -euo pipefail

log() {
	echo "$*"
}

usage() {
	local filename
	filename=$(basename "$0")
	"Usage: $filename revision zuul-uuid"
	echo "where:"
	echo "    revision    revision of the ecam03 board: dm1, dm2"
	echo "    zuul-uuid   zuul periodic build pipeline identifier (UUID)"
	exit 1
}

error() {
	log "ERROR: $*"
}

fatal() {
	error "$*"
	exit 1
}

run() {
	output=$(eval "$* 2>&1")
	status="$?"
	if [ "$status" != "0" ]; then
		log "ERROR: $* ($status)"
		if [ "$output" != "" ]; then
			log "ERROR: $output"
		fi
		#	else
		#		log "RUN: $*"
		#		if [ "$output" != "" ]; then
		#			log "RUN: $output"
		#		fi
	fi
	return "$status"
}

runv() {
	log ">>> $*"
	eval "$*"
	status="$?"
	if [ "$status" != "0" ]; then
		log "ERROR: $* ($status)"
	fi
	return "$status"
}

if [ "$#" != 2 ]; then
	error "Inavlid number of arguments."
	usage
fi

revision="$1"
zuul_uuid="$2"
zuul_uuid="${zuul_uuid:0:7}"

project="http://zuul.elvees.com:8000/periodic/gerrit.elvees.com/ecam03/buildroot"
source="$project/master/ecam03-dev-buildroot-build/$zuul_uuid/artifacts/images/tl-sbimg/"

files=()
sbl_env_offset=""
case "$revision" in
"ecam03dm-r1.0" | "dm1")
	files=(
		"ecam03dm-bootrom.sbimg"
		"sbl-tl-mcom03-ecam03dm-r1.0.sbimg"
		"sbl-tl-otp.bin"
	)
	sbl_env_offset="0x1FD0000"
	;;
"ecam03dm-r2.0" | "dm2")
	files=(
		"pm03cam-r2.0-bootrom.sbimg"
		"sbl-tl-mcom03-pm03cam-r2.0-ecam03common-r2.0.sbimg"
		"sbl-tl-otp.bin"
	)
	sbl_env_offset="0xFD0000"
	;;
*)
	error "Unknown or unsupported board revision \"$revision\""
	usage
	;;
esac

log "Using revision \"$revision\", ZUUL build UUID $2"

download_dir="/var/tmp/mcom03-flash-download"
mkdir -p "$download_dir"
rm -rf "${download_dir:?}/"*

for file in "${files[@]}"; do
	log "Downloading $file"
	if ! run wget --quiet "$source/$file" -O "$download_dir/$file"; then
		fatal "Failed to download \"$source/$file\"."
	fi
done

cd "$download_dir"

if ! runv mcom03-flash --port /dev/ttyUSB0 flash-tl qspi0 "${files[@]}"; then
	fatal "Unable to flash device"
fi
if ! runv mcom03-flash --port /dev/ttyUSB0 erase qspi0 0x10000 --offset "$sbl_env_offset"; then
	fatal "Unable to erase SBL-Env offset"
fi

# mcom03-flash --port /dev/ttyUSB0 flash-tl qspi0 ecam03dm-bootrom.sbimg sbl-tl-mcom03-ecam03dm-r1.0.sbimg sbl-tl-otp.bin
