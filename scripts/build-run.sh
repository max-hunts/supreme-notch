#!/bin/sh
# Usage: scripts/build-run.sh VERSION BUILD (for example 2.3.0 92).
# Iteration build: Developer ID signed Release, installed and launched. Not notarized.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SC=${BETTERNOTCH_WORK_DIR:-${TMPDIR:-/tmp}/betternotch-build}
mkdir -p "$SC"
VERSION=${1:?Usage: scripts/build-run.sh VERSION BUILD (for example 2.3.0 92).}
BUILD=${2:?Usage: scripts/build-run.sh VERSION BUILD (for example 2.3.0 92).}
cd "$ROOT"
rm -rf "$SC/BetterNotch.xcarchive" "$SC/export"
DD="$SC/DerivedData"
# macOS clears old files from the temporary folder, which can leave the Sparkle package
# half gone; start that cache over when it is.
SPARKLE="$DD/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework"
[ -d "$SPARKLE" ] && [ ! -f "$SPARKLE/Info.plist" ] && rm -rf "$DD/SourcePackages"
xcodebuild -project Notchly.xcodeproj -scheme Notchly -configuration Release -derivedDataPath "$SC/DerivedData" \
  -archivePath "$SC/BetterNotch.xcarchive" archive DEVELOPMENT_TEAM=36JR976L6Y CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=Developer ID Application" OTHER_CODE_SIGN_FLAGS=--timestamp \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" > "$SC/archive.log" 2>&1 || { grep -E "error:" "$SC/archive.log" | sort -u | head -20; exit 1; }
grep -E "warning:" "$SC/archive.log" | grep "Desktop/Notchly/Notchly/" | sed -E 's|.*/Notchly/Notchly/||' | sort -u | head -10
xcodebuild -exportArchive -archivePath "$SC/BetterNotch.xcarchive" -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" -exportPath "$SC/export" > "$SC/export.log" 2>&1
# Bundle the Rust claude-usage-monitor as a signed helper, then re-seal the app around it.
ID="Developer ID Application: Max Hunt (36JR976L6Y)"
# The usage monitor checkout (github.com/max-hunts/claude-usage-monitor).
MON=${USAGE_MONITOR_DIR:-$HOME/Desktop/claude-usage-monitor}
APP="$SC/export/BetterNotch.app"
(cd "$MON" && cargo build --release -q)
mkdir -p "$APP/Contents/Helpers"
cp "$MON/target/release/claude-usage-monitor" "$APP/Contents/Helpers/claude-usage-monitor"
codesign --force --options runtime --timestamp --sign "$ID" "$APP/Contents/Helpers/claude-usage-monitor"
codesign --force --options runtime --timestamp --sign "$ID" --preserve-metadata=entitlements,requirements,flags,runtime "$APP"
osascript -e 'tell application id "com.maxhunt.betternotch" to quit' 2>/dev/null || true
osascript -e 'tell application id "xyz.notchly.Notchly" to quit' 2>/dev/null || true
sleep 2
pgrep -x BetterNotch >/dev/null && pkill -x BetterNotch && sleep 1
pgrep -x Notchly >/dev/null && pkill -x Notchly && sleep 1
# One-time: the app was renamed from Notchly; move the old copy to the Trash.
[ -d /Applications/Notchly.app ] && mv /Applications/Notchly.app "$HOME/.Trash/Notchly-$(date +%Y%m%d%H%M%S).app"
rm -rf /Applications/BetterNotch.app
ditto "$APP" /Applications/BetterNotch.app
codesign --verify --deep --strict /Applications/BetterNotch.app
open -a /Applications/BetterNotch.app
sleep 2
pgrep -x BetterNotch >/dev/null && echo "BetterNotch $VERSION ($BUILD) installed and running, signed, not notarized"
