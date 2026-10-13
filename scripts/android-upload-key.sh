#!/bin/sh
# Creates the Android upload key once, keeps it in 1Password and gives CI the four secrets it signs with.
# The keystore exists on disk only while this runs. See docs/play-store.md › Signing.
set -eu

VAULT="${VAULT:-Private}"
REPO="radiosilence/groglog"
TITLE="GrogLog Android upload keystore"

if op document get "$TITLE" --vault "$VAULT" >/dev/null 2>&1; then
    echo "$TITLE already exists in 1Password ($VAULT). Remove it first to make a new key." >&2
    exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
password=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)

keytool -genkeypair -keystore "$work/upload.jks" -storetype PKCS12 -alias upload \
    -keyalg RSA -keysize 4096 -validity 10000 \
    -storepass "$password" -keypass "$password" \
    -dname "CN=James Cleveland, O=GrogLog, C=GB"

op document create "$work/upload.jks" --title "$TITLE" --file-name groglog-upload.jks --vault "$VAULT" >/dev/null
op item create --category password --title "$TITLE password" --vault "$VAULT" "password=$password" >/dev/null

base64 < "$work/upload.jks" | gh secret set ANDROID_UPLOAD_KEYSTORE --repo "$REPO"
printf %s "$password" | gh secret set ANDROID_UPLOAD_KEYSTORE_PASSWORD --repo "$REPO"
printf %s "$password" | gh secret set ANDROID_UPLOAD_KEY_PASSWORD --repo "$REPO"
gh secret set ANDROID_UPLOAD_KEY_ALIAS --repo "$REPO" --body upload

echo "Upload key stored in 1Password ($VAULT) as \"$TITLE\", and the four ANDROID_UPLOAD_* secrets are set on $REPO."
