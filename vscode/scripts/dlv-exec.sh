#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Execute binary on the targets wich does not support Delve debugging.

if [[ "$instance_guard" == "" ]]; then
	export instance_guard="root"
	while true; do
		if [[ -f "$0" ]]; then
			"$0"
		else
			sleep 1
		fi
	done
fi

set -euo pipefail
#set -x

DLOOP_ENABLE_FILE="/tmp/dlv-loop-enable"
DLOOP_RESTART_FILE="/tmp/dlv-loop-restart"

RED=$(printf "\e[31m")
GREEN=$(printf "\e[32m")
YELLOW=$(printf "\e[33m")
BLUE=$(printf "\e[34m")
GRAY=$(printf "\e[90m")
NC=$(printf "\e[0m")

function unused() { :; }
unused "$RED" "$GREEN" "$YELLOW" "$BLUE" "$GRAY" "$NC"

PATTERN="TARGET_BINARY"
EXE_BINARY_PATH="[[TARGET_BINARY_PATH]]"
EXE_BINARY_ARGS=([[TARGET_BINARY_ARGS]])
if [[ "${EXE_BINARY_PATH}" == "[[$PATTERN]]" ]]; then
	echo "${RED}Target binary path is not set. Do not run this script directly.${NC}"
	exit "1"
fi

function cleanup() {
	local filename processes is_bash
	filename=$(basename -- "${EXE_BINARY_PATH}")
	processes=$(ps -a)
	set +e
	running=$(grep "${filename}" <<<"${processes}")
	is_bash=$(grep "bash" <<<"${running}")
	if [[ "$running" != "" ]] && [[ "${is_bash}" == "" ]]; then
		echo "Terminating ${EXE_BINARY_PATH}..."
		killall "${filename}" >/dev/null 2>&1
	fi
	set -e
}

trap cleanup EXIT

function digest() {
	if [[ -f "${1}" ]]; then
		echo "$(md5sum "${1}")$(date -r "${1}" "+%m-%d-%Y %H:%M:%S" 2>/dev/null)" ###
	else
		echo "no-file"
	fi
}

function seltest() {
	s2=$(digest "$0")
	if [[ "${s1}" != "${s2}" ]]; then
		echo "${RED}WARNING: The script has been updated via external upload.${NC}"
		echo "${RED}WARNING: Exiting.... Please restart this script.${NC}"
		exit 1
	fi
}

s1=$(digest "$0")
first_time_run="1"
additional_sleep=""
while true; do

	if [[ ! -f "${DLOOP_ENABLE_FILE}" ]]; then
		additional_sleep="1"
		echo "${YELLOW}The device to be debugged has been rebooted and is now in a non-determined state.${NC}"
		echo "${YELLOW}Please run ${BLUE}\"Go: Build Workspace\"${YELLOW} befor continue. Waiting for completion...${NC}"
		while [[ ! -f "${DLOOP_ENABLE_FILE}" ]]; do
			seltest
			sleep 1
		done
	fi

	if [[ "${first_time_run}" != "" ]]; then
		first_time_run=""
		echo "Beginning ${EXE_BINARY_PATH} execution loop..."
	fi

	if [[ ! -f "${DLOOP_RESTART_FILE}" ]]; then
		echo "Waiting for application to be started (Run/Start Debugging)..."
		while [[ ! -f "${DLOOP_RESTART_FILE}" ]]; do
			seltest
			sleep 1
		done
	fi

	if [[ ! -f "${EXE_BINARY_PATH}" ]]; then
		additional_sleep="1"
		echo "${YELLOW}Unable to run application: target binary file ${EXE_BINARY_PATH} not found.${NC}"
		echo "${YELLOW}Please run ${BLUE}\"Go: Build Workspace\"${YELLOW} befor continue. Waiting for completion...${NC}"
		while [[ ! -f "${EXE_BINARY_PATH}" ]]; do
			seltest
			sleep 1
		done
	fi

	if [[ "${additional_sleep}" != "" ]]; then
		additional_sleep=""
		sleep 2
		continue
	fi

	t1=$(digest "${DLOOP_RESTART_FILE}")
	m1=$(digest "${EXE_BINARY_PATH}")
	status=$?
	if [[ $status -ne 0 ]]; then
		sleep 1
		continue
	fi

	cleanup
	echo "Starting ${EXE_BINARY_PATH}..."
	exec "${EXE_BINARY_PATH}" "${EXE_BINARY_ARGS[@]}" &

	while true; do
		seltest
		sleep 1
		t2=$(digest "${DLOOP_RESTART_FILE}")
		m2=$(digest "${EXE_BINARY_PATH}")
		if [[ "$t1" != "$t2" ]] || [[ "$m1" != "$m2" ]]; then
			break
		fi
	done
	cleanup

	echo " " #
	echo " "
	echo " "
done
