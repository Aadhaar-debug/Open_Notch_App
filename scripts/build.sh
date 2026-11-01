#!/bin/bash
# Builds build/OpenNotch.app (release, ad-hoc signed). Needs only the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/OpenNotch.app
swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release
BIN=$(swift build -c release --show-bin-path 2>/dev/null)/OpenNotch
[ -f "$BIN" ] || BIN=$(find .build -path '*release/OpenNotch' -type f -perm +111 | head -1)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon
if [ ! -f build/AppIcon.icns ]; then
    ICONSET=build/AppIcon.iconset
    mkdir -p "$ICONSET"
    swift scripts/make-icon.swift build/icon-1024.png
    for s in 16 32 128 256 512; do
        sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"
