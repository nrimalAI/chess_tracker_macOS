#!/bin/bash
# Renders the sticky-note panel to a PNG for design review.
#   ./Scripts/render_preview.sh [output.png]
set -euo pipefail
cd "$(dirname "$0")/.."

OUTPUT="${1:-panel-preview.png}"
# Optional second argument: "pinned" to preview the pinned state.
STATE="${2:-}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cp Scripts/render_preview.swift "$WORK/main.swift"

swiftc -target arm64-apple-macos14.0 \
    Sources/Tracking/HostMatcher.swift \
    Sources/Tracking/BrowserBridge.swift \
    Sources/Tracking/IdleMonitor.swift \
    Sources/Tracking/Poller.swift \
    Sources/Data/UsageStore.swift \
    Sources/App/AppSettings.swift \
    Sources/UI/DesktopPanel.swift \
    Sources/UI/PanelView.swift \
    "$WORK/main.swift" \
    -o "$WORK/preview"

"$WORK/preview" "$OUTPUT" "$STATE"
