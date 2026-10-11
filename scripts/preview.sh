#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
mkdir -p build/previews
for theme in light dark; do
    build/Kaleido.app/Contents/MacOS/Kaleido --preview "--$theme" --export-preview "$PWD/build/previews/$theme.png"
done
build/Kaleido.app/Contents/MacOS/Kaleido --preview --light --preview-overflow --export-preview "$PWD/build/previews/overflow.png"
