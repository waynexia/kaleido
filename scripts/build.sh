#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
configuration="${CONFIGURATION:-debug}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
bundle=build/Kaleido.app
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/Kaleido" "$bundle/Contents/MacOS/Kaleido"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" --identifier dev.waynexia.Kaleido "$bundle"
printf 'Built %s/%s\n' "$PWD" "$bundle"
