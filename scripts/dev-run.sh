#!/usr/bin/env bash
#
# Fast iteration loop: incremental Debug build, sign with the stable identity, relaunch.
#
# Runs the app straight out of DerivedData — no /Applications install, no zip. Use
# scripts/dev-build.sh instead when you want to install or share a build.
#
# It is the same bundle id and the same signing identity as the installed app, so it reads
# the same clips and keeps the Accessibility grant.
#
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"

IDENTITY="LoudFlow Self-Signed"
APP="build/dd/Build/Products/Debug/LoudFlow.app"

# Cheap (~0.1s) and required whenever a source file is added or removed.
xcodegen generate >/dev/null

echo "==> Building (Debug, incremental)…"
xcodebuild -project LoudFlow.xcodeproj -scheme LoudFlow -configuration Debug \
  -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO build >/tmp/lf_dev_run.log 2>&1 \
  || { echo "BUILD FAILED:"; grep -E "error:" /tmp/lf_dev_run.log | head -20; exit 1; }

# Same identity as the installed build, so Accessibility / mic grants carry over.
codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null || codesign --force --sign - "$APP"

pkill -f "LoudFlow.app/Contents/MacOS/LoudFlow" 2>/dev/null || true
sleep 0.5
open "$APP"
echo "==> Running $APP"
