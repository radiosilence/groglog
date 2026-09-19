#!/bin/sh
# Renders GrogLog/Assets.xcassets/AppIcon.appiconset/AppIcon.png from the pint glyph.
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
swiftc -parse-as-library -O -o "$OUT/render-icon" \
  GrogLog/Model/Units.swift GrogLog/Views/Shared/DrinkGlyph.swift scripts/render-icon.swift
"$OUT/render-icon" GrogLog/Assets.xcassets/AppIcon.appiconset/AppIcon.png
