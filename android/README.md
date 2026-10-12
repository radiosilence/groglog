# GrogLog for Android

A native port of the iOS app. The decisions in the [main README](../README.md) hold here unchanged: unlogged is not dry, days end at 5am, totals are derived and never incremented, and the catalogue is a starting point. This page covers only what is different and why.

## Building

```sh
mise install          # Java 21, Gradle
just android-build    # assembleDebug
just android-test     # JVM unit tests under Robolectric
just android-install  # onto the connected device or emulator
```

`ANDROID_HOME` defaults to Homebrew's `android-commandlinetools`; set it to use another SDK, which needs `platforms;android-37.0`. Robolectric has no Android 17 sandbox yet, so the tests run against Android 16 (`app/src/test/resources/robolectric.properties`).

A release build is signed with the upload key when `ANDROID_UPLOAD_KEYSTORE_FILE` (or the `groglogUploadKeystoreFile` Gradle property) is set, and is unsigned otherwise; `-PversionCode` sets the version code. See [docs/play-store.md](../docs/play-store.md).

## Layout

`model` is the port of `GrogLog/Model`: plain Kotlin plus the Room entity annotations. `data` holds the database, `Logbook` (every write), `Prefs`, `Seed` and `Serves`. `export` is the backup. `ui` has one directory per tab, each with its screen and a ViewModel exposing `StateFlow`, so each screen can be worked on without touching the others. Navigation 3 holds one back stack rooted at the open tab, with ViewModels scoped to their entries. `AppContainer` on the `Application` wires everything together; there is no dependency injection framework because there is one database and one settings store, and `containerViewModel` hands it to a ViewModel's constructor.

The theme is GrogLog's palette, or Material You's wallpaper colours when Setup turns that on. The budget colours (`GrogColors`) carry meaning, so they stay the same under either. Material 3's Expressive theme and motion are not yet public in a stable release, so the standard `MaterialTheme` is used.

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

- **No sync.** CloudKit has no Android counterpart, and a Google Drive sync would be a second protocol to keep in step for one person's log. The log survives a lost phone through Android's Auto Backup, which copies the database and settings to the user's Google account (`res/xml/data_extraction_rules.xml`), and moves between phones and platforms through the JSON backup.
- **The JSON backup is byte-compatible with iOS.** `SwiftJson` reproduces `JSONEncoder`'s pretty, sorted output exactly, down to how numbers are written. `BackupCompatTests` rewrites a backup made by the iOS encoder and compares the bytes. After changing the backup format on iOS, run `scripts/ios-backup-fixture.sh` on a Mac to regenerate the fixture.
- **No Health.** Neither mirroring drinks out nor reading heart and sleep in. `Nights` is ported so Reports can use a Health Connect source later without new maths.
- **Widgets, a Quick Settings tile and launcher shortcuts stand in for App Intents and the Action Button.** Each carries a `Serve.key` and logs through `QuickLog`, which is `Logbook.log`, so there is still one write path. A widget's tap runs in the app's own process, so unlike iOS nothing has to catch up when the app next opens.
- **Widgets follow the database, not the call sites.** `Widgets.follow` watches Room's invalidation tracker and the settings, so a commit from anywhere (a screen, a tile, an import) redraws both widgets and republishes the shortcuts. An alarm redraws them when the day ends, since an empty evening commits nothing. RemoteViews cannot draw the burndown chart or the draining ring, so those are bitmaps (`Drawings`).
- **Widget previews come in three generations.** Android 15 draws them from `providePreview`, published once per installed version; Android 12 to 14 use the `previewLayout` XML; earlier versions show the `previewImage` drawable.
- **The catalogue is generated.** `scripts/catalog.py` writes `CatalogEntries.kt` from `GrogLog/Model/Catalog.swift`, comments included, so the Swift table stays the one place prices and strengths are researched and edited.
