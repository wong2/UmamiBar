#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP="build/UmamiBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$(swift build -c release --show-bin-path)/UmamiBar" "$APP/Contents/MacOS/UmamiBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Signing preference: real Developer ID (release) > local dev cert (stable
# cdhash so keychain grants survive rebuilds) > ad-hoc (re-prompts every build).
DEV_KEYCHAIN="$PWD/.dev-cert/dev.keychain-db"
DEV_ID=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
if [[ -n "$DEV_ID" ]]; then
    codesign --force --deep --sign "$DEV_ID" --options runtime --timestamp "$APP"
elif security find-certificate -c "UmamiBar Dev" "$DEV_KEYCHAIN" >/dev/null 2>&1; then
    codesign --force --deep --sign "UmamiBar Dev" --keychain "$DEV_KEYCHAIN" "$APP"
else
    codesign --force --deep --sign - "$APP"
fi

echo "Built $APP"
