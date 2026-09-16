#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release

APP="build/UmamiBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$(swift build -c release --show-bin-path)/UmamiBar" "$APP/Contents/MacOS/UmamiBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Sign with the stable dev identity when available so keychain grants survive
# rebuilds; ad-hoc signing changes the cdhash every build and re-prompts.
DEV_KEYCHAIN="$PWD/.dev-cert/dev.keychain-db"
if security find-certificate -c "UmamiBar Dev" "$DEV_KEYCHAIN" >/dev/null 2>&1; then
    codesign --force --deep --sign "UmamiBar Dev" --keychain "$DEV_KEYCHAIN" "$APP"
else
    codesign --force --deep --sign - "$APP"
fi

echo "Built $APP"
