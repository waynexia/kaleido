#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
plutil -lint Resources/Info.plist
codesign --verify --strict build/Kaleido.app
test -x build/Kaleido.app/Contents/MacOS/Kaleido
build/Kaleido.app/Contents/MacOS/Kaleido --self-check
