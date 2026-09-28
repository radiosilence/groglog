# Releasing

Every push to `main` that passes the tests is archived, signed and uploaded to App Store Connect by
`.github/workflows/app.yml`, and appears in TestFlight once Apple has processed it. The listing and review submission
are driven from the terminal by `scripts/app-store.py` (`just store <command>`), so the App Store Connect website is
needed only for what Apple offers no API for.

Signing is Xcode's cloud-managed kind, authenticated with an App Store Connect API key, so no certificate or
provisioning profile is kept anywhere and nothing needs renewing. `scripts/testflight.sh` is the whole of it and runs
the same on a laptop given the same environment.

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

Until `APPLE_TEAM_ID` is set, the upload job is skipped and only the tests run.

An internal TestFlight group with access to all builds hands each processed upload to its testers without anyone
having to add it; internal testers must be App Store Connect users.

## Releasing a version

1. Raise `MARKETING_VERSION` in `project.yml` and push; CI uploads the build.
2. For an update, add a `## What's new` section to [app-store.md](app-store.md). Apple requires release notes on every
   version after the first and refuses them on the first.
3. `just store listing` pushes app-store.md to the listing, creating the version in App Store Connect if needed.
   `just store screenshots` retakes the screenshots and replaces the listing's set, when the app has changed visibly.
4. `just store submit` attaches the newest processed build of that version and submits it for review. An approved
   version is released straight away.

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
