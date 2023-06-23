#!/usr/bin/env bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# Execute binary on the targets wich does not support Delve debugging.

if [[ "$instance_guard" == "" ]]; then
	export instance_guard="root"
	while true; do
		if [[ -f "$0" ]]; then
			"$0"
			status="$?"
			if [[ "${status}" != "155" ]]; then
				exit "${status}"
			fi
		else
			usleep 500000
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

function log() {
	echo "${BLUE}|| $*${NC}"
}

function unused() { :; }
unused "$RED" "$GREEN" "$YELLOW" "$BLUE" "$GRAY" "$NC"

EXE_BINARY_PATH="__TARGET_BINARY_PATH__"
EXE_BINARY_ARGS=(__TARGET_BINARY_ARGS__)

PATTERN="TARGET_BINARY_PATH"
if [[ "$EXE_BINARY_PATH" == "__${PATTERN}__" ]]; then
	log "${RED}Target binary path is not set. Do not run this script directly.${NC}"
	exit "1"
fi

EXE_PROCESS_PID=""

function cleanup() {
	set +e
	local processes running
	processes=$(ps -a)
	running=$(awk "{if(\$3==\"${EXE_BINARY_PATH}\"){print \$3;exit}}" <<<"${processes}")
	if [[ "$running" != "" ]]; then
		#log "Terminating ${EXE_BINARY_PATH}..."
		killall "$(basename -- "${EXE_BINARY_PATH}")" >/dev/null 2>&1
	fi
	if [[ "${EXE_PROCESS_PID}" != "" ]]; then
		kill "${EXE_PROCESS_PID}" >/dev/null 2>&1
		wait "${EXE_PROCESS_PID}" >/dev/null 2>&1
		EXE_PROCESS_PID=""
	fi
	set -e
}

trap cleanup EXIT

function digest() {
	if [[ -f "${1}" ]]; then
		date -r "${1}" "+%m-%d-%Y %H:%M:%S"
	else
		echo "no-file"
	fi
}

function seltest() {
	s2=$(digest "$0")
	if [[ "${s1}" != "${s2}" ]]; then
		log "${YELLOW}INFORMATION: The script has been updated via external upload. Restarting...${NC}"
		exit 155
	fi
}

s1=$(digest "$0")
first_time_run="1"
additional_sleep=""
while true; do
	if [[ "${first_time_run}" == "" ]]; then
		log " "
		log " "
		log " "
	fi

	if [[ ! -f "${DLOOP_ENABLE_FILE}" ]]; then
		additional_sleep="1"
		log "${YELLOW}The device to be debugged has been rebooted and is now in a non-determined state.${NC}"
		log "${YELLOW}Please run ${BLUE}\"Go: Build Workspace\"${YELLOW} befor continue. Waiting for completion...${NC}"
		while [[ ! -f "${DLOOP_ENABLE_FILE}" ]]; do
			seltest
			usleep 500000
		done
	fi

	if [[ "${first_time_run}" != "" ]]; then
		first_time_run=""
		log "Beginning ${EXE_BINARY_PATH} execution loop..."
	fi

	if [[ ! -f "${DLOOP_RESTART_FILE}" ]]; then
		log "Waiting for application to be started (Run/Start Debugging)..."
		while [[ ! -f "${DLOOP_RESTART_FILE}" ]]; do
			seltest
			usleep 100000
		done
	fi

	if [[ ! -f "${EXE_BINARY_PATH}" ]]; then
		additional_sleep="1"
		log "${YELLOW}Unable to run application: target binary file ${EXE_BINARY_PATH} not found.${NC}"
		log "${YELLOW}Please run ${BLUE}\"Go: Build Workspace\"${YELLOW} befor continue. Waiting for completion...${NC}"
		while [[ ! -f "${EXE_BINARY_PATH}" ]]; do
			seltest
			usleep 500000
		done
	fi

	if [[ "${additional_sleep}" != "" ]]; then
		additional_sleep=""
		usleep 2000000
		continue
	fi

	while [[ -f "${EXE_BINARY_PATH}" ]] && [[ ! -r "${EXE_BINARY_PATH}" ]]; do
		seltest
		usleep 100000
	done

	t1=$(digest "${DLOOP_RESTART_FILE}")
	m1=$(digest "${EXE_BINARY_PATH}")
	status=$?
	if [[ $status -ne 0 ]]; then
		usleep 1000000
		continue
	fi

	cleanup
	log "Starting ${EXE_BINARY_PATH}..."
	exec "${EXE_BINARY_PATH}" "${EXE_BINARY_ARGS[@]}" &
	EXE_PROCESS_PID="$!"

	while true; do
		seltest
		usleep 100000
		if [[ "$t1" != "$(digest "${DLOOP_RESTART_FILE}")" ]] ||
			[[ "$m1" != "$(digest "${EXE_BINARY_PATH}")" ]]; then
			break
		fi
	done
	cleanup

done
