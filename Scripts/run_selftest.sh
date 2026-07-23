#!/bin/bash
# Compiles ChessTime's logic together with Scripts/selftest.swift and runs it.
# The app target itself is excluded (it owns @main).
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Swift only permits top-level statements in a file literally named main.swift.
cp Scripts/selftest.swift "$WORK/main.swift"

swiftc -target arm64-apple-macos14.0 \
    Sources/Tracking/HostMatcher.swift \
    Sources/Tracking/BrowserBridge.swift \
    Sources/Data/UsageStore.swift \
    "$WORK/main.swift" \
    -o "$WORK/selftest"

"$WORK/selftest"
