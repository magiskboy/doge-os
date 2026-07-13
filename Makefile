.PHONY: check deps config build build-native build-container test clean clean-all

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ISO_NAME := lotus-os-trixie-amd64.hybrid.iso
ISO_PATH := $(ROOT)/output/$(ISO_NAME)

check:
	@sh "$(ROOT)/scripts/check-host.sh"

deps:
	@if [ -f /etc/debian_version ]; then \
		sudo apt-get update && sudo apt-get install -y \
			live-build live-boot live-config live-manual \
			debootstrap squashfs-tools xorriso isolinux syslinux-utils \
			grub-pc-bin grub-efi-amd64-bin mtools dosfstools fakeroot \
			make git sudo; \
	else \
		echo "deps target is for Debian hosts only; use container build on other distros"; \
		exit 1; \
	fi

config:
	@sh ./auto/config

build-native: config
	@fakeroot lb build
	@mkdir -p output
	@cp -f live-image-amd64.hybrid.iso "$(ISO_PATH)"
	@echo "ISO written to $(ISO_PATH)"

build-container:
	@sh "$(ROOT)/scripts/build-in-container.sh"

build:
	@if [ -f /etc/os-release ]; then \
		. /etc/os-release; \
		if [ "$${ID:-}" = debian ] && [ "$${VERSION_CODENAME:-}" = trixie ] && command -v lb >/dev/null 2>&1; then \
			$(MAKE) build-native; \
		else \
			$(MAKE) build-container; \
		fi; \
	else \
		$(MAKE) build-container; \
	fi

test:
	@sh "$(ROOT)/scripts/test-iso.sh"

test-reset:
	@rm -rf "$(ROOT)/output/test-vm"
	@echo "Removed test VM data under output/test-vm/"

clean:
	@sh "$(ROOT)/scripts/clean-artifacts.sh"

clean-all: clean
	@RUNTIME=$$(sh "$(ROOT)/scripts/detect-runtime.sh" 2>/dev/null || echo none); \
	if [ "$$RUNTIME" != none ]; then \
		$$RUNTIME volume rm lotus-os-cache 2>/dev/null || true; \
	fi
