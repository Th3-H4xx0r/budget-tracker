#!/bin/bash
# Build, sign and install MoneyMatter on the connected iPhone, in Release — one command, no Xcode.
# Adapted from jarvis-copilot/ios_app/deploy-both.sh (iPhone only; no watch target here).
#
# Prereqs: iPhone paired and unlocked, Developer Mode on, signed into your Apple ID in Xcode.
# Usage:   DEVELOPMENT_TEAM=ABCDE12345 ./ios/deploy-iphone.sh
#          (Team ID: Xcode > Settings > Accounts, or developer.apple.com > Membership.)
set -euo pipefail
cd "$(dirname "$0")"

: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Team ID, e.g. DEVELOPMENT_TEAM=ABCDE12345 $0}"

# The identifier is whatever sits in the "(UDID)" column — read it, don't guess its shape. Simulators
# use an 8-4-4-4-12 UUID; a modern iPhone uses 8-16 hex, which a UUID pattern silently fails to match.
udid_of() { sed -E 's/.*[[:space:]]([0-9A-Fa-f][0-9A-Fa-f-]+)[[:space:]]+\(UDID\).*/\1/'; }
BUNDLE_ID="com.pranavkrishna.budgettracker"
APP="build/dd/Build/Products/Release-iphoneos/MoneyMatter.app"
LOG="${TMPDIR:-/tmp}/moneymatter-build.log"

echo "==> Detecting devices"
DEV="$(xcrun devicectl list devices 2>/dev/null || true)"
# Only real, paired hardware: "connected" when cabled and trusted, "available (paired)" over the
# network. Simulators carry "simulated" and fail later with "Install Application is not supported".
REAL="$(printf '%s\n' "$DEV" | grep -v simulated | grep -E "available|connected" || true)"
IPHONE_ID="${IPHONE_ID:-$(printf '%s\n' "$REAL" | grep -i iphone | udid_of | head -1 || true)}"
echo "    iPhone=${IPHONE_ID:-<none>}"
[ -n "$IPHONE_ID" ] || { echo "✗ no iPhone connected — unlock it and check Developer Mode"; exit 1; }

echo "==> Building Release (automatic signing, team $DEVELOPMENT_TEAM)"
# ENABLE_DEBUG_DYLIB=NO keeps everything in one binary; otherwise Xcode splits the app into a
# launcher plus a .debug.dylib, and dyld refuses to load it on device if a nested Mach-O is unsigned.
xcodebuild -project MoneyMatter.xcodeproj -scheme MoneyMatter \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath build/dd \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" CODE_SIGN_STYLE=Automatic \
  ENABLE_DEBUG_DYLIB=NO \
  build > "$LOG" 2>&1 || { tail -30 "$LOG"; exit 1; }

echo "==> Verifying the Associated Domains entitlement (passkeys)"
if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "webcredentials:"; then
  echo "    webcredentials present"
else
  echo "    WARNING: no webcredentials entitlement — passkey sign-in will not work"
fi

echo "==> Installing on the iPhone"
xcrun devicectl device install app --device "$IPHONE_ID" "$APP" | tail -3

echo "==> Launching"
xcrun devicectl device process launch --device "$IPHONE_ID" --terminate-existing "$BUNDLE_ID" | tail -2

echo "✓ Done."
