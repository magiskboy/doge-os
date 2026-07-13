#!/bin/sh
set -e

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
ERRORS=0

warn() {
	echo "warning: $*" >&2
}

fail() {
	echo "error: $*" >&2
	ERRORS=$((ERRORS + 1))
}

ok() {
	echo "ok: $*"
}

ARCH="$(uname -m)"
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "amd64" ]; then
	fail "host architecture must be amd64/x86_64 (got $ARCH)"
else
	ok "architecture $ARCH"
fi

AVAIL_KB="$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')"
REQUIRED_KB=$((15 * 1024 * 1024))
if [ "$AVAIL_KB" -lt "$REQUIRED_KB" ]; then
	warn "less than 15 GB free on $ROOT (have ~$((AVAIL_KB / 1024 / 1024)) GB)"
else
	ok "disk space sufficient (~$((AVAIL_KB / 1024 / 1024)) GB free)"
fi

IS_DEBIAN_TRIXIE=0
if [ -f /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	echo "host OS: ${PRETTY_NAME:-unknown}"
	case "${ID:-}:${VERSION_CODENAME:-}" in
		debian:trixie) IS_DEBIAN_TRIXIE=1 ;;
	esac
fi

if [ "$IS_DEBIAN_TRIXIE" -eq 1 ]; then
	ok "native Debian Trixie build supported"
	if command -v lb >/dev/null 2>&1; then
		ok "live-build installed"
	else
		warn "live-build not installed; run 'make deps' on Debian Trixie for native builds"
	fi
else
	RUNTIME="$("$ROOT/scripts/detect-runtime.sh" 2>/dev/null || echo none)"
	if [ "$RUNTIME" = none ]; then
		fail "container runtime required (install podman or docker)"
	else
		ok "container runtime: $RUNTIME"
	fi
fi

if [ -r /dev/kvm ]; then
	ok "KVM available for ISO testing"
else
	warn "KVM not available; 'make test' will use software emulation"
fi

if command -v qemu-system-x86_64 >/dev/null 2>&1; then
	ok "qemu-system-x86_64 installed"
else
	warn "qemu-system-x86_64 not installed; install qemu-kvm for 'make test'"
fi

if [ -f /etc/selinux/config ] && command -v getenforce >/dev/null 2>&1; then
	SELINUX_MODE="$(getenforce 2>/dev/null || echo Disabled)"
	if [ "$SELINUX_MODE" = Enforcing ]; then
		ok "SELinux enforcing — container mounts use :Z flag"
	fi
fi

if [ "$ERRORS" -gt 0 ]; then
	echo ""
	echo "$ERRORS check(s) failed."
	exit 1
fi

echo ""
echo "All required checks passed."
