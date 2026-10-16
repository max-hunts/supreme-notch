#!/bin/sh
# Visual regression check for agent alerts. Builds the Debug app, shows sample alerts in
# the real island window, saves a PNG of each and checks the gaps around the buttons.
# Usage: scripts/layout-check.sh [output folder]. Exits non-zero if any alert fails.
# Run it on a Mac with a notch to cover the space kept clear below the camera.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${TMPDIR:-/tmp}/betternotch-layout-check
OUT=${1:-$WORK/out}
cd "$ROOT"
xcodebuild -project Notchly.xcodeproj -scheme Notchly -configuration Debug -derivedDataPath "$WORK/DerivedData" \
  build > "$WORK.build.log" 2>&1 || { grep -E "error:" "$WORK.build.log" | sort -u | head -20; exit 1; }
APP="$WORK/DerivedData/Build/Products/Debug/BetterNotch.app"
rm -rf "$OUT"; mkdir -p "$OUT"
# One island at a time: an installed BetterNotch watches the same alert files.
was_running=0
if pgrep -qx BetterNotch; then was_running=1; osascript -e 'quit app "BetterNotch"'; sleep 1; fi
"$APP/Contents/MacOS/BetterNotch" -layoutCheck "$OUT" > "$WORK.run.log" 2>&1
status=$?
[ "$was_running" = 1 ] && open -a /Applications/BetterNotch.app
cat "$OUT/report.txt" 2>/dev/null || { echo "No report (exit $status). See $WORK.run.log"; status=1; }
echo "Images: $OUT"
exit $status
