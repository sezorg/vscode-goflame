#!/bin/bash

set -euo pipefail

# --------------------------------------------------------------------------------------------------

export https_proxy=http://proxy.elvees.com:3128
export http_proxy=http://proxy.elvees.com:3128
export ftp_proxy=http://proxy.elvees.com:3128
export no_proxy=127.0.0.1,localhost,elvees.com

export BR2_PRIMARY_SITE=http://callisto.elvees.com/mirror/buildroot
export PYTHONUSERBASE=$HOME/.python
export PATH=$PYTHONUSERBASE/bin:$PATH

export GOPROXY=http://athens.elvees.com,https://proxy.golang.org,direct

# --------------------------------------------------------------------------------------------------

p_time_started="$(date +%s.%N)"
trap exit_trap EXIT

function exit_trap() {
	local end_time
	end_time="$(date +%s.%N)"
	format_time "$p_time_started" "$end_time" "Total runtime: " "\n"
	return 0
}

function format_time() {
	local from="$1" to="$2" prefix="$3" postfix="$4"
	local time days days_frac hours hours_frac mins secs
	time=$(echo "$to - $from" | bc)
	days=$(echo "$time/86400" | bc)
	days_frac=$(echo "$time-86400*$days" | bc)
	hours=$(echo "$days_frac/3600" | bc)
	hours_frac=$(echo "$days_frac-3600*$hours" | bc)
	mins=$(echo "$hours_frac/60" | bc)
	secs=$(echo "$hours_frac-60*$mins" | bc)
	if is_ne "$days" "0"; then
		printf "$prefix%dd %02dh %02dm %02.3fs$postfix" "$days" "$hours" "$mins" "$secs"
	elif is_ne "$hours" "0"; then
		printf "$prefix%dh %02dm %02.3fs$postfix" "$hours" "$mins" "$secs"
	elif is_ne "$mins" "0"; then
		printf "$prefix%dm %02.3fs$postfix" "$mins" "$secs"
	else
		printf "$prefix%02.3fs$postfix" "$secs"
	fi
}

function log() {
	echo >&2 "$*"
}

function error() {
	log "   *** ERROR: $*"
}

function fatal() {
	error "$*"
	exit 1
}

function is_true() {
	[[ "${1^^}" =~ ^(1|T|TRUE|Y|YES)$ ]]
}

function is_false() {
	[[ ! "${1^^}" =~ ^(1|T|TRUE|Y|YES)$ ]]
}

function is_set() {
	[[ "$1" != "" ]]
}

function is_unset() {
	[[ "$1" == "" ]]
}

function is_eq() {
	[[ "$1" == "$2" ]]
}

function is_ne() {
	[[ "$1" != "$2" ]]
}

function help() {
	log "Usage: $(basename "$0") <flags> <devices> [make-targets]"
	log "Flags:"
	log "    image           Build complete image & software update packages"
	log "    tools           Build toolchains and libraries"
	log "    -c | --clean    Start build from scratch"
	log "    -d | --dry-run  Dry dun. Download only, not build"
	log "    -h | --help     Print this help screen & exit"
	log "    -h | --help     Print this help screen & exit"
	log "Devices:"
	log "    ecam02          ECAM02 compatible devices & boards"
	log "    ecam03          ECAM03 compatible devices & boards"
	exit 1
}

if [[ "$#" == "0" ]]; then
	error "No arguments specified."
	help
fi

p_build_ecam02=false
p_build_ecam03=false
p_build_image=false
p_build_tools=false
p_clean_build=false
p_dry_run_build=false
while [[ "$#" != "0" ]]; do
	case "$1" in
	ecam02)
		p_build_ecam02=true
		shift 1
		;;
	ecam03)
		p_build_ecam03=true
		shift 1
		;;
	image)
		p_build_image=true
		shift 1
		;;
	tools)
		p_build_tools=true
		shift 1
		;;
	-c | --clean)
		p_clean_build=true
		shift 1
		;;
	-d | --dry-run)
		p_dry_run_build=true
		shift 1
		;;
	-h | --help)
		help
		;;
	*)
		break
		;;
	esac
done

p_build_targets=()
if [[ "$#" != "0" ]]; then
	p_build_targets=("$@")
