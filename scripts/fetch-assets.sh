#!/usr/bin/env bash
#
# Fetches the two binary/vector assets LoudFlow needs but does not commit:
#   1. Nunito (variable TTF, weights 400–800) → Resources/Fonts/Nunito.ttf
#   2. The exact Solar (Iconify) icons named in the design spec → asset catalog imagesets
#
# Run once after cloning:   ./scripts/fetch-assets.sh
# Safe to re-run (idempotent). Requires: curl.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FONTS_DIR="$ROOT/Resources/Fonts"
ASSETS_DIR="$ROOT/Resources/Assets.xcassets"

mkdir -p "$FONTS_DIR" "$ASSETS_DIR"

echo "==> Fetching Nunito (variable font)…"
# Upright variable font straight from the Google Fonts repo. macOS 13+ renders
# variable fonts; Typography.swift pins the discrete weights via the 'wght' axis.
curl -fsSL \
  "https://raw.githubusercontent.com/google/fonts/main/ofl/nunito/Nunito%5Bwght%5D.ttf" \
  -o "$FONTS_DIR/Nunito.ttf"
echo "    → Resources/Fonts/Nunito.ttf"

# Every Solar icon the spec references, plus the two added with the app owner's sign-off
# (danger-triangle-bold for the widget error states, key-bold-duotone for the Settings key
# card) and the three that came in with design v4: users-group-rounded-bold-duotone for
# meetings, pen-bold-duotone for renaming a voice, info-circle-bold-duotone for
# "Where your audio goes".
ICONS=(
  "microphone-3-bold"
  "soundwave-bold-duotone"
  "folder-with-files-bold-duotone"
  "settings-bold-duotone"
  "chart-square-bold-duotone"
  "database-bold-duotone"
  "restart-bold-duotone"
  "copy-bold-duotone"
  "alt-arrow-right-bold"
  "play-bold"
  "pause-bold"
  "check-circle-bold"
  "trash-bin-trash-bold-duotone"
  "cursor-bold-duotone"
  "keyboard-bold-duotone"
  "hand-stars-bold-duotone"
  "history-bold-duotone"
  "text-field-bold-duotone"
  "stopwatch-bold-duotone"
  "stop-bold"
  "text-square-bold"
  "danger-triangle-bold"
  "key-bold-duotone"
  "users-group-rounded-bold-duotone"
  "pen-bold-duotone"
  "info-circle-bold-duotone"
)

echo "==> Fetching ${#ICONS[@]} Solar icons from the Iconify API…"
for name in "${ICONS[@]}"; do
  asset="solar-$name"
  set_dir="$ASSETS_DIR/$asset.imageset"
  mkdir -p "$set_dir"
  # Plain currentColor SVG so the asset renders as a tintable template image.
  curl -fsSL "https://api.iconify.design/solar/$name.svg" -o "$set_dir/$asset.svg"
  cat > "$set_dir/Contents.json" <<JSON
{
  "images" : [
    {
      "filename" : "$asset.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
JSON
  echo "    → $asset"
done

echo ""
echo "Done. Next:"
echo "  xcodegen generate   # regenerate LoudFlow.xcodeproj so it sees the new files"
echo "  open LoudFlow.xcodeproj"
