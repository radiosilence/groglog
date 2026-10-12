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

Screens render headlessly under Robolectric with Roborazzi, for looking at in review: `./gradlew :app:testDebugUnitTest --tests '*Screenshots*' -Proborazzi.test.record=true` writes PNGs, light and dark, to `app/build/outputs/roborazzi`. They render in `en-GB`, the listing's language, so prices read in pounds.

A release build is signed with the upload key when `ANDROID_UPLOAD_KEYSTORE_FILE` (or the `groglogUploadKeystoreFile` Gradle property) is set, and is unsigned otherwise; `-PversionCode` sets the version code. See [docs/play-store.md](../docs/play-store.md).

## Layout

`model` is the port of `GrogLog/Model`: plain Kotlin plus the Room entity annotations. `data` holds the database, `Logbook` (every write), `Prefs`, `Seed` and `Serves`. `export` is the backup. `ui` has one directory per tab, each with its screen and a ViewModel exposing `StateFlow`, so each screen can be worked on without touching the others; `ui/shared` holds what several use, such as the form controls and `DrinkGlyph`. Navigation 3 holds one back stack rooted at the open tab, with ViewModels scoped to their entries. Where iOS presents another tab's sheet, such as the drink editor from the Log or the goal from the Day tab, the page is pushed onto that stack (`Routes.kt`, wired in `MainActivity`), so back returns to where it was opened. Choosing the open tab again sends it a reselect, which takes it back to its top. `AppContainer` on the `Application` wires everything together; there is no dependency injection framework because there is one database and one settings store, and `containerViewModel` hands it to a ViewModel's constructor.

The theme is GrogLog's palette, or Material You's wallpaper colours when Setup turns that on. GrogLog's scheme sets every Material role, with iOS's system greys for the neutrals: left to its defaults, Material tints surfaces towards the primary colour, and the app would read lavender beside the iOS one. The budget colours (`GrogColors`) carry meaning, so they stay the same under either. The wallpaper choice belongs to the device, so it is kept in `Prefs` apart from the settings a backup carries. Material 3's Expressive theme and motion are not yet public in a stable release, so the standard `MaterialTheme` is used.

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
- **Health Connect for Health.** The three switches in Setup work as on iOS, with these differences:
  - Health Connect has no record type for alcohol, so the mirror copies only each drink's calories, as a nutrition record named after the drink. Nothing stands in for HealthKit's count of standard drinks.
  - HRV is RMSSD in Health Connect where HealthKit labels everything SDNN. The two are different measures, so readings still compare only with themselves, and not with an iPhone's.
  - Health Connect says which permissions were granted, so a switch shows on only while its permission stands, and turns itself off if the permission is withdrawn in Health Connect.
  - Reading from before the first grant needs `READ_HEALTH_DATA_HISTORY`, requested with the reading switches where Health Connect offers it; without it Health Connect returns only the 30 days before the grant.
  - Heart rate while asleep is fetched for the last 120 nights only, the longest a chart draws it, because Health Connect limits how many requests an app makes and each night is one. Past nights are fetched once per process.
  - Health Connect's sleep stages map onto HealthKit's: light is core, sleeping without a stage is unstaged, awake and awake in bed are awake, and out of bed is left out. A session with no stages counts as unstaged sleep.
  - Writes are serialised and announced by `Logbook.changed` after each commit, from every logbook in the process, so imports and rebuilds reach the mirror too. Coming to the foreground rewrites today and yesterday, as on iOS.
  - Health Connect's permission screens link to the privacy policy, which the build packages from `site/public/privacy.html` so the app shows the same text offline.
- **Reports draws its charts on a Compose Canvas.** Swift Charts has no Android counterpart, and the libraries that come closest (Vico) would need to be fought for the per-bar heat colours, dashed bridges over missing nights, a second axis fitted to one heart reading, and a readout that reads the log rather than the bars. `Plot` describes a chart as plain values and `TimeChart` draws, scrolls, pinches and reads it out; TalkBack reads each day in view as an item and can scroll the chart. Android has no Differentiate Without Colour setting, so the `!` and `!!` marks follow the Calendar's `differentiateWithoutColour`.
- **Widgets, a Quick Settings tile and launcher shortcuts stand in for App Intents and the Action Button.** Each carries a `Serve.key` and logs through `QuickLog`, which is `Logbook.log`, so there is still one write path. A widget's tap runs in the app's own process, so unlike iOS nothing has to catch up when the app next opens.
- **Widgets follow the database, not the call sites.** `Widgets.follow` watches Room's invalidation tracker and the settings, so a commit from anywhere (a screen, a tile, an import) redraws both widgets and republishes the shortcuts. An alarm redraws them when the day ends, since an empty evening commits nothing. RemoteViews cannot draw the burndown chart or the draining ring, so those are bitmaps (`Drawings`).
- **Widget previews come in three generations.** Android 15 draws them from `providePreview`, published once per installed version; Android 12 to 14 use the `previewLayout` XML; earlier versions show the `previewImage` drawable.
- **Portrait on phones, either way on large screens.** iOS is portrait-only, and the screens are laid out for it. The manifest locks `MainActivity` to portrait; Android 16 and later ignore that lock on displays 600 dp and wider, as Google Play requires of large-screen apps, so tablets and unfolded foldables still rotate. Earlier Android versions keep tablets in portrait too.
- **The catalogue is generated.** `scripts/catalog.py` writes `CatalogEntries.kt` from `GrogLog/Model/Catalog.swift`, comments included, so the Swift table stays the one place prices and strengths are researched and edited.
- **A backup is saved, a log is shared.** Setup's JSON backup goes through the system's file picker, since Android's share sheet has no "save to Files" and a backup is a file to keep; the Markdown log goes to the share sheet as a text file, since it is meant for pasting into a chat.
- **Demo mode restarts the app.** Every screen holds the database it was given, so Setup › Developer › Demo mode (debug builds only) records the choice and relaunches onto an in-memory log of `Seed.sample`, rather than swapping the database under open screens.
