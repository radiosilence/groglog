#!/bin/sh
# Builds, launches with demo data and screenshots each tab. Usage: scripts/shoot.sh <out-dir> [light|dark]
set -e
OUT=${1:?out dir}; APPEARANCE=${2:-light}
SIM=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
xcodebuild -project GrogLog.xcodeproj -scheme GrogLog -destination "id=$SIM" -derivedDataPath build build -quiet
xcrun simctl ui "$SIM" appearance "$APPEARANCE"
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/GrogLog.app
mkdir -p "$OUT"
for tab in log calendar day reports setup; do
  xcrun simctl terminate "$SIM" cc.blit.groglog 2>/dev/null || true
  xcrun simctl launch "$SIM" cc.blit.groglog -demo -tab "$tab" >/dev/null
  sleep 4
  xcrun simctl io "$SIM" screenshot "$OUT/$tab-$APPEARANCE.png" >/dev/null 2>&1
done
