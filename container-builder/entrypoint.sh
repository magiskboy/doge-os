#!/bin/sh
set -eu

if [ "$#" -gt 0 ]; then
	exec "$@"
fi

cd /build

rm -f ./.lock

if [ -f config/binary ]; then
	sed -i 's/^LB_BOOTAPPEND_INSTALL=.*/LB_BOOTAPPEND_INSTALL=""/' config/binary
fi

sh ./scripts/prepare-live-build.sh

if [ ! -x ./auto/config ]; then
	echo "error: /build/auto/config not found or not executable" >&2
	exit 1
fi

./auto/config

rm -f live-image-amd64.hybrid.iso

# Rootless containers cannot mknod; fakeroot fakes device nodes for d-i initrd.
if mknod /tmp/.lotus-mknod-test c 1 3 2>/dev/null; then
	rm -f /tmp/.lotus-mknod-test
	lb build
else
	echo "note: mknod unavailable; running lb build under fakeroot" >&2
	fakeroot lb build
fi

ISO_SRC="live-image-amd64.hybrid.iso"
ISO_DST="output/lotus-os-trixie-amd64.hybrid.iso"

if [ ! -f "$ISO_SRC" ]; then
	echo "error: expected ISO not found at $ISO_SRC" >&2
	exit 1
fi

mkdir -p output
cp -f "$ISO_SRC" "$ISO_DST"
echo "ISO written to $ISO_DST"
