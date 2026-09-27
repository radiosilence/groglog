#!/bin/sh
# App Store screenshots: the 6.9-inch size App Store Connect requires for an iPhone app, from the demo data, with
# Apple's clean status bar. Usage: scripts/store-screenshots.sh <out-dir> [light|dark]
#
# The same images feed the website, so the listing and the site always show the app as it is.
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
  sleep 12
  xcrun simctl io "$SIM" screenshot "$OUT/$n-$tab-$APPEARANCE.png" >/dev/null 2>&1
  n=$((n + 1))
done
xcrun simctl status_bar "$SIM" clear
