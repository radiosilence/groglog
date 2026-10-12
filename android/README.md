# GrogLog for Android

A native port of the iOS app. The decisions in the [main README](../README.md) hold here unchanged: unlogged is not dry, days end at 5am, totals are derived and never incremented, and the catalogue is a starting point. This page covers only what is different and why.

## Building

```sh
mise install          # Java 21, Gradle
just android-build    # assembleDebug
just android-test     # JVM unit tests under Robolectric
just android-install  # onto the connected device or emulator
```

`ANDROID_HOME` defaults to Homebrew's `android-commandlinetools`; set it to use another SDK. compileSdk is 36, so AndroidX libraries are held at the last releases that build against it (`gradle/libs.versions.toml`).

## Layout

`model` is the port of `GrogLog/Model`: plain Kotlin plus the Room entity annotations. `data` holds the database, `Logbook` (every write), `Prefs`, `Seed` and `Serves`. `export` is the backup. `ui` has one directory per tab so each screen can be worked on without touching the others. `AppContainer` on the `Application` wires them together; there is no dependency injection framework because there is one database and one settings store.

## Room for GRDB

| iOS | Android |
| --- | --- |
| `AppDatabase` + `DatabaseMigrator` | `AppDatabase` (Room) + `AppDatabase.migrations`, append-only |
| `Logbook` writing in `writer.write` | `Logbook` writing in `withTransaction`, suspend functions |
| `GRDBQuery` requests in `Queries.swift` | `Queries` DAO returning `Flow`s, deduplicated |
| `UserDefaults` in the app group | DataStore (`Prefs`) |
| `UUID` blob, `Date` as text | `UUID` as a 16-byte blob, `Instant` as epoch milliseconds |

Schema version 1 is the iOS schema after its eighth migration, without the iCloud sync tables. The databases are not interchangeable files; logs move between platforms as JSON backups. Room's exported schema is committed under `app/schemas` so each future migration can be tested against the one before.

Entries for a range are read with a Room `@Relation`, which fetches the drinks in a second query; the `(day, timestamp)` index still serves the first, and `IndexTests` checks it.

## What differs from iOS

- **No sync.** CloudKit has no Android counterpart, and a Google Drive sync would be a second protocol to keep in step for one person's log. The log survives a lost phone through Android's Auto Backup, which copies the database and settings to the user's Google account, and moves between phones and platforms through the JSON backup.
- **The JSON backup is byte-compatible with iOS.** `SwiftJson` reproduces `JSONEncoder`'s pretty, sorted output exactly, down to how numbers are written. `BackupCompatTests` rewrites a backup made by the iOS encoder and compares the bytes. After changing the backup format on iOS, run `scripts/ios-backup-fixture.sh` on a Mac to regenerate the fixture.
- **No Health.** Neither mirroring drinks out nor reading heart and sleep in. `Nights` is ported so Reports can use a Health Connect source later without new maths.
- **No widgets or shortcuts yet.** `Serves` is the lookup they will use: a tile carries a `Serve.key` and logs through `Logbook`, as the iOS intents do.
- **The catalogue is generated.** `scripts/catalog.py` writes `CatalogEntries.kt` from `GrogLog/Model/Catalog.swift`, comments included, so the Swift table stays the one place prices and strengths are researched and edited.
