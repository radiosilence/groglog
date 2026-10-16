#!/bin/sh
# Creates the service account CI publishes to Play with, keeps its key in 1Password and sets PLAY_SERVICE_ACCOUNT_JSON.
# It still has to be invited in Play Console › Users and permissions; see docs/play-store.md › Play API access.
set -eu

VAULT="${VAULT:-Claude}"
REPO="radiosilence/groglog"
PROJECT="${PROJECT:-groglog-play}"
ACCOUNT="play-publisher@$PROJECT.iam.gserviceaccount.com"

gcloud projects describe "$PROJECT" >/dev/null 2>&1 || gcloud projects create "$PROJECT" --name "GrogLog Play"
gcloud services enable androidpublisher.googleapis.com --project "$PROJECT"
gcloud iam service-accounts describe "$ACCOUNT" --project "$PROJECT" >/dev/null 2>&1 ||
    gcloud iam service-accounts create play-publisher --project "$PROJECT" --display-name "GrogLog Play publisher"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
gcloud iam service-accounts keys create "$work/key.json" --iam-account "$ACCOUNT" --project "$PROJECT"
op document create "$work/key.json" --title "GrogLog Play service account" --file-name play-publisher.json --vault "$VAULT" >/dev/null
gh secret set PLAY_SERVICE_ACCOUNT_JSON --repo "$REPO" < "$work/key.json"

echo "Now invite $ACCOUNT in Play Console › Users and permissions, with access to GrogLog only."
