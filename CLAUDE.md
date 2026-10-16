# GrogLog

A drink tracker for iOS (SwiftUI, GRDB, in `GrogLog/`) and Android (Compose, Room, in `android/`). The README holds the
decisions worth knowing, so read it before changing how days, units, prices or sync work. The two apps share a model and a
backup format, not code.

## Git

- Work in PRs, which are squashed; do not rebase on merge.
- Never push tags. Tags and GitHub releases are left to the maintainer.
- Commits are signed.

## Changelog and docs

`CHANGELOG.md` is generated and is never edited by hand, not even to fix a typo, and a feature PR does not commit it
either: the release PR (`just release`) is what regenerates it, so open PRs never conflict on it. Every change adds one
fragment under `changelog.d/unreleased/<section>/`, named `<yyyymmdd>-<slug>.md` and holding one `- **Lead.** Detail.`
entry; to correct a note, change its fragment. `just changelog --stdout` prints the assembled text to check how a
fragment reads. The sections and the format are in `changelog.d/README.md`.

A change to behaviour, a setting or the backup format updates the matching page in `docs/` in the same PR.
`docs/IMPORT.md` is the contract between the apps' backups, so a change there changes both.

Releases are cut with `just release patch|minor|major`, which raises `MARKETING_VERSION` in `project.yml`, turns the
unreleased fragments into that version and opens the release PR. `project.yml` is the one place the version lives, for
both apps.

## Build and check

```sh
xcodegen generate       # GrogLog.xcodeproj is generated, never committed
scripts/ci-test.sh      # the iOS tests, on whichever iPhone simulator exists
just phone              # build, install and launch on the connected iPhone
just android-test       # the Android JVM tests
just android-build      # debug APK
just android-install    # install on a running emulator or device
just changelog --stdout # preview the assembled changelog
just release minor      # open the release PR
just store              # App Store Connect, from the terminal
just play               # Google Play, from the terminal
```

The Android recipes use `ANDROID_HOME` from the environment when it is set, so unset it if it points at a directory that
does not exist; otherwise they use Homebrew's SDK.

## Where things live

- `GrogLog/Model`: the database, `Logbook` (every write goes through it), `Ledger` (derived totals), goals, units and the
  catalogue. `GrogLog/Views` has a folder per tab; `GrogLog/Sync` is CloudKit; `GrogLogWidgets` the widgets.
- `android/app/src/main/java/cc/blit/groglog`: `model`, `data`, `export`, `ui` (a package per tab), `widget`, `shortcut`.
- `android/app/.../model/CatalogEntries.kt` is generated from `Catalog.swift` by `android/scripts/catalog.py`. Change the
  Swift file and regenerate; never edit the Kotlin by hand.

## Copy

In-app text is formal but warm: no contractions, no em dashes. Medical and settings text states what a thing does and
why, without cleverness.
