#!/usr/bin/env bash
#
# Copyright 2022 RnD Center "ELVEES", JSC
#
# SPDX-License-Identifier: GPLv3
#

set -euo pipefail

help() {
    log 'format-mmc.sh - Tool to partition, format and flash squashfs image'
    log
    log 'Usage: format-mmc.sh [options] <squashfs image>|- <device>|<image file>'
    log
    log 'Options'
    log '  -h   Print this help'
    log '  -d   Size of data partition in format size{K,M,G} (default: 256M)'
    log '  -s   Size of system partitions in format size{K,M,G} (default: 1G)'
    log '  -n   Omit data verification step'
    log
    log 'Example:'
    log '  format-mmc.sh -s 128M -d 1G rootfs.squashfs /dev/sdX'
    log '  cat rootfs.squashfs | format-mmc.sh [options] - /dev/sdX'
    log '  format-mmc.sh [options] - /dev/sdX <rootfs.squashfs'
    exit 1
}

log() {
    echo "$*" >/dev/stderr
}

log_n() {
    echo -n "$*" >/dev/stderr
}

error() {
    log "  **** Error: $*"
}

fatal() {
    error "$*"
    exit 1
}

silent() {
    eval "$* >/dev/null 2>&1 || true"
}

assert_removable() {
    local path info
    if ! path=$(udevadm info -q path -n "$1"); then
        fatal "Device '$1' does not exists."
    fi
    if ! info=$(udevadm info -a -p "$path"); then
        fatal "Device '$1' at '$path' is not valid device ID."
    fi
    if [[ "$(grep "ATTR{removable}==\"1\"" <<<"$info" || true)" == "" ]]; then
        fatal "Device '$1' does not seems to be a removable USB Flash or SD Card."
    fi
    REMOVABLE="/sys/block/$(basename -- "$1")/removable"
    if [[ ! -f "$REMOVABLE" ]]; then
        fatal "Device '$1' semms not mounted."
    fi
    if [[ "$(cat cat "$REMOVABLE" 2>/dev/null)" != "1" ]]; then
        fatal "Device '$1' does not seems to be a removable USB Flash or SD Card."
    fi
}

get_partition() {
    local prefix="" result
    [[ "$1" =~ [0-9]$ ]] && prefix=p
    result="$1$prefix$2"
    if [[ ! -b "$result" ]]; then
        fatal "Partition '$result' does not exist (not a block device)."
    fi
    echo "$result"
}

# NOTE: There's false positive here: dm-xxx, but who cares...
is_whole_disk() {
    test -e "/sys/block/${1##*/}"
}

cmd_exists() {
    hash "$1" 2>/dev/null
}

unmount() {
    if cmd_exists udisksctl; then
        silent udisksctl unmount -b "$1"
    elif cmd_exists systemd-umount; then
        silent systemd-umount "$1"
    else
        silent umount "$1"
    fi
}

unmount_all() {
    local device="$1" partitions
    partitions="$(fdisk -l "$device" | grep "^$device" | cut -f1 -d' ' || true)"
    mapfile -t partitions <<<"$partitions"
    local postfix=":"
    if [[ "${partitions[*]}" == "" ]]; then
        partitions=()
        postfix="."
    fi
    log "Unmount all partitions on '$device'$postfix"
    for partition in "${partitions[@]}"; do
        log_n "      * partition '$partition' - "
        unmount "$partition"
        silent rm -rf "$partition"
        silent wipefs --all --force "$partition"
        log "OK"
    done
    silent wipefs --all --force "$device"
    partprobe -s "$DEV"
}

filter_messages=(
    "Changes will remain in memory only"
    "Be careful before using the write command."
    "Could not delete partition "
    "Command (m for help)"
    "   p   primary"
    "   e   extended"
    "Select (default p)"
    "Syncing disks"
    "records in"
    "records out"
)
filter_pattern="$(printf "\n%s" "${filter_messages[@]}")"
filter_pattern="${filter_pattern:1}"

filter_output() {
    grep -v -e "$filter_pattern" -e '^[[:space:]]*$'
}

SYSTEM_SIZE="1G"
DATA_SIZE="256M"
SKIP_VERIFY=""

while getopts 'hnd:s:' opt; do
    case $opt in
    h) help ;;
    n) SKIP_VERIFY=true ;;
    d) DATA_SIZE="$OPTARG" ;;
    s) SYSTEM_SIZE="$OPTARG" ;;
    *) help ;;
    esac
done
shift $((OPTIND - 1))

[[ "$#" == "0" ]] && help
[[ "$#" != "2" ]] && (error "Incorrect number of arguments." && help)

SQFS="$1"
DEV_OR_FILE="$(realpath -s "$2")"