fi

p_build_all_devices=("ecam02" "ecam03")
p_build_devices=()
if is_true "$p_build_ecam02"; then
	p_build_devices+=("ecam02")
fi
if is_true "$p_build_ecam03"; then
	p_build_devices+=("ecam03")
fi
if is_eq "${p_build_devices[*]}" ""; then
	error "No devices specified (ecam02/ecam03/...etc)."
	help
fi

p_build_types=()
p_build_all_types=("buildroot" "toolchain")
if is_true "$p_build_image"; then
	p_build_types+=("buildroot")
fi
if is_true "$p_build_tools"; then
	p_build_types+=("toolchain")
fi
if is_eq "${p_build_types[*]}" ""; then
	error "No build types specified (image/tools/...etc)."
	help
fi

p_current_pwd="$PWD"
p_environment="$(mktemp /tmp/buildroot-env.XXXXXXXXX)"

for p_build_device in "${p_build_devices[@]}"; do
	for p_build_type in "${p_build_types[@]}"; do

		cd "$p_current_pwd"

		p_gerrit_source=""
		p_toolchain_make_targets=()
		case "$p_build_device" in
		ecam02)
			p_gerrit_source="mcom02/ecam02"
			p_toolchain_make_targets=(host-go libxml2 onvifd)
			;;
		ecam03)
			p_gerrit_source="ecam03/buildroot"
			p_toolchain_make_targets=(host-go delve libxml2 onvifd)
			;;
		*)
			fatal "Unknown or unsupported build device '$p_build_device'."
			;;
		esac

		p_build_make_targets=("${p_build_targets[@]}")
		if is_eq "${p_build_make_targets[*]}" ""; then
			if is_eq "$p_build_type" "toolchain"; then
				p_build_make_targets=("${p_toolchain_make_targets[@]}")
			else
				p_build_make_targets=("all")
			fi
		fi

		p_build_directory="$p_build_type/${p_build_device}"

		p_message="Building $p_build_type for $p_build_device, make [${p_build_make_targets[*]}]"
		if is_true "$p_clean_build"; then
			p_message="$p_message, clean build"
		fi
		if is_true "$p_dry_run_build"; then
			p_message="$p_message, dry-run"
		fi
		log "$p_message."

		if is_true "$p_clean_build"; then
			rm -rf "${p_build_directory:?}"
		fi

		echo "#"
		echo "# cloning ssh://$USER@gerrit.elvees.com:29418/$p_gerrit_source"
		echo "#"
		if [[ ! -d "$p_build_directory" ]]; then
			mkdir -p "$p_build_directory"
			git clone "ssh://$USER@gerrit.elvees.com:29418/$p_gerrit_source" "$p_build_directory"
			scp -p -P 29418 "$USER@gerrit.elvees.com:hooks/commit-msg" "$p_build_directory/.git/hooks/"
		fi

		cd "$p_build_directory" || fatal "Failed to enter build directory '$p_build_directory'"
		git submodule init
		git submodule update --recursive
		git pull
		git pull --recurse-submodules

		git reset --hard
		git submodule foreach --recursive git reset --hard
		git submodule update --init --recursive

		# Создание dbg.fragment
		p_fragment_name="./external-ipcam/$p_build_device-fragments/dbg.fragment"
		echo "#"
		echo "# creating $p_fragment_name"
		echo "#"
		cat <<EOF >"$p_fragment_name"
