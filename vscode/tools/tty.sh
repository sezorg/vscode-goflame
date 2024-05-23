#!/bin/bash

if [[ $# -lt 1 ]]; then
	echo "Usage:"
	echo "  $0 <serial-port> [ <speed> [ <stty-options> ... ] ]"
	echo "  Example: $0 /dev/ttyUSB0 115200"
	echo "  Press Ctrl+Q to quit"
fi

set -e # Exit when any command fails

# Save settings of current terminal to restore later
original_settings="$(stty -g)"

# Kill background process and restore terminal when this shell exits
trap 'set +e; kill "$bgPid"; stty "$original_settings"' EXIT

# Remove serial port from parameter list, so only stty settings remain
port="$1"
shift

# Set up serial port, append all remaining parameters from command line
stty -F "$port" raw -echo "$@"

# Set current terminal to pass through everything except Ctrl+Q
# * "quit undef susp undef" will disable Ctrl+\ and Ctrl+Z handling
# * "isig intr ^Q" will make Ctrl+Q send SIGINT to this script
stty raw -echo isig intr ^Q quit undef susp undef

printf "Connecting to %s. Press Ctrl+Q to exit.\n\r# " "$port"

# Let cat read the serial port to the screen in the background
# Capture PID of background process so it is possible to terminate it
cat "$port" &
bgPid=$!

cat >"$port" # Redirect all keyboard input to serial port
