#!/usr/bin/env bash
#
# Copyright 2024 RnD Center "ELVEES", JSC
#
# SPDX-License-Identifier: GPLv3
#

set -euo pipefail

help() {
    echo "format-mmc.sh - Tool to partition, format and flash *.swu file"
    echo
    echo "Usage: format-mmc.sh [options] [<*.swu file>|-] <device>"
    echo
    echo "Options"
    echo "  -c   Create partition table only (-n option will be ignored)"
    echo "  -d   Size of data partition in format size{K,M,G} (default: 256M)"
    echo "  -n   Do not create partition table, just write *.swu file content"
    echo "  -r   Create recovery partition"
    echo "  -s   Size of system or recovery partitions in format size{K,M,G} (default: 1G)"
    echo "  -h   Print this help"
    echo
    echo "Example:"
    echo "  1) In case of system firmware from scratch, we create 3 partitions"
    echo "     (2 SYSTEMS and 1 DATA) on SD/eMMC and write a system firmware:"
    echo "         format-mmc.sh <*.swu file> /dev/sdX"
    echo "         cat <*.swu file> | format-mmc.sh - /dev/sdX"
    echo "  2) In case of recovery firmware from scratch, we create 4 partitions"
    echo "     (2 SYSTEM, 1 DATA, 1 RECOVERY) on SD/eMMC and write a recovery firmware:"
    echo "         format-mmc.sh -r <recovery *.swu file> /dev/sdX"
    echo "         cat <recovery *.swu file> | format-mmc.sh -r - /dev/sdX"
    echo "  3) If case #2 has already been applied, there is no need to re-format the partitions."
    echo "     It is only required to write a system partitions:"
    echo "         cat <*.swu file> | format-mmc.sh -n - /dev/sdX"
    echo "         format-mmc.sh -n <*.swu file> /dev/sdX"
    echo "  4) Also we can create partition table only:"
    echo "         format-mmc.sh -c /dev/sdX"
    echo "         format-mmc.sh -c -r /dev/sdX"
    echo "  5) It is possible to change default size of partitions:"
    echo "         format-mmc.sh -c -s 1G -d 128M /dev/sdX"
    echo "         format-mmc.sh -c -s 1G -r /dev/sdX"
    echo "         format-mmc.sh -s 1G -d 128M <*.swu file> /dev/sdX"
    echo "         format-mmc.sh -s 1G -r <recovery *.swu file> /dev/sdX"
    echo
}

# NOTE: There's false positive here: dm-xxx, but who cares...
iswholedisk() {
    test -e "/sys/block/${1##*/}"
}

getdevwithpartprefix() {
    local partprefix=
    [[ "$1" =~ [0-9]$ ]] && partprefix=p
    echo "$1$partprefix"
}

getpart() {
    local devwithpartprefix=
    devwithpartprefix=$(getdevwithpartprefix "$1")
    echo "$devwithpartprefix$2"
}

cmdexists() {
    hash "$1" 2>/dev/null
}

unmount() {
    if cmdexists udisksctl; then
        udisksctl unmount -b "$1"
    elif cmdexists systemd-umount; then
        systemd-umount "$1"
    else
        umount "$1"
    fi
}

unmountall() {
    local devwithpartprefix=
    devwithpartprefix=$(getdevwithpartprefix "$1")
    # shellcheck disable=SC2013
    for i in $(grep -F "$devwithpartprefix" /etc/mtab | cut -f1 -d' '); do
        unmount "$i"
    done
}

align() {
    local NUMBER=$1
    local a=$(( NUMBER + ALIGNMENT - 1 ))
    local b=$(( ALIGNMENT - 1 ))
    echo $(( a & ~b ))
}

make_partition_table() {
    partprobe

    echo "Unmount all partitions on '$DEV'..."
    unmountall "$DEV"

    if [[ "$MAKE_PART_TABLE" == "yes" ]]; then
        echo "Partition '$DEV'..."

        SYSTEM_SIZE=$(echo "$SYSTEM_SIZE" | numfmt --from=iec)
        DATA_SIZE=$(echo "$DATA_SIZE" | numfmt --from=iec)

        local BLOCK_SIZE=
        BLOCK_SIZE=$(blockdev --getpbsz "$DEV")

        local SYSTEM_SECTORS=$(( (SYSTEM_SIZE + BLOCK_SIZE - 1) / BLOCK_SIZE ))
        local DATA_SECTORS=$(( (DATA_SIZE + BLOCK_SIZE - 1) / BLOCK_SIZE ))

        local START=
        local END=

        parted -s "$DEV" mktable gpt

        START=$ALIGNMENT
        END=$(align $(( START + SYSTEM_SECTORS )))
        parted -s -a optimal "$DEV" unit S mkpart systema "$START" $(( END - 1 ))

        START=$END
        END=$(align $(( START + SYSTEM_SECTORS )))
        parted -s -a optimal "$DEV" unit S mkpart systemb "$START" $(( END - 1 ))

        START=$END
        END=$(align $(( START + DATA_SECTORS )))
        parted -s -a optimal "$DEV" unit S mkpart data "$START" $(( END - 1 ))

        if [[ "$RECOVERY" == "yes" ]]; then
            MAX_SECTORS=$(blockdev --getsz "$DEV")
            START=$(align $(( MAX_SECTORS - SYSTEM_SECTORS )))
            parted -s -a optimal "$DEV" unit S mkpart recovery "$START" 100%
        fi
    fi
}

