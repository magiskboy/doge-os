#!/bin/sh
set -e

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
ISO_NAME="lotus-os-trixie-amd64.hybrid.iso"
IMAGE_NAME="lotus-os-builder:trixie"

RUNTIME="$("$ROOT/scripts/detect-runtime.sh" 2>/dev/null || true)"
if [ -z "$RUNTIME" ] || [ "$RUNTIME" = none ]; then
	echo "error: podman or docker is required for container builds" >&2
	exit 1
fi

SELINUX_MOUNT=":Z"
if [ -f /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	if [ "${ID:-}" != "fedora" ] && [ "${ID:-}" != "centos" ] && [ "${ID:-}" != "rhel" ]; then
		SELINUX_MOUNT=""
	fi
fi

echo "Using runtime: $RUNTIME"

"$RUNTIME" build -t "$IMAGE_NAME" -f "$ROOT/container-builder/Containerfile" "$ROOT/container-builder"

mkdir -p "$ROOT/output"

# Privileged + /dev required for live-build chroot/mknod/loop devices.
"$RUNTIME" run --rm \
	--privileged \
	--security-opt seccomp=unconfined \
	-v /dev:/dev \
	-v "$ROOT:/build${SELINUX_MOUNT}" \
	-w /build \
	"$IMAGE_NAME"

if [ ! -f "$ROOT/output/$ISO_NAME" ]; then
	echo "error: ISO not found at output/$ISO_NAME" >&2
	exit 1
fi

echo "Build complete: output/$ISO_NAME"
