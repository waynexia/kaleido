#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
bundle=build/Kaleido.app
ensure_stopped() {
    if pgrep -x Kaleido >/dev/null; then
        printf 'Quit Kaleido before replacing %s. Closing its settings window is not enough.\n' "$bundle" >&2
        exit 1
    fi
}
ensure_stopped

# An explicit disposable ad-hoc build must never overwrite an authorized certificate build.
if [[ -d "$bundle" && "${CODE_SIGN_IDENTITY:-Kaleido Local Development}" == "-" ]]; then
    existing_requirement="$(codesign -d -r- "$bundle" 2>&1)"
    case "$existing_requirement" in
        *certificate*|*anchor*)
            printf 'Refusing to replace the certificate-signed everyday build with ad-hoc signing. Use a separate checkout for disposable builds.\n' >&2
            exit 1 ;;
    esac
fi

configuration="${CONFIGURATION:-debug}"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
mkdir -p build
staging="$(mktemp -d "$PWD/build/.kaleido-build.XXXXXX")"
cleanup() {
    # Restore the last working bundle if installation was interrupted between renames.
    if [[ -d "$staging/previous.app" && ! -e "$bundle" ]]; then
        mv "$staging/previous.app" "$bundle"
    fi
    rm -rf "$staging"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
candidate="$staging/Kaleido.app"
mkdir -p "$candidate/Contents/MacOS" "$candidate/Contents/Resources"
cp "$binary_dir/Kaleido" "$candidate/Contents/MacOS/Kaleido"
cp Resources/Info.plist "$candidate/Contents/Info.plist"
./scripts/sign-app.sh "$candidate"
# Detect accidental replacement of the local signing certificate, even if its name is unchanged.
if [[ -d "$bundle" && "${CODE_SIGN_IDENTITY:-Kaleido Local Development}" == "Kaleido Local Development" ]]; then
    previous_requirement="$(codesign -d -r- "$bundle" 2>&1 | sed -n 's/^designated => //p')"
    case "$previous_requirement" in
        *certificate*|*anchor*)
            candidate_requirement="$(codesign -d -r- "$candidate" 2>&1 | sed -n 's/^designated => //p')"
            if [[ "$candidate_requirement" != "$previous_requirement" ]]; then
                printf 'The local signing identity changed. Keep the original certificate; the existing app has not been replaced.\n' >&2
                exit 1
            fi ;;
    esac
fi
plutil -lint "$candidate/Contents/Info.plist"
"$candidate/Contents/MacOS/Kaleido" --self-check
ensure_stopped
if [[ -e "$bundle" ]]; then mv "$bundle" "$staging/previous.app"; fi
mv "$candidate" "$bundle"
printf 'Built %s/%s\n' "$PWD" "$bundle"
