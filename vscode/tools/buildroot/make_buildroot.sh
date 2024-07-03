#!/bin/bash

set -euo pipefail

# --------------------------------------------------------------------------------------------------

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
	log "    sdk             Build buildroot SDK"
	log "    -c | --clean    Start build from scratch"
	log "    -d | --dry-run  Dry dun. Download only, not build"
	log "    -D | --docker   Docker build"
	log "    -h | --help     Print this help screen & exit"
	log "         --no-wget  Do not cache wget files"
	log "         --no-proxy Disable proxies"
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
p_build_sdk=false
p_clean_build=false
p_dry_run_build=false
p_docker_build=false
p_no_wget=false
p_no_proxy=false
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
	sdk)
		p_build_sdk=true
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
	-D | --docker)
		p_docker_build=true
		shift 1
		;;
	--no-wget)
		p_no_wget=true
		shift 1
		;;
	--no-proxy)
		p_no_proxy=true
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
p_build_all_types=("image" "tools" "sdk")
if is_true "$p_build_image"; then
	p_build_types+=("image")
fi
if is_true "$p_build_tools"; then
	p_build_types+=("tools")
fi
if is_true "$p_build_sdk"; then
	p_build_types+=("sdk")
fi
if is_eq "${p_build_types[*]}" ""; then
	error "No build types specified (image/tools/sdk/...etc)."
	help
fi

if is_false "$p_no_proxy"; then
	export https_proxy=http://proxy.elvees.com:3128
	export http_proxy=http://proxy.elvees.com:3128
	export ftp_proxy=http://proxy.elvees.com:3128
	export no_proxy=127.0.0.1,localhost,elvees.com
fi

function execute_make() {
	if is_true "$p_docker_build"; then
		./docker-build.sh make "$@"
	else
		make "$@"
	fi
}

p_current_pwd="$PWD"
p_environment="$(mktemp /tmp/buildroot-env.XXXXXXXXX)"

for p_build_device in "${p_build_devices[@]}"; do
	for p_build_type in "${p_build_types[@]}"; do

		cd "$p_current_pwd"

		p_gerrit_source=""
		p_tools_targets=()
		p_sdk_targets=()
		case "$p_build_device" in
		ecam02)
			p_gerrit_source="ecam02/buildroot"
			p_tools_targets=(host-go libxml2 onvifd)
			p_sdk_targets=(sdk)
			;;
		ecam03)
			p_gerrit_source="ecam03/buildroot"
			p_tools_targets=(host-go delve libxml2 libarchive onvifd)
			p_sdk_targets=(sdk)
			;;
		*)
			fatal "Unknown or unsupported build device '$p_build_device'."
			;;
		esac

		p_build_targets=("${p_build_targets[@]}")
		if is_eq "${p_build_targets[*]}" ""; then
			if is_eq "$p_build_type" "tools"; then
				p_build_targets=("${p_tools_targets[@]}")
			elif is_eq "$p_build_type" "sdk"; then
				p_build_targets=("${p_sdk_targets[@]}")
			else
				p_build_targets=("all")
			fi
		fi

		p_build_directory="$p_build_type/${p_build_device}"

		p_message="Building $p_build_type for $p_build_device, make [${p_build_targets[*]}]"
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
		if [[ -f "$p_current_pwd/local.fragment" ]]; then
			cp "$p_current_pwd/local.fragment" "$p_fragment_name"
		fi
		#		cat <<EOF >"$p_fragment_name"
		#BR2_PACKAGE_DELVE=y
		#R2_PACKAGE_PPROF=y
		#BR2_PACKAGE_MOSH=y
		#BR2_PACKAGE_DSP_THERMO_TESTS=n
		#BR2_PACKAGE_ONVIFD_SYSPARTITIONS=5
		##BR2_PACKAGE_PYTHON_IPCAM_TOOLS=n
		#BR2_PACKAGE_NGINX_HTTP_DAV_MODULE=y
		#BR2_PACKAGE_NGINX_UPLOAD=y
		#BR2_JLEVEL=$(nproc)
		#BR2_CCACHE=y
		#BR2_PACKAGE_IGD2_FOR_LINUX=y
		#BR2_PACKAGE_SSDP_RESPONDER=y
		#BR2_PACKAGE_NANO=y
		## Experimental buildroot features:
		## BR2_PER_PACKAGE_DIRECTORIES=y
		#BR2_PACKAGE_GPTFDISK=y
		#BR2_PACKAGE_GPTFDISK_SGDISK=y
		#BR2_PACKAGE_BASH_COMPLETION=y
		#BR2_PACKAGE_RSYNC=y
		#EOF

		# Копируем overlay в buildroot
		echo "#"
		echo "# merging overlay into buildroot"
		echo "#"
		p_overlay_dir=".overlay"
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
		append_source "UBOOT_TOOLS" "uboot-tools"

		set >"$p_environment"

		# Применение конфигурации
		if [[ "$p_clean_build" != "" ]]; then
			execute_make distclean
		fi
		execute_make "${p_build_device}_defconfig" FRAGMENTS=dev:dbg

		# Т.к. sources.redhat.com недоступен, отключаем его.
		HOSTALIASES_FILE="/var/tmp/hosts_aliases"
		echo "127.0.0.1	sources.redhat.com" >"$HOSTALIASES_FILE"
		export HOSTALIASES="$HOSTALIASES_FILE"

		# Дополнительный путь к wget_cache
		if is_false "$p_no_proxy"; then
			if [[ -d "$HOME/.local/bin/wget" ]]; then
				export PATH=$HOME/.local/bin:$PATH
			fi
		fi

		# Сборка Buildroot
		BR2_JLEVEL="$(nproc)"
		export BR2_JLEVEL
		BR2_CCACHE=y
		export BR2_CCACHE
		NPROC="-j$(nproc)"
		for target in "${p_build_targets[@]}"; do
			if is_true "$p_dry_run_build"; then
				log "DRY RUN: make $NPROC $target"
			else
				set +e
				retries=1
				while ((retries > 0)); do
					echo "--- make $NPROC $target # retries $retries"
					execute_make "$NPROC" "$target"
					status="$?"
					if is_eq "$status" "0"; then
						break
					fi
					error "Failed to build $target, status \"$status\""
					retries=$((retries - 1))
				done
				if ((retries == 0)); then
					fatal "Failed to build $target, status \"$status\""
				fi
				set -e
			fi
		done

		# to install matplotlib & numpy:
		pip3 install matplotlib
		pip3 install numpy
		execute_make graph-build

		set +e
		eval "$(cat "$p_environment")" >/dev/null 2>&1
		set -e
	done
done
