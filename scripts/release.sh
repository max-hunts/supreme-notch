#!/bin/sh
# Usage: scripts/release.sh VERSION BUILD. Needs the notary keychain profile on this Mac.
# Release build: Developer ID signed, notarized, stapled, zipped and installed.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SC=${SUPREMENOTCH_WORK_DIR:-${TMPDIR:-/tmp}/supremenotch-build}
mkdir -p "$SC"
VERSION=${1:?Usage: scripts/release.sh VERSION BUILD. Needs the notary keychain profile on this Mac.}
# Personal notarization login (team 36JR976L6Y). Never the Gaia profile.
NOTARY_PROFILE=${NOTARY_PROFILE:-max-hunt-notary}
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || { echo "Notary profile $NOTARY_PROFILE not found; create it first."; exit 1; }
BUILD=${2:?Usage: scripts/release.sh VERSION BUILD. Needs the notary keychain profile on this Mac.}
cd "$ROOT"
rm -rf "$SC/SupremeNotch.xcarchive" "$SC/export"
DD="$SC/DerivedData"
xcodebuild -project SupremeNotch.xcodeproj -scheme SupremeNotch -configuration Release -derivedDataPath "$SC/DerivedData" \
  -archivePath "$SC/SupremeNotch.xcarchive" archive DEVELOPMENT_TEAM=36JR976L6Y CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=Developer ID Application" OTHER_CODE_SIGN_FLAGS=--timestamp \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" > "$SC/archive.log" 2>&1 || { grep -E "error:" "$SC/archive.log" | sort -u | head -20; exit 1; }
grep -E "warning:" "$SC/archive.log" | grep "$ROOT/SupremeNotch/" | sed -E "s|.*$ROOT/SupremeNotch/||" | sort -u | head -10
xcodebuild -exportArchive -archivePath "$SC/SupremeNotch.xcarchive" -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" -exportPath "$SC/export" > "$SC/export.log" 2>&1
# Bundle the Rust claude-usage-monitor as a signed helper, then re-seal the app around it.
ID="Developer ID Application: Max Hunt (36JR976L6Y)"
# The usage monitor's source, kept in this repo.
MON=${USAGE_MONITOR_DIR:-$ROOT/usage-monitor}
APP="$SC/export/SupremeNotch.app"
(cd "$MON" && cargo build --release -q)
mkdir -p "$APP/Contents/Helpers"
cp "$MON/target/release/claude-usage-monitor" "$APP/Contents/Helpers/claude-usage-monitor"
codesign --force --options runtime --timestamp --sign "$ID" "$APP/Contents/Helpers/claude-usage-monitor"
codesign --force --options runtime --timestamp --sign "$ID" --preserve-metadata=entitlements,requirements,flags,runtime "$APP"
codesign --verify --deep --strict "$APP"
# Notarize, staple, then zip the stapled app for the release.
(cd "$SC/export" && rm -f notarize.zip && ditto -c -k --keepParent SupremeNotch.app notarize.zip)
xcrun notarytool submit "$SC/export/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1 | grep -E "id:|status:" | tail -2
xcrun stapler staple "$APP" | tail -1
spctl -a -vv -t exec "$APP" 2>&1 | head -2
(cd "$SC/export" && rm -f "SupremeNotch-$VERSION.zip" && ditto -c -k --keepParent SupremeNotch.app "SupremeNotch-$VERSION.zip")
osascript -e 'tell application id "com.maxhunt.supremenotch" to quit' 2>/dev/null || true
osascript -e 'tell application id "com.maxhunt.betternotch" to quit' 2>/dev/null || true
osascript -e 'tell application id "xyz.notchly.Notchly" to quit' 2>/dev/null || true
sleep 2
pgrep -x SupremeNotch >/dev/null && pkill -x SupremeNotch && sleep 1
# The app's earlier names: quit them and move their copies to the Trash.
for OLD in BetterNotch Notchly; do
  pgrep -x "$OLD" >/dev/null && pkill -x "$OLD" && sleep 1
  [ -d "/Applications/$OLD.app" ] && mv "/Applications/$OLD.app" "$HOME/.Trash/$OLD-$(date +%Y%m%d%H%M%S).app" || true
done
rm -rf /Applications/SupremeNotch.app
ditto "$APP" /Applications/SupremeNotch.app
open -a /Applications/SupremeNotch.app
sleep 2
pgrep -x SupremeNotch >/dev/null && echo "SupremeNotch $VERSION ($BUILD) notarized, installed and running: $SC/export/SupremeNotch-$VERSION.zip"
