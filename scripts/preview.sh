#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
mkdir -p build/previews
for theme in light dark; do
    build/Kaleido.app/Contents/MacOS/Kaleido --preview "--$theme" --export-preview "$PWD/build/previews/$theme.png"
    build/Kaleido.app/Contents/MacOS/Kaleido --preview --settings-preview "--$theme" --missing-permission \
        --export-preview "$PWD/build/previews/settings-missing-$theme.png"
    build/Kaleido.app/Contents/MacOS/Kaleido --preview --settings-preview "--$theme" \
        --export-preview "$PWD/build/previews/settings-ready-$theme.png"
done
build/Kaleido.app/Contents/MacOS/Kaleido --preview --light --preview-overflow --export-preview "$PWD/build/previews/overflow.png"
