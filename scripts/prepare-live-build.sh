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
		.build/chroot_* \
		.build/binary_* \
		.build/installer_debian-installer \
		.build/installer_preseed
}

chroot_has_kernel() {
	ls chroot/boot/vmlinuz-* >/dev/null 2>&1
}

# Copy host CA store into a rootfs so apt can verify HTTPS third-party
# archives during chroot_archives (before package lists install ca-certificates).
# Apt's HTTPS method uses OpenSSL, which looks under OPENSSLDIR (/usr/lib/ssl),
# not only /etc/ssl/certs — same issue as live-build + HTTPS mirrors without
# ca-certificates (https://unix.stackexchange.com/q/805776).
# Do not force a fresh debootstrap: under rootless/fakeroot that often fails
# (tar into a non-empty chroot, or device nodes).
inject_ca_certs() {
	_root="$1"
	[ -n "${_root}" ] || return 1
	[ -d "${_root}" ] || return 1

	_need_certs=false
	_need_openssl_dir=false
	[ -f "${_root}/etc/ssl/certs/ca-certificates.crt" ] || _need_certs=true
	[ -e "${_root}/usr/lib/ssl/cert.pem" ] || _need_openssl_dir=true

	if [ "${_need_certs}" = false ] && [ "${_need_openssl_dir}" = false ]; then
		return 0
	fi

	if [ "${_need_certs}" = true ]; then
		if [ ! -f /etc/ssl/certs/ca-certificates.crt ]; then
			echo "error: cannot inject CA certs: /etc/ssl/certs missing on build host" >&2
			return 1
		fi
		echo "Injecting CA certificates into ${_root}"
		mkdir -p "${_root}/etc/ssl"
		rm -rf "${_root}/etc/ssl/certs"
		cp -a /etc/ssl/certs "${_root}/etc/ssl/"
		if [ -f /etc/ssl/openssl.cnf ] && [ ! -e "${_root}/etc/ssl/openssl.cnf" ]; then
			cp -a /etc/ssl/openssl.cnf "${_root}/etc/ssl/"
		fi
	fi

	# OpenSSL OPENSSLDIR layout (normally provided by the openssl package).
	if [ "${_need_openssl_dir}" = true ]; then
		echo "Injecting OpenSSL cert dir layout into ${_root}"
		mkdir -p "${_root}/usr/lib/ssl" "${_root}/etc/ssl/private"
		ln -sfn /etc/ssl/certs "${_root}/usr/lib/ssl/certs"
		ln -sfn /etc/ssl/certs/ca-certificates.crt "${_root}/usr/lib/ssl/cert.pem"
		if [ -f "${_root}/etc/ssl/openssl.cnf" ]; then
			ln -sfn /etc/ssl/openssl.cnf "${_root}/usr/lib/ssl/openssl.cnf"
		elif [ -f /etc/ssl/openssl.cnf ]; then
			cp -a /etc/ssl/openssl.cnf "${_root}/etc/ssl/"
			ln -sfn /etc/ssl/openssl.cnf "${_root}/usr/lib/ssl/openssl.cnf"
		fi
		ln -sfn /etc/ssl/private "${_root}/usr/lib/ssl/private"
	fi
}

# Recreate cache/bootstrap from a usable chroot when the cache was removed
# (avoids re-running debootstrap under fakeroot into a non-empty tree).
ensure_bootstrap_cache() {
	if [ -d cache/bootstrap ] && [ -x cache/bootstrap/usr/bin/apt ]; then
		return 0
	fi
	if [ ! -x chroot/usr/bin/apt ]; then
		return 0
	fi
	echo "Recreating cache/bootstrap from existing chroot"
	rm -rf chroot/debootstrap
	inject_ca_certs chroot
	mkdir -p cache
	rm -rf cache/bootstrap
	cp -a chroot cache/bootstrap
	touch .build/bootstrap .build/bootstrap_cache.save .build/bootstrap_cache.restore
	invalidate_chroot_stages
}

ensure_bootstrap_cache

# Ensure CA store + OpenSSL OPENSSLDIR exist for HTTPS archives.
_NEEDS_ARCHIVES_RERUN=false
if [ -d cache/bootstrap ]; then
	if [ ! -f cache/bootstrap/etc/ssl/certs/ca-certificates.crt ] || \
		[ ! -e cache/bootstrap/usr/lib/ssl/cert.pem ]; then
		inject_ca_certs cache/bootstrap
		_NEEDS_ARCHIVES_RERUN=true
	fi
fi
if [ -d chroot ] && [ -x chroot/usr/bin/apt ]; then
	if [ ! -f chroot/etc/ssl/certs/ca-certificates.crt ] || \
		[ ! -e chroot/usr/lib/ssl/cert.pem ]; then
		inject_ca_certs chroot
		_NEEDS_ARCHIVES_RERUN=true
	fi
fi
if [ "${_NEEDS_ARCHIVES_RERUN}" = true ]; then
	echo "CA/OpenSSL layout injected; invalidating chroot stages so archives re-run"
	invalidate_chroot_stages
fi

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

# Rebuild chroot when package lists or third-party archives change.
# live-build stages are named by pass (.install / .live), not by list basename.
_NEEDS_CHROOT_REBUILD=false
if [ -e .build/chroot_install-packages.install ] || [ -e .build/chroot_install-packages.live ] || \
	[ -e .build/chroot_archives ]; then
	for _LIST in \
		config/package-lists/*.list \
		config/package-lists/*.list.chroot \
		config/package-lists/*.list.chroot_* \
		config/archives/*.list \
		config/archives/*.list.chroot \
		config/archives/*.list.binary \
		config/archives/*.key \
		config/archives/*.key.chroot \
		config/archives/*.key.binary; do
		[ -e "${_LIST}" ] || continue
		for _STAGE in \
			.build/chroot_install-packages.install \
			.build/chroot_install-packages.live \
			.build/chroot_archives; do
			[ -e "${_STAGE}" ] || continue
			if [ "${_LIST}" -nt "${_STAGE}" ]; then
				_NEEDS_CHROOT_REBUILD=true
				break 2
			fi
		done
	done
fi
if [ "${_NEEDS_CHROOT_REBUILD}" = true ]; then
	echo "Package list or archives changed; invalidating chroot and binary stages"
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
