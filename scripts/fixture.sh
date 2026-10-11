#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
bundle=build/WindowFixture.app
mkdir -p "$bundle/Contents/MacOS"
swiftc scripts/WindowFixture.swift -o "$bundle/Contents/MacOS/WindowFixture"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.waynexia.Kaleido.WindowFixture</string>
<key>CFBundleExecutable</key><string>WindowFixture</string>
<key>CFBundleName</key><string>Window Fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
codesign --force --sign - "$bundle"
if [[ "${1:-}" != "--build-only" ]]; then
    open "$bundle"
fi
