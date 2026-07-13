.PHONY: build run clean

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))

build:
	@sh "$(ROOT)/scripts/build.sh"

run:
	@sh "$(ROOT)/scripts/run.sh"

clean:
	@sh "$(ROOT)/scripts/clean.sh"
