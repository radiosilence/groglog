# Releasing

Every push to `main` that passes the tests is archived, signed and uploaded to App Store Connect by
`.github/workflows/app.yml`, and appears in TestFlight once Apple has processed it. Putting a build up for App Store
review is done in App Store Connect, where the listing lives (see [app-store.md](app-store.md)).

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

## Build numbers

A CI build's number is 1000 plus the workflow run number, so it always rises and can never collide with one uploaded
by hand. The version shown in the App Store is `MARKETING_VERSION` in `project.yml`; raise it for each release.

## Screenshots

`scripts/store-screenshots.sh <dir>` takes the 6.9-inch set App Store Connect requires, from the demo data with
Apple's standard status bar. The website uses the same images, so re-run it and copy them into `site/public/screens`
when the app changes visibly.
