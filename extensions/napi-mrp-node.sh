# @description MRP (IEC 62439-2) ring node on a board with ordinary NICs, e.g. NanoPi R6S as
# MRC/MRM in a ring with NAPI-Switch: kernel bridge MRP, napi-mrp (mrp_server) from
# repo.napilab.ru, test tools. The bridge runs the ring in software (patch
# net-bridge-mrp-run-the-ring-in-software-on-plain-NICs). Login: napi/napilinux, no
# first-login wizard; NAPI_ROOT_SSH_KEY=<file> adds a public key for root (a path
# relative to the build tree, e.g. userpatches/root.pub: the build may run in Docker).
#
#   ./compile.sh build BOARD=nanopi-r6s BRANCH=current RELEASE=trixie ENABLE_EXTENSIONS=napi-mrp-node ...

function extension_prepare_config__napi_mrp_node() {
	declare -g TZDATA="Asia/Tashkent"
}

function custom_kernel_config__napi_mrp_node() {
	opts_y+=("BRIDGE_MRP")
}

function post_family_tweaks__napi_mrp_node_accounts() {
	declare user_name="napi" user_pass="napilinux" group

	display_alert "${BOARD}" "napi-mrp-node: user '${user_name}', no first-login wizard" "info"
	chroot_sdcard "id '${user_name}' >/dev/null 2>&1 || useradd --create-home --shell /bin/bash --comment 'NAPI' '${user_name}'"
	chroot_sdcard "echo '${user_name}:${user_pass}' | chpasswd"
	for group in sudo netdev dialout plugdev systemd-journal; do
		chroot_sdcard "usermod -aG '${group}' '${user_name}' 2>/dev/null || true"
	done
	run_host_command_logged rm -fv "${SDCARD}/root/.not_logged_in_yet"

	if [[ -n "${NAPI_ROOT_SSH_KEY}" ]]; then
		declare key="${NAPI_ROOT_SSH_KEY}"
		[[ "${key}" == /* ]] || key="${SRC}/${key}"
		[[ -f "${key}" ]] || exit_with_error "NAPI_ROOT_SSH_KEY: no file ${key}"
		display_alert "${BOARD}" "napi-mrp-node: root SSH key from ${NAPI_ROOT_SSH_KEY}" "info"
		install -d -m 0700 "${SDCARD}/root/.ssh"
		install -m 0600 "${key}" "${SDCARD}/root/.ssh/authorized_keys"
	fi

	# Same as the napi family: tzdata reads the zone from the /etc/localtime link.
	run_host_command_logged ln -sfn "/usr/share/zoneinfo/${TZDATA}" "${SDCARD}/etc/localtime"
	echo "${TZDATA}" > "${SDCARD}/etc/timezone"
	return 0
}

function post_repo_customize_image__napi_mrp_node_packages() {
	declare bsp="${SRC}/packages/bsp/napi"

	display_alert "${BOARD}" "napi-mrp-node: repo.napilab.ru, installing napi-mrp" "info"
	install -m 0644 "${bsp}/usr/share/keyrings/napilab.gpg" "${SDCARD}/usr/share/keyrings/napilab.gpg"
	install -m 0644 "${bsp}/etc/apt/sources.list.d/napilab.list" "${SDCARD}/etc/apt/sources.list.d/napilab.list"
	chroot_sdcard_apt_get update
	chroot_sdcard_apt_get_install napi-mrp iproute2 iperf3 tcpdump ethtool nftables
	return 0
}
