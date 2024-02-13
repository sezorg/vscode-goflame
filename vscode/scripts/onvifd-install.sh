#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Onvifd installation script.

set -euo pipefail

TITLE="onvifd"
SERVICE="$TITLE.service"
SOURCE="/usr/bin/${TITLE}_debug"
TARGET="/usr/bin/$TITLE"
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "This will install debug version of $TITLE as main service."
read -r -p "Do you want to continue? (Y/n): " answer

if [[ "$answer" == "" ]] || [[ "$answer" =~ ^[Yy]$ ]]; then
	if [[ ! -f "$SOURCE" ]]; then
		echo "$RED ***ERROR: File '$SOURCE' does not exist. Aborting.$NC"
		exit 1
	fi
elif [[ "$answer" =~ ^[Nn]$ ]]; then
	echo "Aborting install."
	exit 0
else
	echo "$RED ***ERROR: Invalid input. Please enter 'y' for yes or 'n' for no.$NC"
	exit 1
fi

if [[ ! -f "$TARGET.bak" ]]; then
	echo "Backuping up previous $TITLE to '$TARGET.bak'"
	cp "$TARGET" "$TARGET.bak"
else
	echo "Backup '$TARGET.bak' already exists. Skipping."
fi

echo "Stopping '$SERVICE'"
systemctl stop "$SERVICE"
echo "Copying '$SOURCE' to '$TARGET'"
cp "$SOURCE" "$TARGET"
sync
echo "Enabling & restarting '$TITLE' service"
systemctl unmask "$SERVICE"
systemctl enable "$SERVICE"
systemctl restart "$SERVICE"
systemctl status "$SERVICE" --no-pager -l --lines=1
echo "Exit status: $?"
