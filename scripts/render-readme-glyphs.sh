#!/bin/sh
# Renders the README's status ring, closed notch and usage color images straight from the
# battery views, without building the app. Usage: scripts/render-readme-glyphs.sh [folder]
# (default docs/images). The tab and alert images come from a Debug build instead:
# BetterNotch.app/Contents/MacOS/BetterNotch -renderReadmeImages <folder>
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/docs/images}
B="$ROOT/Notchly/Views/Island/Battery"
WORK=${TMPDIR:-/tmp}/betternotch-readme-glyphs
mkdir -p "$WORK" "$OUT"
cp "$ROOT/scripts/readme-glyphs/main.swift" "$ROOT/scripts/readme-glyphs/stubs.swift" "$WORK/"
cd "$WORK"
swiftc -o readme stubs.swift "$B/StatusRingGlyph.swift" "$B/CompactBatteryView.swift" "$B/UsageBarsGlyph.swift" \
  "$B/ChargingPopView.swift" "$B/ExpandedBatteryView.swift" main.swift
./readme "$OUT"
echo "Wrote images to $OUT"
