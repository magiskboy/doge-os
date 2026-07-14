#!/bin/sh
# Boot DogeOS ISO in QEMU as a laptop-like guest (UEFI when OVMF is available).
#
# Default hardware profile (q35):
#   - Display 1920x1080 (virtio-vga + EDID)
#   - Wired Ethernet (virtio-net, user-mode NAT, SSH hostfwd :2222)
#   - Intel HDA audio (speaker + microphone)
#   - USB 3.0 + tablet/keyboard
#   - ACPI power button (built into q35; battery/AC/lid need newer QEMU patches)
#
# Optional host USB passthrough (QEMU has no emulated Wi‑Fi/BT radios):
#   DOGE_USB_BT=1              auto-pass first USB Bluetooth adapter
#   DOGE_USB_BT=vvvv:pppp      pass specific Bluetooth device
#   DOGE_USB_WIFI=vvvv:pppp    pass USB Wi‑Fi adapter
#
# Other knobs: DOGE_MEMORY, DOGE_SMP, DOGE_DISK_SIZE, DOGE_VGA_GL=1
set -e

. "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/lib.sh"

ISO="$ISO_PATH"
VM_DIR="$ROOT/output/vm"
DISK="$VM_DIR/disk.qcow2"
DISK_SIZE="${DOGE_DISK_SIZE:-32G}"
MEMORY="${DOGE_MEMORY:-4096}"
SMP="${DOGE_SMP:-4}"
SCREEN_W="${DOGE_SCREEN_W:-1920}"
SCREEN_H="${DOGE_SCREEN_H:-1080}"

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

pick_audio_driver() {
	for driver in pipewire pa alsa sdl; do
		if qemu-system-x86_64 -audio help 2>/dev/null | grep -qx "$driver"; then
			echo "$driver"
			return 0
		fi
	done
	return 1
}

# Parse vvvv:pppp into -device usb-host,vendorid=...,productid=...
usb_host_args() {
	id="$1"
	vendor="$(printf '%s' "$id" | cut -d: -f1)"
	product="$(printf '%s' "$id" | cut -d: -f2)"
	if [ -z "$vendor" ] || [ -z "$product" ] || [ "$vendor" = "$product" ]; then
		echo "error: invalid USB id '$id' (expected vvvv:pppp)" >&2
		return 1
	fi
	# Normalize hex without 0x prefix for QEMU
	vendor="$(printf '%s' "$vendor" | tr 'A-F' 'a-f')"
	product="$(printf '%s' "$product" | tr 'A-F' 'a-f')"
	printf -- '-device usb-host,vendorid=0x%s,productid=0x%s' "$vendor" "$product"
}

find_usb_bluetooth() {
	if ! command -v lsusb >/dev/null 2>&1; then
		return 1
	fi
	lsusb 2>/dev/null | grep -i bluetooth | head -n1 | sed -n 's/.*ID \([0-9a-fA-F]\{4\}:[0-9a-fA-F]\{4\}\).*/\1/p'
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
	MACHINE="q35,accel=kvm,usb=off"
	CPU="host"
else
	MACHINE="q35,usb=off"
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

AUDIO_DRIVER="$(pick_audio_driver || true)"
EXTRA_USB=""

# Bluetooth: host USB passthrough (emulation removed on modern x86 QEMU builds)
case "${DOGE_USB_BT:-}" in
	""|0|false|no) ;;
	1|true|yes)
		bt_id="$(find_usb_bluetooth || true)"
		if [ -n "$bt_id" ]; then
			EXTRA_USB="$EXTRA_USB $(usb_host_args "$bt_id")"
			echo "USB Bluetooth passthrough: $bt_id"
		else
			echo "warning: DOGE_USB_BT set but no USB Bluetooth device found" >&2
		fi
		;;
	*:*)
		EXTRA_USB="$EXTRA_USB $(usb_host_args "$DOGE_USB_BT")"
		echo "USB Bluetooth passthrough: $DOGE_USB_BT"
		;;
	*)
		echo "error: DOGE_USB_BT must be 1 or vvvv:pppp" >&2
		exit 1
		;;
esac

# Wi‑Fi: no emulated 802.11 NIC in QEMU; USB Wi‑Fi dongle passthrough only
case "${DOGE_USB_WIFI:-}" in
	""|0|false|no) ;;
	*:*)
		EXTRA_USB="$EXTRA_USB $(usb_host_args "$DOGE_USB_WIFI")"
		echo "USB Wi‑Fi passthrough: $DOGE_USB_WIFI"
		;;
	*)
		echo "error: DOGE_USB_WIFI must be vvvv:pppp (QEMU cannot emulate Wi‑Fi)" >&2
		exit 1
		;;
esac

if [ "$USE_UEFI" -eq 1 ]; then
	if [ "${DOGE_VGA_GL:-0}" = "1" ] && qemu-system-x86_64 -device help 2>/dev/null | grep -q 'virtio-vga-gl'; then
		VGA_DEVICE="virtio-vga-gl,xres=${SCREEN_W},yres=${SCREEN_H}"
	else
		VGA_DEVICE="virtio-vga,xres=${SCREEN_W},yres=${SCREEN_H}"
	fi
else
	VGA_DEVICE="cirrus-vga"
fi

echo "DogeOS (laptop profile)"
echo "  ISO:     $ISO"
echo "  Disk:    $DISK ($DISK_SIZE)"
echo "  RAM:     ${MEMORY} MiB, CPUs: $SMP"
echo "  Screen:  ${SCREEN_W}x${SCREEN_H}"
echo "  VGA:     $VGA_DEVICE"
echo "  Audio:   ${AUDIO_DRIVER:-none}"
echo "  Network: wired virtio-net (user NAT, ssh localhost:2222)"
echo "  UEFI:    $([ "$USE_UEFI" -eq 1 ] && echo yes || echo no)"
echo "  Power:   ACPI power button (q35); no battery device in this QEMU"
echo ""

if [ -n "$DISPLAY_BACKEND" ]; then
	display_args="-display $DISPLAY_BACKEND"
else
	display_args="-nographic"
fi

# shellcheck disable=SC2086
set -- \
	-name dogeos \
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
	-device usb-kbd,bus=xhci.0 \
	-device virtio-rng-pci \
	-device virtio-balloon-pci \
	-device "$VGA_DEVICE" \
	$display_args \
	-boot order=d,menu=on,splash-time=5000

if [ "$USE_UEFI" -eq 1 ]; then
	set -- "$@" \
		-drive if=pflash,format=raw,readonly=on,file="$OVMF_DIR/OVMF_CODE.fd" \
		-drive if=pflash,format=raw,file="$OVMF_VARS"
fi

if [ -n "$AUDIO_DRIVER" ]; then
	set -- "$@" -audio "$AUDIO_DRIVER,model=hda"
fi

# shellcheck disable=SC2086
if [ -n "$EXTRA_USB" ]; then
	set -- "$@" $EXTRA_USB
fi

exec qemu-system-x86_64 "$@"
