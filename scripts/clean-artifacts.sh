#!/bin/sh
set -e

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
RUNTIME="$("$ROOT/scripts/detect-runtime.sh" 2>/dev/null || echo none)"
IMAGE="lotus-os-builder:trixie"

rm_host() {
	rm -f "$ROOT/build.log" "$ROOT/.lock" 2>/dev/null || true
	find "$ROOT" -maxdepth 1 -name 'live-image-*.iso' -delete 2>/dev/null || true
	rm -f "$ROOT"/chroot.* 2>/dev/null || true
}

if [ "$RUNTIME" = none ]; then
	rm_host
	sudo rm -rf \
		"$ROOT/chroot" "$ROOT/cache" "$ROOT/binary" "$ROOT/local" \
		"$ROOT/.debootstrap" "$ROOT/unpacked-initrd" "$ROOT/.build" \
		"$ROOT/config/bootstrap" "$ROOT/config/binary" "$ROOT/config/chroot" \
		"$ROOT/config/build" "$ROOT/config/common" "$ROOT/config/source" \
		2>/dev/null || true
	exit 0
fi

SELINUX_MOUNT=":Z"
if [ -f /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	if [ "${ID:-}" != "fedora" ] && [ "${ID:-}" != "centos" ] && [ "${ID:-}" != "rhel" ]; then
		SELINUX_MOUNT=""
	fi
fi

if ! "$RUNTIME" image exists "$IMAGE" >/dev/null 2>&1; then
	IMAGE="docker.io/debian:trixie-slim"
fi

"$RUNTIME" run --rm \
	-v "$ROOT:/build${SELINUX_MOUNT}" \
	--entrypoint rm \
	"$IMAGE" \
	-rf \
	/build/chroot \
	/build/cache \
	/build/binary \
	/build/local \
	/build/.debootstrap \
	/build/config/bootstrap \
	/build/config/binary \
	/build/config/chroot \
	/build/config/build \
	/build/config/common \
	/build/config/source \
	/build/unpacked-initrd \
	/build/.build

rm_host
