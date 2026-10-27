#!/bin/sh
# Usage: scripts/build-run.sh VERSION BUILD (for example 2.3.0 92).
# Iteration build: Developer ID signed Release, installed and launched. Not notarized.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SC=${SUPREMENOTCH_WORK_DIR:-${TMPDIR:-/tmp}/supremenotch-build}
mkdir -p "$SC"
VERSION=${1:?Usage: scripts/build-run.sh VERSION BUILD (for example 2.3.0 92).}
BUILD=${2:?Usage: scripts/build-run.sh VERSION BUILD (for example 2.3.0 92).}
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
# Universal, like the app, so the Usage tab works on Intel Macs too.
rustup -q target add aarch64-apple-darwin x86_64-apple-darwin
(cd "$MON" && cargo build --release -q --target aarch64-apple-darwin && cargo build --release -q --target x86_64-apple-darwin)
mkdir -p "$APP/Contents/Helpers"
lipo -create -output "$APP/Contents/Helpers/claude-usage-monitor" \
  "$MON/target/aarch64-apple-darwin/release/claude-usage-monitor" "$MON/target/x86_64-apple-darwin/release/claude-usage-monitor"
codesign --force --options runtime --timestamp --sign "$ID" "$APP/Contents/Helpers/claude-usage-monitor"
codesign --force --options runtime --timestamp --sign "$ID" --preserve-metadata=entitlements,requirements,flags,runtime "$APP"
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
codesign --verify --deep --strict /Applications/SupremeNotch.app
open -a /Applications/SupremeNotch.app
sleep 2
pgrep -x SupremeNotch >/dev/null && echo "SupremeNotch $VERSION ($BUILD) installed and running, signed, not notarized"
