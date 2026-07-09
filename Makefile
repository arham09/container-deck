SHELL := /bin/bash

APP_NAME := ContainerDeck
BUILD_DIR := .build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
DMG := $(BUILD_DIR)/$(APP_NAME).dmg
CONFIG ?= release
TEST_ARGS ?=

.DEFAULT_GOAL := help

.PHONY: help verify build release test app dmg installer package icon clean

help:
	@printf "%s\n" \
		"ContainerDeck build targets:" \
		"  make build       Build the Swift package in debug mode" \
		"  make release     Build the Swift package in release mode" \
		"  make test        Run the test suite (pass TEST_ARGS='--filter ...')" \
		"  make app         Build $(APP_BUNDLE) (CONFIG=$(CONFIG))" \
		"  make dmg         Build $(DMG)" \
		"  make installer   Alias for make dmg" \
		"  make verify      Check local toolchain and Apple Container setup" \
		"  make icon        Regenerate Resources/AppIcon.icns from logo.png" \
		"  make clean       Remove SwiftPM build artifacts" \
		"" \
		"Signing: DEVELOPER_ID='Developer ID Application: Name (TEAMID)' make dmg"

verify:
	scripts/verify-environment.sh

# Result: $(BUILD_DIR)/debug/$(APP_NAME) (bare executable)
build:
	swift build

# Result: $(BUILD_DIR)/release/$(APP_NAME) (bare executable)
release:
	swift build -c release

# No artifact — prints pass/fail results to stdout.
test:
	scripts/test.sh $(TEST_ARGS)

# Result: $(APP_BUNDLE) (launchable, ad-hoc-signed .app bundle)
app:
	scripts/make-app-bundle.sh $(CONFIG)
	@printf "Created %s\n" "$(APP_BUNDLE)"

# Result: $(DMG) (distributable disk image containing the .app)
dmg:
	scripts/package-release.sh
	@printf "Created %s\n" "$(DMG)"

installer: dmg

package: dmg

# Result: Resources/AppIcon.icns
icon:
	scripts/make-app-icon.sh

# Removes the $(BUILD_DIR)/ directory and all build artifacts above.
clean:
	swift package clean
