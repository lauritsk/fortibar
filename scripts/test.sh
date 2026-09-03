#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sdk=$(xcrun --sdk macosx --show-sdk-path)
architecture=$(uname -m)
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT INT TERM

xcrun swiftc -parse-as-library \
    -swift-version 6 \
    -target "${architecture}-apple-macos26.0" \
    -sdk "$sdk" \
    "$root/FortiFort/Shared/VPNValidation.swift" \
    "$root/FortiFort/Shared/SAMLLogin.swift" \
    "$root/FortiFortChecks/main.swift" \
    -o "$temporary_directory/validation-checks"
"$temporary_directory/validation-checks"

xcrun swiftc -typecheck -parse-as-library \
    -swift-version 6 \
    -target "${architecture}-apple-macos26.0" \
    -sdk "$sdk" \
    "$root"/FortiFort/Shared/*.swift \
    "$root"/FortiFort/App/*.swift

xcrun swiftc -typecheck \
    -swift-version 6 \
    -target "${architecture}-apple-macos26.0" \
    -sdk "$sdk" \
    -D FORTIFORT_ALLOW_HOMEBREW \
    "$root"/FortiFort/Shared/*.swift \
    "$root"/FortiFort/Helper/*.swift

echo "App and helper type checks passed"
