#!/bin/sh
# Renders site/public/share.png, the link-preview image, from the app icon and the site's screenshots.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
swiftc -parse-as-library -O -o "$OUT/render-share" scripts/render-share-image.swift
"$OUT/render-share" site/public/share.png
rm -rf "$OUT"
