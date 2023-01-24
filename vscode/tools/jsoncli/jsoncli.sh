#!/bin/bash
# Copyright 2022 RnD Center "ELVEES", JSC
#
# ONVIF Infrared Filter & Light test script.

set -euo pipefail

IP_ADDR=""
VIDEO_SOURCE="src"

RUN_FLAGS=()
COMMANDS=()

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SCRIPT_NAME=$(basename -- "${0}")
SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
if [ -f "${SCRIPT_DIR}/config.ini" ]; then
  source "${SCRIPT_DIR}/config.ini"
fi

# Execute something like: 
# $ source ./test.sh 
# to apply aliases to current console instance. 
TESTS_SH_SCRIPT="${SCRIPT_PATH}"
alias if_on='${TESTS_SH_SCRIPT} if_on'
alias if_off='${TESTS_SH_SCRIPT} if_off'
alias if_auto='${TESTS_SH_SCRIPT} if_auto'
alias if_get='${TESTS_SH_SCRIPT} if_get'
alias il_on='${TESTS_SH_SCRIPT} il_on'
alias il_off='${TESTS_SH_SCRIPT} il_off'
alias il_get='${TESTS_SH_SCRIPT} il_get' 

while [[ $# -gt 0 ]]; do
  case ${1} in
    v|verbose)
      RUN_FLAGS+=("-v")
      shift # past value
      ;;
    ip)
      IP_ADDR="${2}"
      shift # past argument
      shift # past value
      ;;
    *)
      if [ -f "${SCRIPT_DIR}/templates/${1}.json" ]; then
        COMMANDS+=("execute_file_request \"${SCRIPT_DIR}/templates/${1}.json\"")
        shift # past value
      else
        echo "Unknown option: ${1}"
        exit 1
      fi
      ;;
  esac
done

function unused() {
  return 0 
}

#
# Implementation.
#

function execute_json_request() {
  local json="${1}"
  json="${json/(VIDEO_SOURCE)/"${VIDEO_SOURCE}"}"
  json="${IP_ADDR}/${json}"
  echo python3 "${SCRIPT_DIR}/jsonrq.py" "${json}"
  python3 "${SCRIPT_DIR}/jsonrq.py" "${json}" "${RUN_FLAGS[@]}"
}

function execute_file_request() {
  execute_json_request "$(cat "${1}")"
}

REQUEST_JSON=""

function peek_request_json() {
  local template="${1}"
  local compound="${template}_${2}"
  set +u
  REQUEST_JSON=${!compound}
  set -u
  if [ "${REQUEST_JSON}" == "" ]; then
    REQUEST_JSON="${!template}"
  fi
} 

function execute_if_mode() {
  echo "execute execute_if_mode ${1}"
  peek_request_json "JSON_IF_MODE" "${1}"
  execute_json_request "${REQUEST_JSON/(IF_MODE)/"${1}"}"
}

function execute_if_get() {
  echo "execute execute_if_get"
  execute_json_request "${JSON_IF_GET}"
}

function execute_il_mode() {
  echo "execute execute_il_mode ${1}"
}

function execute_il_get() {
  echo "execute execute_il_get"
}

for command in "${COMMANDS[@]}"; do
  echo "${command}"
  eval "${command}"
done

