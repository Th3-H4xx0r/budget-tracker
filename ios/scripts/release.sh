#!/bin/bash
# Build MoneyMatter for the iPhone and publish it as an over-the-air update: the app shows
# "Update available" the next time it opens and installs the build from the MoneyMatter server.
#   ios/scripts/release.sh --notes "• Faster sync
#   • New widget sizes"
#   ios/scripts/release.sh --no-publish        # just archive + export the IPA
# Every build gets a build number (UTC yyDDDHHMM) so the app can tell an older build from a
# newer one; BUILD_NUMBER=N overrides it. Builds the checkout as it stands, uncommitted edits
# included. One-time setup and publish settings: ios/scripts/README.md.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ios/scripts/release.sh [--notes "<release notes>"] [--no-publish]

Archives MoneyMatter (Release), exports a development-signed IPA to ios/build/ota/export/
and uploads it with ios/scripts/publish-app-update.sh.

  --notes <text>   What's new, one "• " line per item; shown with the update in the app
  --no-publish     Stop after exporting the IPA
  -h, --help       Show this help

Environment:
  BUILD_NUMBER       Build number to stamp (default: UTC yyDDDHHMM)
  DEVELOPMENT_TEAM   Apple Team ID to sign with (default: VY5CNF8734)
  OUT                Output directory, relative to ios/ (default: build/ota)
EOF
}

cd "$(dirname "$0")/.."
TEAM="${DEVELOPMENT_TEAM:-VY5CNF8734}"
OUT="${OUT:-build/ota}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%y%j%H%M)}"
notes="" publish=1
while [ $# -gt 0 ]; do
  case "$1" in
    --notes) [ $# -ge 2 ] || { echo "--notes needs a value" >&2; exit 2; }; notes="$2"; shift 2 ;;
    --no-publish) publish=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
# The server never offers an update to a build below 2, which it treats as an unstamped
# development build (the project's own CURRENT_PROJECT_VERSION is 1), so an iPhone running a
# build stamped 1 would never update again.
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] && [ "$BUILD_NUMBER" -gt 1 ] \
  || { echo "BUILD_NUMBER must be an integer greater than 1, got: $BUILD_NUMBER" >&2; exit 2; }

mkdir -p "$OUT"
ARCHIVE="$OUT/MoneyMatter.xcarchive"
echo "==> Archiving build $BUILD_NUMBER (team $TEAM)"
rm -rf "$ARCHIVE"
# CURRENT_PROJECT_VERSION on the command line stamps the app and the widget extension alike, so
# both carry the same CFBundleVersion. ENABLE_DEBUG_DYLIB=NO keeps the app a single binary, as in
# deploy-iphone.sh.
xcodebuild -project MoneyMatter.xcodeproj -scheme MoneyMatter -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  ENABLE_DEBUG_DYLIB=NO \
  archive > "$OUT/archive.log" 2>&1 \
  || { grep -E "error:" "$OUT/archive.log" | head -20 || true; tail -15 "$OUT/archive.log"; echo "full log: $OUT/archive.log" >&2; exit 1; }

echo "==> Exporting development-signed IPA"
# "debugging" signs with the development profile; iOS installs the IPA only on the iPhones that
# profile lists, which is what lets it install over the air without TestFlight.
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>debugging</string>
<key>teamID</key><string>$TEAM</string>
<key>signingStyle</key><string>automatic</string>
<key>thinning</key><string>&lt;none&gt;</string>
</dict></plist>
EOF
rm -rf "$OUT/export"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" -allowProvisioningUpdates > "$OUT/export.log" 2>&1 \
  || { tail -30 "$OUT/export.log"; echo "full log: $OUT/export.log" >&2; exit 1; }
IPA=""
for candidate in "$OUT"/export/*.ipa; do
  [ -f "$candidate" ] && { IPA="$candidate"; break; }
done
[ -n "$IPA" ] || { echo "export produced no .ipa in $OUT/export (see $OUT/export.log)" >&2; exit 1; }
case "$IPA" in /*) ;; *) IPA="$PWD/$IPA" ;; esac
echo "ipa:   $IPA"
echo "build: $BUILD_NUMBER"
[ "$publish" = 1 ] || exit 0
scripts/publish-app-update.sh --file "$IPA" --build "$BUILD_NUMBER" --notes "$notes"
