#!/bin/sh
# Repair live-build stage stamps before `lb build`.
#
# live-build only creates `.build/bootstrap_cache.restore` when a restore
# actually runs. A first bootstrap (debootstrap + save) never creates that
# stamp, so the next build would wipe `chroot/` from cache while leaving
# chroot stage stamps — skipping kernel scheduling (`chroot_linux-image`).
set -e

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p .build

invalidate_chroot_stages() {
	echo "Invalidating chroot and binary stages"
	rm -f \
		.build/chroot_linux-image \
		.build/chroot_firmware \
		.build/chroot_preseed \
		.build/chroot_includes_before_packages \
		.build/chroot_package-lists.* \
		.build/chroot_install-packages.* \
		.build/chroot_includes_after_packages \
		.build/chroot_hooks \
		.build/chroot_hacks \
		.build/chroot_interactive \
		.build/chroot_purge \
		.build/chroot_rootfs \
		.build/chroot_live \
		.build/binary_* \
		.build/installer_debian-installer \
		.build/installer_preseed
}

chroot_has_kernel() {
	ls chroot/boot/vmlinuz-* >/dev/null 2>&1
}

# Rebuild installer/ISO when preseed changes (live-build skips cached stages).
if [ -f config/includes.installer/preseed.cfg ]; then
	_PRESEED="config/includes.installer/preseed.cfg"
	_NEEDS_INSTALLER_REBUILD=false
	for _STAGE in installer_debian-installer installer_preseed binary_grub_cfg binary_includes binary_iso; do
		[ -e ".build/${_STAGE}" ] || continue
		if [ "${_PRESEED}" -nt ".build/${_STAGE}" ]; then
			_NEEDS_INSTALLER_REBUILD=true
			break
		fi
	done
	if [ "${_NEEDS_INSTALLER_REBUILD}" = true ]; then
		echo "Preseed changed; invalidating installer and ISO build stages"
		rm -f .build/installer_debian-installer .build/installer_preseed \
			.build/binary_grub_cfg .build/binary_includes .build/binary_iso
		rm -rf binary binary.udeb unpacked-initrd
	fi
fi

# Rebuild chroot when package lists change.
# live-build stages are named by pass (.install / .live), not by list basename.
_NEEDS_CHROOT_REBUILD=false
if [ -e .build/chroot_install-packages.install ] || [ -e .build/chroot_install-packages.live ]; then
	for _LIST in \
		config/package-lists/*.list \
		config/package-lists/*.list.chroot \
		config/package-lists/*.list.chroot_*; do
		[ -e "${_LIST}" ] || continue
		for _STAGE in .build/chroot_install-packages.install .build/chroot_install-packages.live; do
			[ -e "${_STAGE}" ] || continue
			if [ "${_LIST}" -nt "${_STAGE}" ]; then
				_NEEDS_CHROOT_REBUILD=true
				break 2
			fi
		done
	done
fi
if [ "${_NEEDS_CHROOT_REBUILD}" = true ]; then
	echo "Package list changed; invalidating chroot and binary stages"
	invalidate_chroot_stages
fi

# First bootstrap never stamps bootstrap_cache.restore. Without that stamp,
# the next build restores cache/bootstrap over chroot and skips stamped
# chroot stages (including kernel scheduling).
if [ -d cache/bootstrap ] && [ ! -e .build/bootstrap_cache.restore ]; then
	if [ -e .build/chroot_linux-image ] || [ -e .build/chroot_install-packages.install ]; then
		if chroot_has_kernel; then
			echo "Preserving completed chroot; marking bootstrap_cache.restore done"
			touch .build/bootstrap_cache.restore
		else
			echo "Bootstrap restore would wipe chroot with stale stage stamps; invalidating chroot stages"
			invalidate_chroot_stages
		fi
	fi
fi

# Recover from partial/failed rebuilds: stamp says kernel was scheduled, but
# vmlinuz is missing from the live chroot.
if [ -e .build/chroot_linux-image ] && ! chroot_has_kernel; then
	echo "Kernel stage stamped but vmlinuz missing; invalidating chroot stages"
	invalidate_chroot_stages
fi
