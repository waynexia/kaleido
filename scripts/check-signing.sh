#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${CODE_SIGN_IDENTITY:-Kaleido Local Development}" == "-" ]]; then
    printf 'Skipping persistent identity check for explicit ad-hoc build.\n'
    exit 0
fi

requirement() {
    codesign -d -r- "$1" 2>&1 | sed -n 's/^designated => //p'
}
code_hash() {
    codesign -d --verbose=4 "$1" 2>&1 | sed -n 's/^CDHash=//p'
}

original=build/Kaleido.app
original_requirement="$(requirement "$original")"
original_hash="$(code_hash "$original")"
case "$original_requirement" in
    *certificate*|*anchor*) ;;
    *) printf 'Expected a certificate-bound signing requirement.\n' >&2; exit 1 ;;
esac
test -n "$original_hash"

# Change signed contents without modifying or launching the installed app.
scratch="$(mktemp -d "$PWD/build/signing-check.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
candidate="$scratch/Kaleido.app"
ditto "$original" "$candidate"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$candidate/Contents/Info.plist")"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version.1" "$candidate/Contents/Info.plist"
./scripts/sign-app.sh "$candidate"
test "$(requirement "$candidate")" = "$original_requirement"
candidate_hash="$(code_hash "$candidate")"
test -n "$candidate_hash"
test "$candidate_hash" != "$original_hash"
printf 'Changed bundle contents retain the same certificate-bound identity.\n'
