#!/bin/sh
# Renders android/store/icon.png (512×512) and android/store/feature-graphic.png (1024×500) for the Play listing.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
swiftc -parse-as-library -O -o "$OUT/render-play-graphics" \
  GrogLog/Model/Units.swift GrogLog/Views/Shared/DrinkGlyph.swift scripts/render-play-graphics.swift
"$OUT/render-play-graphics" android/store
rm -rf "$OUT"
