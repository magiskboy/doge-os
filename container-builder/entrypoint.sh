#!/bin/sh
set -eux

if [ "$#" -gt 0 ]; then
	exec "$@"
fi

cd /build

rm -f ./.lock

if [ -f config/binary ]; then
	sed -i 's/^LB_BOOTAPPEND_INSTALL=.*/LB_BOOTAPPEND_INSTALL=""/' config/binary
fi

# Rebuild installer/ISO when preseed changes (live-build skips cached stages).
if [ -f config/includes.installer/preseed.cfg ]; then
	_PRESEED="config/includes.installer/preseed.cfg"
	_NEEDS_INSTALLER_REBUILD=false
	for _STAGE in installer_debian-installer installer_preseed binary_grub_cfg binary_includes binary_iso; do
		if [ ! -e ".build/${_STAGE}" ] || [ "${_PRESEED}" -nt ".build/${_STAGE}" ]; then
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
for _LIST in config/package-lists/*.list.chroot; do
	[ -e "${_LIST}" ] || continue
	_BASE="${_LIST##*/}"
	_BASE="${_BASE%.list.chroot}"
	_STAGE=".build/chroot_install-packages.${_BASE}"
	if [ ! -e "${_STAGE}" ] || [ "${_LIST}" -nt "${_STAGE}" ]; then
		echo "Package list changed; invalidating chroot and binary stages"
		rm -f .build/chroot_package-lists.* .build/chroot_install-packages.* \
			.build/chroot_purge .build/chroot_rootfs .build/chroot_live \
			.build/binary_*
		break
	fi
done

if [ ! -x ./auto/config ]; then
	echo "error: /build/auto/config not found or not executable" >&2
	exit 1
fi

fakeroot ./auto/config

rm -f live-image-amd64.hybrid.iso

fakeroot lb build || exit 1

ISO_SRC="live-image-amd64.hybrid.iso"
ISO_DST="output/lotus-os-trixie-amd64.hybrid.iso"

if [ -f "$ISO_SRC" ]; then
	mkdir -p output
	cp -f "$ISO_SRC" "$ISO_DST"
	echo "ISO written to $ISO_DST"
else
	echo "error: expected ISO not found at $ISO_SRC" >&2
	exit 1
fi
