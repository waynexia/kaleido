#!/bin/bash
set -euo pipefail

# A persistent certificate keeps the designated requirement stable across builds.
# Never fall back to ad-hoc signing when that identity is unavailable.
identity="${CODE_SIGN_IDENTITY:-Kaleido Local Development}"
if [[ "$identity" == "-" ]]; then
    printf 'Using explicit ad-hoc signing; system permissions may not survive updates.\n' >&2
fi
if ! codesign --force --sign "$identity" --identifier dev.waynexia.Kaleido "${1:?Usage: sign-app.sh APP_PATH}"; then
    printf 'Signing failed for "%s". See docs/code-signing.md; the signing identity must be kept across builds.\n' "$identity" >&2
    exit 1
fi
codesign --verify --strict "$1"