error() {
    echo "Error: $*" >&2
    help
    exit 1
}

# 'data' (3rd) partition should be at least 128MiB in production
# By default it is set to 256M size for development purposes.
DATA_SIZE="256M"
MAKE_PART_TABLE="yes"
PART_TABLE_ONLY=
RECOVERY=
SYSTEM_SIZE="1G"
ALIGNMENT=2048

[[ "$EUID" != "0" ]] && error "This script must be run as root"

while getopts 'cd:hnrs:' opt; do
    case $opt in
        c) PART_TABLE_ONLY="yes" ;;
        d) DATA_SIZE="$OPTARG" ;;
        h) help; exit 0 ;;
        n) [[ "$PART_TABLE_ONLY" == "yes" ]] || MAKE_PART_TABLE= ;;
        r) RECOVERY="yes" ;;
        s) SYSTEM_SIZE="$OPTARG" ;;
        *) help; exit 1 ;;
    esac
done
shift $((OPTIND-1))


if [[ "$PART_TABLE_ONLY" == "yes" ]]; then
    [[ "$#" -eq 1 ]] || error "Incorrect number of command line arguments"

    DEV="$(realpath -s "$1")"
else
    [[ "$#" -eq 2 ]] || error "Incorrect number of command line arguments"

    SWUFILE="$1"
    DEV="$(realpath -s "$2")"

    [[ "$SWUFILE" == "-" || -r "$SWUFILE" ]] || error "'$SWUFILE' is not readable"
fi

iswholedisk "$DEV" || error "'$DEV' is not a disk"
[[ -w "$DEV" ]] || error "'$DEV' is not writable"

# Real work starts here!
make_partition_table

[[ "$PART_TABLE_ONLY" == "yes" ]] && exit 0

if [[ "$RECOVERY" != "yes" ]]; then
    PART1=$(getpart "$DEV" 1)
    PART2=$(getpart "$DEV" 2)
    PART3=$(getpart "$DEV" 3)

    echo "Waiting for '$PART1', '$PART2' and '$PART3'..."
    COUNTER=30
    while [ ! -b "$PART1" ] || [ ! -b "$PART2" ] || [ ! -b "$PART3" ]; do
        if [ "$COUNTER" -eq "0" ]; then
            echo "Failed to wait for target partitions to appear in 30 seconds"
            exit 1
        fi
        COUNTER=$((COUNTER-1))
        sleep 1;
    done
    echo "Devices are ready!"

    echo "Flashing '$PART1' and '$PART2' with file '$SWUFILE'..."
    if [[ "$SWUFILE" == "-" ]]; then
        cpio --extract --to-stdout rootfs.squashfs | \
            tee >(dd of="$PART1" conv=fdatasync bs=4M &> /dev/null) | \
                dd of="$PART2" conv=fdatasync bs=4M
    else
        cpio --extract --to-stdout rootfs.squashfs < "$SWUFILE" | \
            tee >(dd of="$PART1" conv=fdatasync bs=4M &> /dev/null) | \
                dd of="$PART2" conv=fdatasync bs=4M
    fi

    echo "Format '$PART3'..."
    mkfs.ext4 -F -L data "$PART3"
else
    PART4=$(getpart "$DEV" 4)

    echo "Waiting for '$PART4'..."
    COUNTER=30
    while [ ! -b "$PART4" ]; do
        if [ "$COUNTER" -eq "0" ]; then
            echo "Failed to wait for target partition to appear in 30 seconds"
            exit 1
        fi
        COUNTER=$((COUNTER-1))
        sleep 1;
    done
    echo "Devices are ready!"

    echo "Flashing '$PART4' with file '$SWUFILE'..."
    if [[ "$SWUFILE" == "-" ]]; then
        cpio --extract --to-stdout rootfs.squashfs | \
            dd of="$PART4" conv=fdatasync bs=4M
    else
        cpio --extract --to-stdout rootfs.squashfs < "$SWUFILE" | \
            dd of="$PART4" conv=fdatasync bs=4M
    fi
fi
