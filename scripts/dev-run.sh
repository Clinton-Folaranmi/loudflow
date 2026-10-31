#!/usr/bin/env bash
#
# Fast iteration loop: incremental Debug build, sign with the stable identity, relaunch.
#
# Runs the app straight out of DerivedData — no /Applications install, no zip. Use
# scripts/dev-build.sh instead when you want to install or share a build.
#
# It is the same bundle id and uses the configured signing identity as the installed app, so it reads
# the same clips and keeps the Accessibility grant.
#
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"

IDENTITY="${LOUDFLOW_SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" && -s build/signing-identity ]]; then
  IFS= read -r IDENTITY < build/signing-identity
fi
IDENTITY="${IDENTITY:-LoudFlow Self-Signed}"
APP="build/dd/Build/Products/Debug/LoudFlow.app"

# Cheap (~0.1s) and required whenever a source file is added or removed.
xcodegen generate >/dev/null

echo "==> Building (Debug, incremental)…"
xcodebuild -project LoudFlow.xcodeproj -scheme LoudFlow -configuration Debug \
  -derivedDataPath build/dd ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build >/tmp/lf_dev_run.log 2>&1 \
  || { echo "BUILD FAILED:"; grep -E "error:" /tmp/lf_dev_run.log | head -20; exit 1; }

# Keep one code identity across builds so macOS can keep the Accessibility grant.
if ! codesign --force --deep --sign "$IDENTITY" "$APP"; then
  echo "Signing failed. Set LOUDFLOW_SIGNING_IDENTITY to a certificate fingerprint or run scripts/dev-signing-setup.sh, then retry." >&2
  exit 1
fi

pkill -f "LoudFlow.app/Contents/MacOS/LoudFlow" 2>/dev/null || true
sleep 0.5
open "$APP"
echo "==> Running $APP"
