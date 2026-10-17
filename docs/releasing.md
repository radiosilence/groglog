# Releasing

Every push to `main` that passes the tests is archived, signed and uploaded to App Store Connect by
`.github/workflows/ios.yml`, and appears in TestFlight once Apple has processed it. The listing and review submission
are driven from the terminal by `scripts/app-store.py` (`just store <command>`), so the App Store Connect website is
needed only for what Apple offers no API for.

Signing is Xcode's cloud-managed kind, authenticated with an App Store Connect API key, so no provisioning profile is
kept anywhere. Archiving also needs an Apple Development identity, which a runner lacks; without one Xcode has Apple
issue a new certificate on every run until the account reaches its limit. CI therefore imports one stored certificate,
shared with koan's CI. `scripts/testflight.sh` runs the same on a laptop given the same environment.

## Setting it up

Once, in App Store Connect and GitHub:

1. **App record.** App Store Connect › Apps › + › New App: iOS, name GrogLog, bundle ID `cc.blit.groglog`, SKU
   anything. The widgets' bundle ID, `cc.blit.groglog.widgets`, is registered automatically on the first upload.
2. **API key.** Users and Access › Integrations › App Store Connect API › Team Keys › +, with the **Admin** role:
   cloud-managed signing has to create certificates and profiles, which lesser roles can't. Download the `.p8` (it can
   only be downloaded once) and note the Key ID and the Issuer ID shown above the list.
3. **GitHub**, in the repository's Settings › Secrets and variables › Actions:
   - variable `APPLE_TEAM_ID`: the team ID from developer.apple.com › Account › Membership details
   - secret `ASC_KEY_ID`, secret `ASC_ISSUER_ID`
   - secret `ASC_KEY`: the whole contents of the `.p8` file
   - secret `IOS_CERTIFICATE_P12`: the base64 of the `.p12` in 1Password's "Apple Development certificate for CI
     (.p12)", and secret `IOS_CERTIFICATE_PASSWORD` from "Apple Development certificate for CI (password)"

Until `APPLE_TEAM_ID` is set, the upload job is skipped and only the tests run.

An internal TestFlight group with access to all builds hands each processed upload to its testers without anyone
having to add it; internal testers must be App Store Connect users.

Each CI build's What to Test is set from CHANGELOG.md: the section for `MARKETING_VERSION`, or Unreleased when there
is none yet. `just store whats-new BUILD` sets it by hand.

Outside testers join through the public group's link, https://testflight.apple.com/join/GKQQyk7P. A build reaches them
only once it has been added to that group and passed Apple's beta review, which the first build of each version needs.

## Releasing a version

Every change adds a fragment under `changelog.d/unreleased/` (see `changelog.d/README.md`); CHANGELOG.md is generated
from them, by the release PR alone, and never edited by hand. TestFlight's What to Test and Play's release notes are
assembled from the fragments, so they are current before a release is cut.

1. `just release patch|minor|major` (or an exact version) branches from `main`, raises `MARKETING_VERSION` in `project.yml`,
   turns the unreleased fragments into that version with `just changelog --release`, and opens the release PR with the
   changelog section as its body. Merging it uploads the build; it creates no tag, which is left to you.
2. For an update, add a `## What's new` section to [app-store.md](app-store.md). Apple requires release notes on every
   version after the first and refuses them on the first.
3. `just store listing` pushes app-store.md to the listing, creating the version in App Store Connect if needed.
   `just store screenshots` retakes the screenshots and replaces the listing's set, when the app has changed visibly.
4. `just store submit` attaches the newest processed build of that version and submits it for review. An approved
   version is released straight away.

To replace the build of a version already waiting for review, `just store withdraw` takes it out of review once the
new build has processed; `just store submit` then attaches that build and sends it again. Review starts over.

When App Review asks for more information, answer in the Review notes section of app-store.md, which `just store
listing` sends, and attach anything else, such as a screen recording, with `just store review-attachment FILE`.
The recording App Review asked for with 1.1.0, starting from launch and covering the main flow, is kept outside the
repository at `~/Documents/GrogLog/app-review-recording-1.1.0-build-1025.mp4`; re-record it when the app changes visibly.

`just store` on its own shows the versions, recent builds and review state.

The script reads the API key from `~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`; the key and issuer IDs
are in `mise.toml`. App Privacy, the EU trader declaration and agreements have no API and are set on the website, once.

## Build numbers

A CI build's number is 1000 plus the workflow run number, so it always rises and can never collide with one uploaded
by hand. The version shown in the App Store is `MARKETING_VERSION` in `project.yml`; raise it for each release.

## Screenshots

`scripts/store-screenshots.sh <dir>` takes the 6.9-inch set App Store Connect requires, from the demo data with
Apple's standard status bar. The website uses the same images, in both appearances (`light` and `dark`, the script's second argument), so re-run it for each and copy them into `site/public/screens`
when the app changes visibly. Then run `scripts/render-share-image.sh`, which builds the site's link-preview image
(`site/public/share.png`, 1200×630) from the app icon and two of those screenshots.

## Android

Every push to `main` that touches `android/` is tested, bundled, signed with the upload key and released to Google
Play's internal track by `.github/workflows/android.yml`. Pull requests are tested and bundled unsigned. Until the
upload key's secrets exist the bundle stays unsigned and nothing is uploaded; until `PLAY_SERVICE_ACCOUNT_JSON` exists
the signed bundle is kept as the run's `bundle` artifact and not uploaded. Setting both up, the Play Console forms and
the closed test a personal account must run before production are in [play-store.md](play-store.md).

The version code is the workflow's run number times 100 plus its attempt, so it always rises and a re-run uploads a
code Play has not seen. The version name is `versionName` in
`android/app/build.gradle.kts`; raise it with `MARKETING_VERSION`, so both apps carry the same version. Release notes
on each upload are CHANGELOG.md's Unreleased section, or the newest version's, cut to Play's 500 characters.

To release a version on Android:

1. Let CI put the build on the internal track, and check it on a phone.
2. Move it to the closed test or production with Testing › Internal testing › Promote release in Play Console, or
   upload the same bundle (the run's `bundle` artifact) with `scripts/play.py upload app-release.aab alpha` or
   `production`. Play reviews closed and production releases.
3. When the listing has changed, `scripts/play.py listing` pushes `android/store/listing.toml` and the graphics. Run
   `scripts/render-play-graphics.sh` first if the icon has changed.

A push to `main` whose `MARKETING_VERSION` is newer than the latest GitHub release is released by the `apk` job in `.github/workflows/android.yml`: it builds a signed APK from the commit that raised the version, publishes the release with that version's changelog section as its notes and attaches the APK. Publishing a release by hand attaches the APK to it too. It is signed with the upload key, not the key Play signs installs with, so it installs fresh but does not update over a Play install, or the other way round.

To check that a release would work first, run the Android workflow by hand (Actions › Android › Run workflow, or `gh workflow run android.yml`): the `apk` job builds and signs the APK, prints its certificate and version, and keeps it as a workflow artifact for a week, without publishing anything.

`scripts/play.py status` shows what each track holds. It authenticates with the service account's key in
`PLAY_SERVICE_ACCOUNT_JSON`.
