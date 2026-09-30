#!/bin/sh
# Archives a signed build and uploads it to App Store Connect, where it lands in TestFlight.
#
# Needs APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY (the .p8 key's contents) in the environment, and
# BUILD_NUMBER, which must be higher than any build uploaded before. Runs on a laptop or on CI.
set -eu
cd "$(dirname "$0")/.."
: "${APPLE_TEAM_ID:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY:?}" "${BUILD_NUMBER:?}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
KEY="$WORK/AuthKey_$ASC_KEY_ID.p8"
printf '%s\n' "$ASC_KEY" > "$KEY"
AUTH="-allowProvisioningUpdates -authenticationKeyPath $KEY -authenticationKeyID $ASC_KEY_ID -authenticationKeyIssuerID $ASC_ISSUER_ID"

# Offset by 1000 so a CI build number cannot collide with one uploaded by hand.
BUILD=$((1000 + BUILD_NUMBER))

xcodegen generate --quiet
# shellcheck disable=SC2086
xcodebuild archive -scheme GrogLog -destination 'generic/platform=iOS' -archivePath "$WORK/GrogLog.xcarchive" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CURRENT_PROJECT_VERSION="$BUILD" $AUTH -quiet

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$APPLE_TEAM_ID</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

# shellcheck disable=SC2086
xcodebuild -exportArchive -archivePath "$WORK/GrogLog.xcarchive" -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$WORK/export" $AUTH
echo "Uploaded build $BUILD to App Store Connect"
