#!/bin/sh
# Visual regression check for agent alerts. Builds the Debug app, shows sample alerts in
# the real island window, saves a PNG of each and checks the gaps around the buttons.
# Then opens the island and swipes through the tabs, checking that both edges move
# together while its width animates.
# Usage: scripts/layout-check.sh [output folder]. Exits non-zero if any check fails.
# Run it on a Mac with a notch to cover the space kept clear below the camera.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${TMPDIR:-/tmp}/supremenotch-layout-check
OUT=${1:-$WORK/out}
cd "$ROOT"
DD="$WORK/DerivedData"
xcodebuild -project SupremeNotch.xcodeproj -scheme SupremeNotch -configuration Debug -derivedDataPath "$WORK/DerivedData" \
  build > "$WORK.build.log" 2>&1 || { grep -E "error:" "$WORK.build.log" | sort -u | head -20; exit 1; }
APP="$WORK/DerivedData/Build/Products/Debug/SupremeNotch.app"
rm -rf "$OUT"; mkdir -p "$OUT"
# One island at a time: an installed SupremeNotch watches the same alert files.
was_running=0
if pgrep -qx SupremeNotch; then was_running=1; osascript -e 'quit app "SupremeNotch"'; sleep 1; fi
"$APP/Contents/MacOS/SupremeNotch" -layoutCheck "$OUT" > "$WORK.run.log" 2>&1
status=$?
"$APP/Contents/MacOS/SupremeNotch" -widthCheck "$OUT/width" > "$WORK.width.log" 2>&1
width_status=$?
[ "$was_running" = 1 ] && open -a /Applications/SupremeNotch.app
cat "$OUT/report.txt" 2>/dev/null || { echo "No report (exit $status). See $WORK.run.log"; status=1; }
echo "Tab swipes:"
grep -v "moved left/right" "$OUT/width/report.txt" 2>/dev/null || { echo "No report (exit $width_status). See $WORK.width.log"; width_status=1; }
[ "$width_status" = 0 ] || status=1
echo "Images: $OUT"
exit $status
