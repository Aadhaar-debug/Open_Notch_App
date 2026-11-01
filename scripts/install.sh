#!/bin/bash
# Builds OpenNotch, installs it to /Applications (or ~/Applications) and launches it.
# On first launch the app registers itself under Login Items › "Open at Login".
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh

DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

pkill -x OpenNotch 2>/dev/null && sleep 0.5 || true
rm -rf "$DEST/OpenNotch.app"
cp -R build/OpenNotch.app "$DEST/"
xattr -dr com.apple.quarantine "$DEST/OpenNotch.app" 2>/dev/null || true

open "$DEST/OpenNotch.app"
echo "Installed to $DEST/OpenNotch.app and launched."
