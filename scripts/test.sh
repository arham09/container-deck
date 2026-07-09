#!/bin/bash
# Runs the ContainerDeck test suite.
#
# With CommandLineTools (no Xcode), Testing.framework exists but SwiftPM does
# not add its search path, and the _Testing_Foundation cross-import overlay
# ships without a swiftmodule — so we pass the framework path explicitly and
# disable cross-import overlays. Under a full Xcode toolchain a plain
# `swift test` also works.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FWK=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
# Newer CommandLineTools ship the Swift Testing interop dylib
# (lib_TestingInterop.dylib) here rather than inside Testing.framework, so it
# needs its own rpath or the test bundle fails to dlopen at launch.
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

FLAGS=()
if [ -d "$FWK" ] && ! xcodebuild -version >/dev/null 2>&1; then
    FLAGS+=(
        -Xswiftc -F"$FWK"
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
        -Xlinker -F"$FWK"
        -Xlinker -rpath -Xlinker "$FWK"
    )
    if [ -d "$LIB" ]; then
        FLAGS+=(-Xlinker -rpath -Xlinker "$LIB")
    fi
fi

# Pass through extra arguments (e.g. --filter).
swift test --package-path "$ROOT" "${FLAGS[@]}" "$@"
