#!/usr/bin/env bash
#
# Build LoudFlow (Release), sign it with a stable local identity so the Accessibility
# grant survives rebuilds, install to /Applications, and drop a versioned zip on the Desktop.
#
# One-time setup of the signing identity lives in scripts/dev-signing-setup.sh.
#
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"

IDENTITY="${LOUDFLOW_SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" && -s build/signing-identity ]]; then
  IFS= read -r IDENTITY < build/signing-identity
fi
IDENTITY="${IDENTITY:-LoudFlow Self-Signed}"
APP="build/dd/Build/Products/Release/LoudFlow.app"

echo "==> Generating project…"
xcodegen generate >/dev/null

echo "==> Building (Release)…"
xcodebuild -project LoudFlow.xcodeproj -scheme LoudFlow -configuration Release \
  -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build >/tmp/lf_build.log 2>&1 \
  || { echo "BUILD FAILED:"; tail -30 /tmp/lf_build.log; exit 1; }

# Keep one code identity across builds so macOS can keep the Accessibility grant.
echo "==> Signing…"
if ! codesign --force --deep --sign "$IDENTITY" "$APP"; then
  echo "Signing failed. Set LOUDFLOW_SIGNING_IDENTITY to a certificate fingerprint or run scripts/dev-signing-setup.sh, then retry." >&2
  exit 1
fi
echo "    signed with '$IDENTITY' (Accessibility grant persists across rebuilds)"

echo "==> Installing to /Applications…"
pkill -f "/Applications/LoudFlow.app/Contents/MacOS/LoudFlow" 2>/dev/null || true
sleep 1
rm -rf /Applications/LoudFlow.app
cp -R "$APP" /Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/LoudFlow.app || true

VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/LoudFlow.app/Contents/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" /Applications/LoudFlow.app/Contents/Info.plist)
ZIP="$HOME/Desktop/LoudFlow-$VER.zip"
ditto -c -k --sequesterRsrc --keepParent /Applications/LoudFlow.app "$ZIP"

echo ""
echo "Done: LoudFlow $VER ($BUILD)"
echo "  installed: /Applications/LoudFlow.app"
echo "  shareable: $ZIP"
codesign -dv --verbose=2 /Applications/LoudFlow.app 2>&1 | grep -E "Authority|Signature=" | head -2