if [[ "$DEV_OR_FILE" == /dev/* ]] && [[ -b "$DEV_OR_FILE" ]]; then
    if [[ $EUID -ne 0 ]]; then
        fatal "This script must be run as root"
    fi
    DEV="$DEV_OR_FILE"
    assert_removable "$DEV"
elif [[ "$DEV_OR_FILE" != /dev/* ]]; then
    # For unknown reason fdisk can't re-read partition table of loop
    # device without root access after table written to disk (see 'w'
    # command in fdisk) and prints error:
    #
    #   Calling ioctl() to re-read partition table.
    #   Re-reading the partition table failed.: Permission denied
    #
    # TODO: Consider to use sfdisk as it has --no-reread option.
    if [[ $EUID -ne 0 ]]; then
        fatal "This script must be run as root"
    fi

    LOOP_DEV_LIST=()
    mapfile -t LOOP_DEV_LIST <<<"$(losetup -a | grep "$DEV_OR_FILE" | sed -e 's/:\s.*$//')"
    for LOOP_DEV in "${LOOP_DEV_LIST[@]}"; do
        [[ "$LOOP_DEV" == "" ]] && continue
        log "Removing suspicious/outdated loop device '${LOOP_DEV}'."
        losetup -d "${LOOP_DEV}"
    done

    log "Creating boot image in '$DEV_OR_FILE'..."
    {
        # Add to image 1MiB default offset of fdisk plus one additional sector
        dd if=/dev/zero bs=1049088 count=1
        dd if=/dev/zero bs="$SYSTEM_SIZE" count=1
        dd if=/dev/zero bs="$SYSTEM_SIZE" count=1
        dd if=/dev/zero bs="$DATA_SIZE" count=1
    } >"$DEV_OR_FILE" 2>/dev/null
    if ! losetup -fP "$DEV_OR_FILE"; then
        fatal "Failed to setup loop device on '$DEV_OR_FILE'."
    fi
    DEV=$(losetup -a | grep "$DEV_OR_FILE" | sed -e 's/:\s.*$//')
    log "Using loop device '$DEV' on '$DEV_OR_FILE'."
    # shellcheck disable=SC2064
    trap "echo \"Removing loopback device '$DEV'.\"; losetup -d \"$DEV\"" EXIT
else
    fatal "Parameter '$DEV_OR_FILE' should be either block device or regular file."
fi

[[ "$SQFS" == "-" || -r "$SQFS" ]] || fatal "'$SQFS' is not readable."
is_whole_disk "$DEV" || fatal "'$DEV' is not a disk device."
[[ -w "$DEV" ]] || fatal "'$DEV' is not writable."

# Real work starts here!

unmount_all "$DEV"

log "Partition '$DEV'..."
# 'data' (3rd) partition should be at least 128MiB in production
# By default it is set to 256M size for development purposes.
(
    fdisk --wipe always "$DEV" <<EOF
d
d
d
d

o
n
p


+${SYSTEM_SIZE}
n
p


+${SYSTEM_SIZE}
n
p


+${DATA_SIZE}
w
EOF
) 2>&1 | filter_output

partprobe -s "$DEV"
PART1=$(get_partition "$DEV" 1)
PART2=$(get_partition "$DEV" 2)
PART3=$(get_partition "$DEV" 3)
log "Waiting for '$PART1', '$PART2' and '$PART3'..."
COUNTER=30
while [ ! -b "$PART1" ] || [ ! -b "$PART2" ] || [ ! -b "$PART3" ]; do
    if [ "$COUNTER" -eq "0" ]; then
        fatal "Failed to wait for target partitions to appear in 30 seconds"
    fi
    COUNTER=$((COUNTER - 1))
    sleep 1
done
log "Devices are ready!"
TMPST="/tmp/format-mmc-status"
SQFS_SIZE=""
SQFS_MD5=""
if [[ "$SQFS" == "-" ]]; then
    log "Flashing '$PART1' and '$PART2' with STDIN:"
    log_n "      * partition '$PART1' - "
    if ! tee >(dd of="$PART1" conv=fdatasync bs=4M 2>"${TMPST}1") \
        >(dd of="$PART2" conv=fdatasync bs=4M 2>"${TMPST}2") \
        >(md5sum >"${TMPST}3") | wc -c >"${TMPST}4"; then
        log "FAIL"
        error <"${TMPST}1"
        error <"${TMPST}2"
        fatal "Failed to write partition '$partition'"
    fi
    log "OK"
    log "        $(filter_output <"${TMPST}1")"
    log "      * partition '$PART2' - OK"
    log "        $(filter_output <"${TMPST}2")"
    SQFS_MD5="$(cat "${TMPST}3")"
    SQFS_SIZE="$(cat "${TMPST}4")"
else
    log "Flashing '$PART1' and '$PART2' with '$SQFS':"
    flash_partition() {
        local partition="$1"
        log_n "      * partition '$partition' - "
        if ! status=$(dd if="$SQFS" of="$partition" conv=fdatasync bs=4M 2>&1); then
            log "FAIL"
            error "$status"
            fatal "Failed to flash partition '$partition'"
        fi
        log "OK"
        log "        $(filter_output <<<"$status")"
    }
    flash_partition "$PART1"
    flash_partition "$PART2"
    SQFS_SIZE=$(du -b "$SQFS" | cut -f1)
    SQFS_MD5="$(dd if="$SQFS" status=none | md5sum)"
fi
rm -f "${TMPST}1" "${TMPST}2" "${TMPST}3" "${TMPST}4"
log "Done, size $SQFS_SIZE bytes, MD5 ${SQFS_MD5:0:32}"

log "Format '$PART3' as EXT4 partition..."
mkfs.ext4 -F -L data "$PART3" | filter_output
sync

if [[ "$SKIP_VERIFY" == "" ]]; then
    verify_partition() {
        local partition="$1" partition_md5
        log_n "      * partition '$partition' - "
        if ! partition_md5=$(dd if="$partition" bs="$SQFS_SIZE" count="1" iflag=direct 2>"${TMPST}1" | md5sum); then
            log "FAILED"
            error "$(cat "${TMPST}1")"
            fatal "Failed to read partition '$partition' data."
        fi
        if [[ "$partition_md5" != "$SQFS_MD5" ]]; then
            log "FAILED"
            error "Failed to verify '$partition' MD5."
            fatal "Calculated ${partition_md5:0:32} != expected ${SQFS_MD5:0:32}"
        fi
        log "OK"
        log "        $(filter_output <"${TMPST}1")"
    }
    log "Verifying '$PART1' and '$PART2':"
    verify_partition "$PART1"
    verify_partition "$PART2"
fi
log "Successfully completed."
