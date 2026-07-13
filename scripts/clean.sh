#!/bin/sh
# Remove live-build intermediates. Keeps:
#   - output/*.iso (product)
#   - cache/ (package + bootstrap cache for faster rebuilds)
set -e

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/lib.sh"

rm_host() {
	rm -f "$ROOT/build.log" "$ROOT/.lock" 2>/dev/null || true
	find "$ROOT" -maxdepth 1 -name 'live-image-*' -delete 2>/dev/null || true
	rm -f "$ROOT"/chroot.* 2>/dev/null || true
}

CLEAN_PATHS="
	/build/chroot
	/build/binary
	/build/binary.deb
	/build/binary.udeb
	/build/local
	/build/.debootstrap
	/build/unpacked-initrd
	/build/.build
	/build/config/bootstrap
	/build/config/binary
	/build/config/chroot
	/build/config/build
	/build/config/common
	/build/config/source
"

RUNTIME="$(detect_runtime)"
if [ "$RUNTIME" = none ]; then
	rm_host
	sudo rm -rf \
		"$ROOT/chroot" "$ROOT/binary" "$ROOT/binary.deb" "$ROOT/binary.udeb" \
		"$ROOT/local" "$ROOT/.debootstrap" "$ROOT/unpacked-initrd" "$ROOT/.build" \
		"$ROOT/config/bootstrap" "$ROOT/config/binary" "$ROOT/config/chroot" \
		"$ROOT/config/build" "$ROOT/config/common" "$ROOT/config/source" \
		2>/dev/null || true
	echo "Cleaned build intermediates (kept output/*.iso and cache/)"
	exit 0
fi

SELINUX_MOUNT="$(selinux_mount)"
CLEAN_IMAGE="$IMAGE_NAME"
if ! "$RUNTIME" image exists "$CLEAN_IMAGE" >/dev/null 2>&1; then
	CLEAN_IMAGE="docker.io/debian:trixie-slim"
fi

# shellcheck disable=SC2086
"$RUNTIME" run --rm \
	-v "$ROOT:/build${SELINUX_MOUNT}" \
	--entrypoint rm \
	"$CLEAN_IMAGE" \
	-rf $CLEAN_PATHS

rm_host
echo "Cleaned build intermediates (kept output/*.iso and cache/)"
