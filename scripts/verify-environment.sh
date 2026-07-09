#!/bin/bash
# Verifies the development environment for ContainerDeck.
set -u

status=0

note() { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; status=1; }

note "== ContainerDeck environment check =="

# Architecture
arch="$(uname -m)"
if [ "$arch" = "arm64" ]; then
    note "OK: Apple silicon ($arch)"
else
    fail "Apple silicon required, found $arch"
fi

# macOS version
macos_version="$(sw_vers -productVersion)"
note "macOS: $macos_version (project deployment target: 15.0)"

# Swift toolchain
if command -v swift >/dev/null 2>&1; then
    note "Swift: $(swift --version 2>&1 | head -1)"
else
    fail "swift not found"
fi

# Apple Container CLI (optional for building; required for real integration)
if command -v container >/dev/null 2>&1; then
    note "container: $(command -v container)"
    note "container version: $(container system version --format json 2>/dev/null || echo 'version query failed')"
    container system status >/dev/null 2>&1
    case $? in
        0) note "container system: running" ;;
        *) note "container system: not running (status exit code is non-zero when stopped; this is expected)" ;;
    esac
else
    note "container: NOT INSTALLED — build and mock tests still work; real integration tests will be skipped"
fi

exit $status
