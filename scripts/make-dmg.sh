#!/usr/bin/env bash
#
# Builds the branded installer DMG (background + drag-to-Applications layout) for the app
# currently in /Applications. Uses dmgbuild (writes the .DS_Store directly — no Finder
# scripting, so it won't hang on automation prompts).
#
set -euo pipefail
cd "$(dirname "$0")/.."

APP="/Applications/LoudFlow.app"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

echo "==> Rendering background…"
swift scripts/make-dmg-bg.swift >/dev/null

if [ ! -x .dmgvenv/bin/dmgbuild ]; then
  echo "==> Setting up dmgbuild (one-time)…"
  python3 -m venv .dmgvenv
  .dmgvenv/bin/pip install --quiet --upgrade pip
  .dmgvenv/bin/pip install --quiet dmgbuild
fi

OUT="$HOME/Desktop/LoudFlow-$VER.dmg"
rm -f "$OUT"
echo "==> Building $OUT …"
.dmgvenv/bin/dmgbuild \
  -s scripts/dmg-settings.py \
  -D app="$APP" -D bg="$(pwd)/scripts/dmg-bg.png" \
  "LoudFlow $VER" "$OUT"

echo ""
echo "Done: $OUT ($(du -h "$OUT" | cut -f1))"
