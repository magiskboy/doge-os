#!/bin/sh
# Boot Lotus OS ISO in QEMU (UEFI when OVMF is available).
set -e

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/lib.sh"

ISO="$ISO_PATH"
VM_DIR="$ROOT/output/vm"
DISK="$VM_DIR/disk.qcow2"
DISK_SIZE="${LOTUS_DISK_SIZE:-32G}"
MEMORY="${LOTUS_MEMORY:-4096}"
SMP="${LOTUS_SMP:-4}"

if [ ! -f "$ISO" ]; then
	echo "error: ISO not found at $ISO" >&2
	echo "Run 'make build' first." >&2
	exit 1
fi

mkdir -p "$VM_DIR"

if [ ! -f "$DISK" ]; then
	echo "Creating virtual disk ($DISK_SIZE): $DISK"
	qemu-img create -f qcow2 "$DISK" "$DISK_SIZE"
fi

find_ovmf_dir() {
	for dir in /usr/share/edk2/ovmf /usr/share/OVMF /usr/share/qemu; do
		if [ -f "$dir/OVMF_CODE.fd" ] && [ -f "$dir/OVMF_VARS.fd" ]; then
			echo "$dir"
			return 0
		fi
	done
	return 1
}

OVMF_DIR="$(find_ovmf_dir || true)"
OVMF_VARS="$VM_DIR/OVMF_VARS.fd"
USE_UEFI=0

if [ -n "$OVMF_DIR" ]; then
	USE_UEFI=1
	if [ ! -f "$OVMF_VARS" ]; then
		cp "$OVMF_DIR/OVMF_VARS.fd" "$OVMF_VARS"
	fi
else
	echo "warning: OVMF firmware not found; falling back to legacy BIOS" >&2
fi

if [ -r /dev/kvm ]; then
	MACHINE="q35,accel=kvm"
	CPU="host"
else
	MACHINE="q35"
	CPU="max"
	echo "warning: /dev/kvm not available, using software emulation (slow)" >&2
fi

DISPLAY_BACKEND=""
if [ -z "${DISPLAY:-}" ]; then
	echo "warning: DISPLAY not set, using text console only" >&2
else
	for backend in gtk sdl spice-app default; do
		if qemu-system-x86_64 -display help 2>/dev/null | grep -qx "$backend"; then
			DISPLAY_BACKEND="$backend"
			break
		fi
	done
	if [ -z "$DISPLAY_BACKEND" ]; then
		echo "warning: no graphical QEMU display backend found; using text console" >&2
	fi
fi

echo "Lotus OS"
echo "  ISO:  $ISO"
echo "  Disk: $DISK ($DISK_SIZE)"
echo "  RAM:  ${MEMORY} MiB, CPUs: $SMP"
echo "  UEFI: $([ "$USE_UEFI" -eq 1 ] && echo yes || echo no)"
echo ""

launch_qemu() {
	vga_device="$1"

	if [ -n "$DISPLAY_BACKEND" ]; then
		display_args="-display $DISPLAY_BACKEND"
	else
		display_args="-nographic"
	fi

	# shellcheck disable=SC2086
	if [ "$USE_UEFI" -eq 1 ]; then
		exec qemu-system-x86_64 \
			-name lotus-os \
			-machine "$MACHINE" \
			-cpu "$CPU" \
			-m "$MEMORY" \
			-smp "$SMP" \
			-drive if=pflash,format=raw,readonly=on,file="$OVMF_DIR/OVMF_CODE.fd" \
			-drive if=pflash,format=raw,file="$OVMF_VARS" \
			-device ich9-ahci,id=ahci \
			-drive file="$DISK",format=qcow2,if=none,id=disk0 \
			-device ide-hd,drive=disk0,bus=ahci.0 \
			-drive file="$ISO",format=raw,media=cdrom,if=none,id=cdrom0 \
			-device ide-cd,drive=cdrom0,bus=ahci.1 \
			-netdev user,id=net0,hostfwd=tcp::2222-:22 \
			-device virtio-net-pci,netdev=net0 \
			-device qemu-xhci,id=xhci \
			-device usb-tablet,bus=xhci.0 \
			-device virtio-rng-pci \
			-device "$vga_device" \
			$display_args \
			-boot order=d,menu=on,splash-time=5000
	fi

	exec qemu-system-x86_64 \
		-name lotus-os \
		-machine "$MACHINE" \
		-cpu "$CPU" \
		-m "$MEMORY" \
		-smp "$SMP" \
		-device ich9-ahci,id=ahci \
		-drive file="$DISK",format=qcow2,if=none,id=disk0 \
		-device ide-hd,drive=disk0,bus=ahci.0 \
		-drive file="$ISO",format=raw,media=cdrom,if=none,id=cdrom0 \
		-device ide-cd,drive=cdrom0,bus=ahci.1 \
		-netdev user,id=net0,hostfwd=tcp::2222-:22 \
		-device virtio-net-pci,netdev=net0 \
		-device qemu-xhci,id=xhci \
		-device usb-tablet,bus=xhci.0 \
		-device virtio-rng-pci \
		-device "$vga_device" \
		$display_args \
		-boot order=d,menu=on,splash-time=5000
}

if [ "$USE_UEFI" -eq 1 ]; then
	launch_qemu virtio-vga
else
	launch_qemu cirrus-vga
fi
