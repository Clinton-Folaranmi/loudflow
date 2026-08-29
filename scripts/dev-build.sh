#!/usr/bin/env bash
#
# Build LoudFlow (Release), sign it with the stable self-signed identity so the Accessibility
# grant survives rebuilds, install to /Applications, and drop a versioned zip on the Desktop.
#
# One-time setup of the signing identity lives in scripts/dev-signing-setup.sh.
#
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"

IDENTITY="LoudFlow Self-Signed"
APP="build/dd/Build/Products/Release/LoudFlow.app"

echo "==> Generating project…"
xcodegen generate >/dev/null

echo "==> Building (Release)…"
xcodebuild -project LoudFlow.xcodeproj -scheme LoudFlow -configuration Release \
  -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build >/tmp/lf_build.log 2>&1 \
  || { echo "BUILD FAILED:"; tail -30 /tmp/lf_build.log; exit 1; }

# Try the stable identity directly — untrusted self-signed identities work for codesign even
# though `find-identity` won't list them. Fall back to ad-hoc only if signing actually fails.
echo "==> Signing…"
if codesign --force --deep --sign "$IDENTITY" "$APP" 2>/tmp/lf_sign.log; then
  echo "    signed with '$IDENTITY' (Accessibility grant persists across rebuilds)"
else
  echo "    '$IDENTITY' unavailable — ad-hoc (run scripts/dev-signing-setup.sh to make grants stick)"
  codesign --force --deep --sign - "$APP"
fi

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
