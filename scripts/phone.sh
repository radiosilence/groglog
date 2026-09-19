#!/bin/sh
# Builds, installs and launches on the connected iPhone. Usage: scripts/phone.sh [Debug|Release]
# Your log survives: installing over the app keeps its data.
set -e
cd "$(dirname "$0")/.."
CONFIG=${1:-Debug}
PHONE=$(xcrun devicectl list devices | awk '/physical/ && /connected|available/' | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)
[ -n "$PHONE" ] || { echo "No iPhone connected — plug it in, or unlock it if it's on Wi-Fi." >&2; exit 1; }
xcodegen generate --quiet
xcodebuild -project GrogLog.xcodeproj -scheme GrogLog -configuration "$CONFIG" -destination "id=$PHONE" -derivedDataPath build -allowProvisioningUpdates build -quiet
xcrun devicectl device install app --device "$PHONE" "build/Build/Products/$CONFIG-iphoneos/GrogLog.app"
xcrun devicectl device process launch --device "$PHONE" cc.blit.groglog
