#!/bin/bash

BASE=$(realpath "$(dirname "$PWD/${BASH_SOURCE[0]}")")
IP=10.113.11.65

if [[ -f "$BASE/../../config.ini" ]]; then
	source "$BASE/../../config.ini"
	IP="$1"
fi

function log() {
	echo "$*"
}

function error() {
	echo "ERROR: $*"
}

function fatal() {
	error "$*"
	exit 1
}

function json_test() {
	local service method output status decoded
	service="$(dirname "$1")"
	method="$(basename -- "$1")"
	log "$IP: $service.$method()"
	output=$(python3 "$BASE/ipcam_request.py" -a $IP -s "$service" -c "$method" -l "$JSON" 2>&1)
	status=$(echo "$output" | grep "No route to host")
	if [[ "$status" != "" ]]; then
		fatal "IP $IP: No route to host."
	fi
	decoded=$(echo "$output" | jq 2>&1)
	status=$(echo "$decoded" | grep "parse error:")
	if [[ "$status" != "" ]]; then
		error "Malformed JSON response."
		error "$decoded"
		fatal "$output"
	fi
	echo "$output" | jq
}
