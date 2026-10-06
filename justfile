# Builds, installs and launches on the connected iPhone. Installing over the app keeps its data.
phone config="Debug":
    #!/bin/sh
    set -e
    PHONE=$(xcrun devicectl list devices | awk '/physical/ && / (connected|available) /' | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)
    [ -n "$PHONE" ] || { echo "No iPhone connected. Plug it in, or unlock it if it is on Wi-Fi." >&2; exit 1; }
    xcodegen generate --quiet
    xcodebuild -project GrogLog.xcodeproj -scheme GrogLog -configuration {{config}} -destination "id=$PHONE" -derivedDataPath build -allowProvisioningUpdates build -quiet
    xcrun devicectl device install app --device "$PHONE" "build/Build/Products/{{config}}-iphoneos/GrogLog.app"
    xcrun devicectl device process launch --device "$PHONE" cc.blit.groglog

# CHANGELOG.md, generated from the fragments in changelog.d/. `--release X.Y.Z` cuts a version.
changelog *args:
    python3 scripts/changelog.py {{args}}

# The App Store listing, builds and review, from the terminal. See scripts/app-store.py.
store command="status" *args:
    scripts/app-store.py {{command}} {{args}}
