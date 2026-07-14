#!/bin/sh
# Build DogeOS ISO (native on Debian Trixie, otherwise container).
# Keeps live-build cache between runs for faster rebuilds.
set -e

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/lib.sh"

can_build_native() {
	[ -f /etc/os-release ] || return 1
	# shellcheck disable=SC1091
	. /etc/os-release
	[ "${ID:-}" = debian ] && [ "${VERSION_CODENAME:-}" = trixie ] && command -v lb >/dev/null 2>&1
}

build_native() {
	cd "$ROOT"
	sh "$ROOT/scripts/prepare-live-build.sh"
	sh "$ROOT/auto/config"
	rm -f live-image-amd64.hybrid.iso
	fakeroot lb build
	mkdir -p "$ROOT/output"
	cp -f live-image-amd64.hybrid.iso "$ISO_PATH"
	echo "ISO written to output/$ISO_NAME"
}

build_container() {
	RUNTIME="$(detect_runtime)"
	if [ "$RUNTIME" = none ]; then
		echo "error: podman or docker is required for container builds" >&2
		exit 1
	fi

	SELINUX_MOUNT="$(selinux_mount)"
	echo "Using runtime: $RUNTIME"

	"$RUNTIME" build -t "$IMAGE_NAME" -f "$ROOT/container-builder/Containerfile" "$ROOT/container-builder"
	mkdir -p "$ROOT/output"

	# Privileged + /dev required for live-build chroot/loop devices.
	# Rootless Podman still cannot mknod; entrypoint falls back to fakeroot.
	"$RUNTIME" run --rm \
		--privileged \
		--security-opt seccomp=unconfined \
		-v /dev:/dev \
		-v "$ROOT:/build${SELINUX_MOUNT}" \
		-w /build \
		"$IMAGE_NAME"

	if [ ! -f "$ISO_PATH" ]; then
		echo "error: ISO not found at output/$ISO_NAME" >&2
		exit 1
	fi

	echo "Build complete: output/$ISO_NAME"
}

if can_build_native; then
	build_native
else
	build_container
fi