BR2_PACKAGE_DELVE=y
BR2_PACKAGE_PPROF=y
BR2_PACKAGE_MOSH=y
BR2_PACKAGE_DSP_THERMO_TESTS=n
BR2_PACKAGE_ONVIFD_SYSPARTITIONS=5
#BR2_PACKAGE_PYTHON_IPCAM_TOOLS=n
BR2_PACKAGE_NGINX_HTTP_DAV_MODULE=y
BR2_PACKAGE_NGINX_UPLOAD=y
BR2_JLEVEL=$(nproc)
BR2_CCACHE=y
BR2_PACKAGE_IGD2_FOR_LINUX=y
BR2_PACKAGE_SSDP_RESPONDER=y
BR2_PACKAGE_NANO=y
EOF

		# Копируем zoverlay в buildroot
		echo "#"
		echo "# merging overlay into buildroot"
		echo "#"
		p_overlay_dir="zoverlay"
		p_overlay_paths=(
			"common/buildroot"
			"(DEVICE)/buildroot"
			"(DEVICE)_(TYPE)/buildroot"
			"(TYPE)/buildroot"
			"sources/(DEVICE)"
		)
		for p_overlay_device in "${p_build_all_devices[@]}"; do
			for p_overlay_type in "${p_build_all_types[@]}"; do
				for p_overlay_path in "${p_overlay_paths[@]}"; do
					p_overlay_path=${p_overlay_path//"(DEVICE)"/$p_overlay_device}
					p_overlay_path=${p_overlay_path//"(TYPE)"/$p_overlay_type}
					if [[ -d "$p_current_pwd/$p_overlay_path" ]]; then
						echo "Creating overlay path: $p_overlay_path"
						mkdir -p "$p_current_pwd/$p_overlay_path"
					fi
				done
			done
		done

		p_prefix_paths=(
			"common"
			"$p_build_device"
			"${p_build_device}_${p_build_type}"
			"${p_build_type}"
		)
		for p_overlay in "${p_prefix_paths[@]}"; do
			p_overlay_path="$p_current_pwd/$p_overlay_dir/$p_overlay"

			if [[ -d "$p_overlay_path" ]]; then
				find "$p_overlay_path" -name ".cleanup" -print0 |
					while IFS= read -r -d '' line; do
						p_cleanup_path="${line#"$p_overlay_path"}"
						p_cleanup_path="$PWD/${p_cleanup_path%".cleanup"}"
						echo "--- cleaning ${p_cleanup_path:?}/"*
						rm -rfv "${p_cleanup_path:?}/"*
					done
				echo "--- copying $p_overlay_path -> $PWD/"
				cp -arfv "$p_overlay_path/." "$PWD/."
			fi
		done

		# Копируем local.mk в buildroot
		if [[ -f "$p_current_pwd/local.mk" ]]; then
			cp "$p_current_pwd/local.mk" "./buildroot/"
		fi

		function append_source() {
			local name="$1" target="$2"
			local directory="$p_current_pwd/$p_overlay_dir/sources/$p_build_device/$target/git"
			if [[ -d "$directory" ]]; then
				echo "--- Fetching Git $directory"
				git -C "$directory" fetch
				echo "--- Pulling Git $directory"
				branch="$(git -C "$directory" rev-parse --abbrev-ref HEAD)"
				branch=$(basename -- "$branch")
				git -C "$directory" pull origin "$branch"
				local param="${name}_OVERRIDE_SRCDIR = $directory"
				echo "--- adding $param"
				echo "$param" >>"./buildroot/local.mk"
			fi
		}
		append_source "LINUX" "linux"
		append_source "TENSORFLOW_LITE" "tensorflow-lite"
		append_source "IPCAMWEB_FRONTEND" "ipcamweb-frontend"

		set >"$p_environment"

		# Применение конфигурации
		if [[ "$p_clean_build" != "" ]]; then
			make distclean
		fi
		make "${p_build_device}_defconfig" FRAGMENTS=dev:dbg

		# Т.к. sources.redhat.com недоступен, отключаем его.
		HOSTALIASES_FILE="/var/tmp/hosts_aliases"
		echo "127.0.0.1	sources.redhat.com" >"$HOSTALIASES_FILE"
		export HOSTALIASES="$HOSTALIASES_FILE"

		# Дополнительный путь к wget_cache
		if [[ -d "$HOME/.local/bin" ]]; then
			export PATH=$HOME/.local/bin:$PATH
		fi

		#exit 0

		# Сборка Buildroot
		BR2_JLEVEL="$(nproc)" && export BR2_JLEVEL
		BR2_CCACHE=y && export BR2_CCACHE
		for target in "${p_build_make_targets[@]}"; do
			if is_true "$p_dry_run_build"; then
				log "DRY RUN: make -j$(nproc) $target"
			else
				make "-j$(nproc)" "$target"
			fi
		done

		set +e
		eval "$(cat "$p_environment")" >/dev/null 2>&1
		set -e
	done
done
