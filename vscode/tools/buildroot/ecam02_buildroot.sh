#!/bin/sh

BUILD_DIRNAME=ecam02_buildroot
BUILD_TARGETS=(all)
BUILD_POSTFIX=

start_time="$(date +%s.%N)"
trap exit_trap EXIT

function exit_trap() {
	local dt dd dt2 dh dt3 dm ds
	dt=$(echo "$(date +%s.%N) - $start_time" | bc)
	dd=$(echo "$dt/86400" | bc)
	dt2=$(echo "$dt-86400*$dd" | bc)
	dh=$(echo "$dt2/3600" | bc)
	dt3=$(echo "$dt2-3600*$dh" | bc)
	dm=$(echo "$dt3/60" | bc)
	ds=$(echo "$dt3-60*$dm" | bc)
	if [[ "$dd" != "0" ]]; then
		echo "$(printf "Total runtime: %dd %02dh %02dm %02.4fs\n" "$dd" "$dh" "$dm" "$ds")"
	elif [[ "$dh" != "0" ]]; then
		echo "$(printf "Total runtime: %dh %02dm %02.4fs\n" "$dh" "$dm" "$ds")"
	elif [[ "$dm" != "0" ]]; then
		echo "$(printf "Total runtime: %dm %02.4f\n" "$dm" "$ds")"
	else
		echo "$(printf "Total runtime: %02.4fs\n" "$ds")"
	fi
}

export https_proxy=http://proxy.elvees.com:3128
export http_proxy=http://proxy.elvees.com:3128
export ftp_proxy=http://proxy.elvees.com:3128
export no_proxy=127.0.0.1,localhost,elvees.com

export BR2_PRIMARY_SITE=http://callisto.elvees.com/mirror/buildroot
export PYTHONUSERBASE=$HOME/.python
export PATH=$PYTHONUSERBASE/bin:$PATH

export GOPROXY=http://athens.elvees.com,https://proxy.golang.org,direct

SCRIPT_ARG="$1"
if [[ "$SCRIPT_ARG" == "delete" ]] && [[ -d "$BUILD_DIRNAME" ]]; then
	rm -rf "$BUILD_DIRNAME"
	SCRIPT_ARG=""
fi

if [[ ! -d "$BUILD_DIRNAME" ]]; then
	git clone "ssh://$USER@gerrit.elvees.com:29418/mcom02/ecam02" "$BUILD_DIRNAME"
	scp -p -P 29418 "$USER@gerrit.elvees.com:hooks/commit-msg" "$BUILD_DIRNAME/.git/hooks/"
fi

cd "$BUILD_DIRNAME"
git submodule init
git submodule update --recursive
git pull
git pull --recurse-submodules

git reset --hard
git submodule foreach --recursive git reset --hard
git submodule update --init --recursive

# Копируем local.mk в buildroot
if [[ -f "../local.mk" ]]; then
	cp "../local.mk" "./buildroot/"
fi

# Создание dbg.fragment
#cat <<EOF > "./external-ipcam/ecam03-fragments/dbg.fragment"
#BR2_PACKAGE_DELVE=y
#BR2_PACKAGE_PPROF=y
#BR2_PACKAGE_DSP_THERMO_TESTS=n
#EOF

# Применение конфигурации
#make distclean
make ecam02_defconfig FRAGMENTS=dev

# Сборка Buildroot
export BR2_JLEVEL="$(nproc)"
for target in "${BUILD_TARGETS[@]}"; do
	make -j$(nproc) $target$BUILD_POSTFIX
done
