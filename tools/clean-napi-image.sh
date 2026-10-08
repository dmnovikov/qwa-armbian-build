#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "Usage: $0 ROOTFS CONFIG [--apply]" >&2
	exit 1
}

[[ $# -ge 2 && $# -le 3 ]] || usage
mode=${3:---dry-run}
[[ $mode == --apply || $mode == --dry-run ]] || usage
root=$(realpath -e -- "$1")
[[ $root != / && -f $root/etc/armbian-release && -f $root/var/lib/dpkg/status ]] || {
	echo "Expected an Armbian image root directory." >&2
	exit 1
}
REMOVE_PACKAGES=()
KEEP_PACKAGES=(nano)
REMOVE_MAN_PAGES=no
PRUNE_FIRMWARE=no
KEEP_FIRMWARE=()
# shellcheck source=/dev/null
source "$2"

installed=()
for package in "${REMOVE_PACKAGES[@]}"; do
	[[ $package =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || exit 1
	status=$(chroot "$root" dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)
	[[ $status != 'install ok installed' ]] || installed+=("$package")
done

if ((${#installed[@]})); then
	plan=$(LC_ALL=C chroot "$root" apt-get --simulate purge "${installed[@]}")
	printf '%s\n' "$plan"
	for package in nano "${KEEP_PACKAGES[@]}"; do
		if awk -v package="$package" '$1 ~ /^(Remv|Purg)$/ && ($2 == package || index($2, package ":") == 1) {found=1} END {exit !found}' <<< "$plan"; then
			echo "Refusing to remove protected package: $package" >&2
			exit 1
		fi
	done
	if [[ $mode == --apply ]]; then
		chroot "$root" env DEBIAN_FRONTEND=noninteractive apt-get -y purge "${installed[@]}"
	fi
fi

if [[ $PRUNE_FIRMWARE == yes ]]; then
	python3 "$(dirname "${BASH_SOURCE[0]}")/clean-napi-firmware.py" \
		"$root" "$mode" "${KEEP_FIRMWARE[@]}"
fi

if [[ $REMOVE_MAN_PAGES == yes ]]; then
	echo "Remove /usr/share/man contents; exclude manual pages from package updates."
	if [[ $mode == --apply ]]; then
		[[ ! -L $root/usr && ! -L $root/usr/share && ! -L $root/usr/share/man && ! -L $root/etc && ! -L $root/etc/dpkg && ! -L $root/etc/dpkg/dpkg.cfg.d ]] || exit 1
		mkdir -p "$root/etc/dpkg/dpkg.cfg.d"
		[[ ! -L $root/etc/dpkg/dpkg.cfg.d/99-napi-minimal ]] || exit 1
		printf 'path-exclude=/usr/share/man/*\n' > "$root/etc/dpkg/dpkg.cfg.d/99-napi-minimal"
		if [[ -d $root/usr/share/man ]]; then
			find "$root/usr/share/man" -mindepth 1 -delete
		fi
	fi
fi
