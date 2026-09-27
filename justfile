# Builds, installs and launches on the connected iPhone. Installing over the app keeps its data.
phone config="Debug":
    #!/bin/sh
    set -e
    PHONE=$(xcrun devicectl list devices | awk '/physical/ && /connected|available/' | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)
    [ -n "$PHONE" ] || { echo "No iPhone connected — plug it in, or unlock it if it's on Wi-Fi." >&2; exit 1; }
    xcodegen generate --quiet
    xcodebuild -project GrogLog.xcodeproj -scheme GrogLog -configuration {{config}} -destination "id=$PHONE" -derivedDataPath build -allowProvisioningUpdates build -quiet
    xcrun devicectl device install app --device "$PHONE" "build/Build/Products/{{config}}-iphoneos/GrogLog.app"
    xcrun devicectl device process launch --device "$PHONE" cc.blit.groglog
