#!/bin/sh
# App Store screenshots: the 6.9-inch size App Store Connect requires for an iPhone app, from the demo data, with
# Apple's clean status bar. Usage: scripts/store-screenshots.sh <out-dir> [light|dark]
#
# The website uses the same images, so the listing and the site show the same build.
set -eu
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; APPEARANCE=${2:-light}
DEVICE="iPhone 18 Pro Max"
SIM=$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$SIM" 2>/dev/null || true
xcrun simctl bootstatus "$SIM" -b >/dev/null
xcrun simctl ui "$SIM" appearance "$APPEARANCE"
xcrun simctl status_bar "$SIM" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

xcodegen generate --quiet
xcodebuild -project GrogLog.xcodeproj -scheme GrogLog -destination "id=$SIM" -derivedDataPath build build -quiet
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/GrogLog.app

mkdir -p "$OUT"
n=1
for tab in log day reports calendar setup; do
  xcrun simctl terminate "$SIM" cc.blit.groglog 2>/dev/null || true
  # Day opens on yesterday: today in the demo data is empty until its evening, and a screenshot is taken at whatever
  # time it happens to be.
  xcrun simctl launch "$SIM" cc.blit.groglog -demoMode YES -tab "$tab" -dayOffset 1 >/dev/null
  # Captures repeat until two in a row are the same size, so the screen is taken once it has finished drawing: a first
  # frame can be black apart from the status bar, and the calendar draws its grid before its days. A busy machine can
  # be slow at either.
  FILE="$OUT/$n-$tab-$APPEARANCE.png"
  last=0
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 5
    xcrun simctl io "$SIM" screenshot "$FILE" >/dev/null 2>&1
    size=$(wc -c < "$FILE")
    [ "$size" -gt 200000 ] && [ "$size" -eq "$last" ] && break
    last=$size
  done
  n=$((n + 1))
done
xcrun simctl status_bar "$SIM" clear
