#!/usr/bin/env bash
# Copyright 2024 RnD Center "ELVEES", JSC
#
# Prepare debugging environment on x86_64 platform.
#
# Log messages are stored into file:///var/tmp/goflame/go-wrapper.log

set -euo pipefail

TARGET_ARCH="host"

# Include Golang environment
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
source "$SCRIPT_DIR/go-runtime.sh"

XECHO_ENABLED=true
xcp "init/onvifd.conf.in" ".vscode/launch/onvifd.conf"
xcp "init/action-engine.toml" ".vscode/launch/lib/onvifd/action-engine.toml"
xcp "init/devicedesc.tmpl" ".vscode/launch/lib/onvifd/devicedesc.tmpl"
xcp "init/dot1x.toml" ".vscode/launch/lib/onvifd/dot1x.toml"
xcp "init/inadyn.tmpl" ".vscode/launch/lib/onvifd/inadyn.tmpl"
xcp "init/ipcam.tmpl" ".vscode/launch/lib/onvifd/ipcam.tmpl"
xrm ".vscode/launch/lib/onvifd/state.toml"
xcp "init/timesyncd-static.conf" ".vscode/launch/lib/onvifd/timesyncd-static.conf"
xcp "init/users.toml" ".vscode/launch/lib/onvifd/users.toml"
xcp "init/wpa_supplicant.tmpl" ".vscode/launch/lib/onvifd/wpa_supplicant.tmpl"

TARGET_BUILD_GOFLAGS+=(
	"-C" "$PWD"
	"-o" "./onvifd"
)

TARGET_BUILD_LDFLAGS=(
	"-X main.currentVersion=custom"
	"-X main.sysConfDir=./.vscode/launch"
	"-X main.localStateDir=./.vscode/launch"
)

xbuild_project
