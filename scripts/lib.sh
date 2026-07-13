#!/bin/sh
# Shared helpers for Lotus OS build scripts. Source from other scripts:
#   . "$(dirname "$0")/lib.sh"

ROOT="$(CDPATH= cd -- "$(dirname "$0")" && pwd)/.."
ROOT="$(CDPATH= cd -- "$ROOT" && pwd)"
ISO_NAME="lotus-os-trixie-amd64.hybrid.iso"
ISO_PATH="$ROOT/output/$ISO_NAME"
IMAGE_NAME="lotus-os-builder:trixie"

detect_runtime() {
	if command -v podman >/dev/null 2>&1; then
		echo podman
	elif command -v docker >/dev/null 2>&1; then
		echo docker
	else
		echo none
	fi
}

selinux_mount() {
	if [ -f /etc/os-release ]; then
		# shellcheck disable=SC1091
		. /etc/os-release
		case "${ID:-}" in
			fedora|centos|rhel) echo ":Z"; return ;;
		esac
	fi
	echo ""
}
