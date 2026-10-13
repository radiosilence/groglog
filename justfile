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

# The Google Play listing and releases, from the terminal. See scripts/play.py.
play command="status" *args:
    scripts/play.py {{command}} {{args}}

# The Android app, built with Gradle from android/. JAVA_HOME comes from mise; ANDROID_HOME defaults to Homebrew's SDK.
android-gradle *tasks:
    cd android && JAVA_HOME="$(mise where java)" ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}" ./gradlew {{tasks}}

android-build: (android-gradle ":app:assembleDebug")

android-test: (android-gradle ":app:testDebugUnitTest")

# Installs on the connected device or running emulator. Installing over the app keeps its data.
android-install: (android-gradle ":app:installDebug")

# Creates the Play upload key, keeps it in 1Password and sets CI's signing secrets. Once only.
android-upload-key:
    PATH="$(mise where java)/bin:$PATH" scripts/android-upload-key.sh
