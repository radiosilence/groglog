#!/bin/sh
# Regenerates the iOS-written backup the Android tests read, from the iOS app's own Backup type and encoder settings.
# Run on a Mac after changing the backup format: android/scripts/ios-backup-fixture.sh
set -e
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
{
    echo 'import Foundation'
    awk '/^nonisolated struct Backup/{p=1} /^nonisolated enum Exporter/{p=0} p' "$root/GrogLog/Export/Backup.swift"
} > "$work/backup.swift"
cp "$root/android/scripts/ios-backup-fixture.swift" "$work/main.swift"
model="$root/GrogLog/Model"
swiftc -o "$work/fixture" "$model/DayKey.swift" "$model/Goal.swift" "$model/Units.swift" "$work/backup.swift" "$work/main.swift"
"$work/fixture" > "$root/android/app/src/test/resources/ios-backup.json"
