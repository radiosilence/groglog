# Google Play listing

What Play Console asks for, kept here so a change to the listing is reviewed like any other. The listing text and
graphics live in [android/store/listing.toml](../android/store/listing.toml), which `scripts/play.py listing` sends to
Play; the rest of this page is the forms Play has no API for, answered once in Play Console, and the steps that only
the developer can take. [app-store.md](app-store.md) is the iOS counterpart, and the two listings say the same thing
where the apps do.

## App details

- **App name:** GrogLog Drink Tracker
- **Default language:** English (United Kingdom), `en-GB`
- **App or game:** App
- **Free or paid:** Free, no in-app purchases
- **Category:** Health & Fitness
- **Tags:** Health & fitness tracking, Habit tracker, Diary (whichever Play offers closest to these)
- **Contact email:** support@groglog.io
- **Website:** https://groglog.io
- **Privacy policy:** https://groglog.io/privacy.html
- **Phone:** not given. Play does not require one, and it would be public.

A personal account that sells nothing does not have to show a postal address on the listing.

## Listing

`android/store/listing.toml` holds the title (30 characters), short description (80) and full description (4000);
`scripts/play.py listing` refuses text over those limits. The description is the iOS one with Apple Health replaced by
Health Connect and iCloud sync by Android's backup. Play's metadata policy forbids price and promotional words such as
"free" or "best" in the title, icon and developer name, and reviewers apply it loosely to the short description too, so
"free" appears only in the body.

Graphics, rendered by `scripts/render-play-graphics.sh` from the pint glyph the iOS icon is drawn from:

- **Icon** (512 × 512, `android/store/icon.png`): full-bleed, since Play applies its own corner mask.
- **Feature graphic** (1024 × 500, `android/store/feature-graphic.png`): the name to the left and the glyph to the
  right, leaving the centre clear of the play button Play may lay over it.
- **Phone screenshots:** 2 to 8 PNGs in `android/store/screenshots/phone/`, uploaded in name order. Play will not
  publish the listing without at least two. They have to come from the Android app, so none exist yet.

## Content rating

The IARC questionnaire, under Policy › App content › Content rating. Category: **All other app types** (not a game,
not social or communication). Play's wording changes between revisions; the answers are:

| Topic | Answer | Why |
|---|---|---|
| Violence, blood, fear | No | |
| Sexuality, nudity | No | |
| Offensive language | No | Drink names are as their brewers print them; none is crude. |
| Controlled substances: references to alcohol | **Yes** | The app is about alcohol: names, strengths and serves of drinks. |
| Depicts consumption, or encourages use | No | It records what the user drank and helps them drink less. Nothing in it presents drinking favourably. |
| Sale or purchase of alcohol | No | Prices are what the user paid, for their own total. Nothing can be bought. |
| Gambling, simulated gambling | No | |
| Users interact or exchange content | No | No accounts, no messaging, nothing shared between users. |
| Shares the user's location | No | |
| Digital purchases | No | |
| Unrestricted web access | No | The app opens a few fixed links to guidance pages and nothing else. |

Answering *yes* to alcohol references will rate the app above the youngest bands; how far above varies by rating
authority. The age the app is meant for is set separately, under Target audience.

## Target audience and content

- **Target age groups:** 18 and over, only.
- **Could the store listing unintentionally appeal to children?** No.

An app that tracks alcohol is for people old enough to drink it, which in most countries is 18 or over. Leaving every
younger group unticked also keeps the app outside the Families policy, which an alcohol app could not meet.

## Other App content declarations

- **Privacy policy:** https://groglog.io/privacy.html
- **Ads:** No, the app contains no ads.
- **App access:** All functionality is available without special access. There is no sign-in.
- **Advertising ID:** No, the app does not use it. Check the merged manifest of a release build has no
  `com.google.android.gms.permission.AD_ID`, which some libraries add.
- **Government app:** No.
- **Financial features:** None.
- **News app:** No.
- **Health apps:** Yes. Choose the features closest to tracking alcohol intake in order to reduce it (Play's list has
  varied; at the time of writing, health and wellness tracking and habit or addiction support). Confirm it is not a
  medical device and does not diagnose or treat anything, as the description says.
- **Health Connect:** see below.
- **Data safety:** see below.

## Data safety

Play defines *collection* as data transmitted off the user's device by the app, and *sharing* as a transfer of
collected data to a third party. GrogLog sends nothing off the device: there is no server, no account, no analytics or
crash SDK, and no advertising. The form, question by question:

1. **Does your app collect or share any of the required user data types?** No.

   That answer ends the form, so the questions on encryption in transit and deletion requests are not asked. The
   listing will show *No data collected* and *No data shared*. The reasons, should Play ask:

   - **The log** is stored in the app's private storage on the device.
   - **Health Connect data** is read and written on the device, through Health Connect, and never transmitted. Play
     counts on-device processing as neither collection nor sharing.
   - **Android Auto Backup** copies the app's storage to the user's own Google account, done by the operating system
     rather than the app, and end-to-end encrypted with the device's screen lock on Android 9 and later. The developer
     cannot read it, as with iCloud Backup on iOS. Play's guidance does not address OS backup directly; this is the one
     answer that rests on interpretation, and it is the same one Apple accepts for iOS.
   - **Exports** are files the user chooses to create and hands to the share sheet. Play exempts transfers made by a
     specific user action the user expects, and the app itself transmits nothing.

2. **Security practices** and **Data types**: not asked after a *No*.

If a later version adds any network request that carries user data (a crash reporter, a sync server, fetched prices),
this answer has to change before that version ships.

## Health Connect

Health Connect permissions are declared under Policy › App content › Health Connect, which appears once a bundle that
requests them has been uploaded. Every requested permission needs its own justification, and requests that are vague
or broader than a feature needs are refused. GrogLog requests exactly these, each behind its own switch in Setup and
off by default:

| Permission | Justification |
|---|---|
| `android.permission.health.READ_HEART_RATE` | Reports shows the user's heart rate while asleep against the alcohol they logged the evening before, so they can see what drinking does to their recovery overnight. Only readings inside a sleep session are used. |
| `android.permission.health.READ_RESTING_HEART_RATE` | Reports shows resting heart rate by day and week next to the units drunk, because a raised resting rate is the slowest-recovering sign of a run of heavy nights. |
| `android.permission.health.READ_HEART_RATE_VARIABILITY` | Reports shows overnight heart rate variability against the previous evening's drinking. A lower HRV after drinking is the most direct measure of its effect on the user's recovery. |
| `android.permission.health.READ_SLEEP` | Reports shows each night's sleep, by stage, against the evening before, and the heart readings above are taken from inside the sleep session. |
| `android.permission.health.WRITE_NUTRITION` | When the user turns on copying, the energy (kcal) of each drink they log is written as a nutrition record, so the calories from alcohol count in the other health and diet apps they use. |
| `android.permission.health.READ_HEALTH_DATA_HISTORY` | The weekly and monthly charts compare recovery before and after the user started cutting down, which needs readings from before they installed the app. Health Connect otherwise allows only the 30 days before the first grant. Requested with the heart and sleep switches. |

Health Connect has no record type for alcohol, so GrogLog writes no alcohol data at all; the nutrition records carry
only energy, named after the drink. Turning copying off deletes them. Background reading is not requested: Reports reads
only while it is on screen.

The use case to select is **fitness, wellness and coaching**: the app helps the user understand and improve their own
wellbeing. Play reviews substance use more closely; GrogLog neither reads nor writes any substance-use data type, and
the justifications make clear that the heart and sleep readings serve a user-facing feature.

Health Connect also requires, in the app itself:

- an activity that handles `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE`, showing the privacy policy, which Health
  Connect opens from its permission screen (`PrivacyActivity`, which shows `site/public/privacy.html` as packaged at
  build time, so a change to the policy reaches the app with the next build);
- on Android 14 and later, an `activity-alias` handling `android.intent.action.VIEW_PERMISSION_USAGE` with category
  `android.intent.category.HEALTH_PERMISSIONS`, pointing at the same activity;
- the permissions listed in the manifest, and nothing requested that is not used.

## Alcohol content

Play's Inappropriate Content policy
([Tobacco and alcohol](https://support.google.com/googleplay/android-developer/answer/9878810)) forbids apps that
facilitate the sale of tobacco, encourage illegal or inappropriate use of alcohol, depict or encourage alcohol use by
minors, or portray excessive, binge or competitive drinking favourably. It does not forbid apps about alcohol, and drink
trackers and sobriety apps are common on Play. GrogLog stays clearly inside it if:

- the listing and screenshots read as a tool for drinking less, which the text does throughout;
- nothing presents a large total as an achievement: streaks reward dry days and staying under budget, never volume;
- the catalogue's brands and prices are presented as data for the user's own log, with no links to buy anything;
- the target audience is 18 and over, and the medical disclaimer stays in the description and the app.

The points a reviewer is most likely to question, and the answer to each: the catalogue names commercial brands (it
is a lookup table, as a calorie counter names food brands); a "budget" of units left could be read as an allowance to
drink up to (it is the reduction plan's ceiling, and the description says so); the icon and feature graphic show a full
pint (it is the app's mark, the same as on iOS, and shows no person drinking).

## Signing

Play App Signing holds the key that signs what users install; the developer keeps only an *upload key*, which proves a
bundle came from them and can be reset through Play support if lost. Play App Signing is chosen when the first bundle
is uploaded, and is required for app bundles.

### Creating the upload key

On a laptop, once. `keytool` comes with the JDK in `mise.toml`.

```sh
keytool -genkeypair -v -keystore groglog-upload.jks -storetype PKCS12 -alias upload \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=James Cleveland, O=GrogLog, C=GB"
```

It asks for one password; a PKCS12 store uses it for the key as well. Keep both in 1Password, then delete the local
copy:

```sh
op document create groglog-upload.jks --title "GrogLog Android upload keystore" --vault Private
op item create --category password --title "GrogLog Android upload keystore password" --vault Private \
  'password=<the password>'
rm groglog-upload.jks
```

### GitHub secrets

```sh
op document get "GrogLog Android upload keystore" --vault Private | base64 \
  | gh secret set ANDROID_UPLOAD_KEYSTORE --repo radiosilence/groglog
op read "op://Private/GrogLog Android upload keystore password/password" \
  | gh secret set ANDROID_UPLOAD_KEYSTORE_PASSWORD --repo radiosilence/groglog
op read "op://Private/GrogLog Android upload keystore password/password" \
  | gh secret set ANDROID_UPLOAD_KEY_PASSWORD --repo radiosilence/groglog
gh secret set ANDROID_UPLOAD_KEY_ALIAS --repo radiosilence/groglog --body upload
```

### Gradle

`android/app/build.gradle.kts` signs the release build with the upload key when its location is given, and otherwise
builds it unsigned, so CI on a pull request and a laptop without the key still bundle. Each value is read from the
environment (CI) or a Gradle property (a laptop's `~/.gradle/gradle.properties`, never the repository's).
`versionCode` comes from `-PversionCode`, which CI sets to the run number times 100 plus the attempt (see
[releasing.md](releasing.md)).

```kotlin
fun setting(env: String, property: String) =
    providers.environmentVariable(env).orElse(providers.gradleProperty(property))

val uploadKeystore = setting("ANDROID_UPLOAD_KEYSTORE_FILE", "groglogUploadKeystoreFile")

android {
    defaultConfig {
        versionCode = providers.gradleProperty("versionCode").orNull?.toInt() ?: 1
    }

    signingConfigs {
        if (uploadKeystore.isPresent) {
            create("upload") {
                storeFile = file(uploadKeystore.get())
                storePassword = setting("ANDROID_UPLOAD_KEYSTORE_PASSWORD", "groglogUploadKeystorePassword").get()
                keyAlias = setting("ANDROID_UPLOAD_KEY_ALIAS", "groglogUploadKeyAlias").get()
                keyPassword = setting("ANDROID_UPLOAD_KEY_PASSWORD", "groglogUploadKeyPassword").get()
            }
        }
    }

    buildTypes {
        release {
            // Unsigned without the upload key: Play refuses it, but the build is still checked.
            signingConfig = signingConfigs.findByName("upload")
        }
    }
}
```

## Play API access

`scripts/play.py` and CI publish through the Google Play Developer API as a service account. Once:

```sh
gcloud projects create groglog-play --name "GrogLog Play"
gcloud services enable androidpublisher.googleapis.com --project groglog-play
gcloud iam service-accounts create play-publisher --project groglog-play --display-name "GrogLog Play publisher"
gcloud iam service-accounts keys create play-publisher.json \
  --iam-account play-publisher@groglog-play.iam.gserviceaccount.com
op document create play-publisher.json --title "GrogLog Play service account" --vault Private
gh secret set PLAY_SERVICE_ACCOUNT_JSON --repo radiosilence/groglog < play-publisher.json
rm play-publisher.json
```

Then, in Play Console › Users and permissions › Invite new users, invite
`play-publisher@groglog-play.iam.gserviceaccount.com` with access to GrogLog only, and these app permissions: *Release
apps to testing tracks*, *Release to production, exclude devices, and use Play App Signing*, and *Edit store listing,
pricing and distribution*. The account needs nothing at the Google Cloud level beyond existing. Permissions can take a
day to reach the API.

To use the script from a laptop:

```sh
PLAY_SERVICE_ACCOUNT_JSON="$(op document get 'GrogLog Play service account' --vault Private)" scripts/play.py status
```

## From nothing to production

A personal developer account has to run a closed test with at least 12 testers, each opted in for 14 consecutive days,
before Play will consider it for production. A tester who opts out and back in starts their 14 days again, so recruit
15 or more. In order, by hand:

1. **Verify the account.** Play Console asks a personal account to verify the developer's identity and that they have
   an Android device (through the Play Console app). Neither can be skipped.
2. **Create the app.** Play Console › Create app: name *GrogLog Drink Tracker*, default language English (United
   Kingdom), App, Free; accept the declarations. The package name is fixed by the first upload as `cc.blit.groglog`.
3. **App content.** Answer every form under Policy › App content as this page sets out: privacy policy, ads, app
   access, content rating, target audience, data safety, government app, financial features, health apps.
4. **Store listing.** Set up API access (above) and run `scripts/play.py listing`, or paste the text from
   `listing.toml` and upload the graphics by hand. Add at least two phone screenshots. Set the category and contact
   details under Store settings.
5. **Upload key and secrets.** Create the upload key and set the GitHub secrets (above).
6. **First bundle, by hand.** The Play API cannot see an app until a bundle has been uploaded in Play Console. Merge to
   main so CI builds a signed bundle; its upload step fails on this first run. Download the `bundle` artifact from that
   run, then in Testing › Internal testing › Create new release, accept Play App Signing and upload it. From the next
   run on, CI uploads to the internal track itself.
7. **Health Connect declaration.** With a bundle requesting the permissions uploaded, complete Policy › App content ›
   Health Connect with the justifications above. The closed test cannot go to review without it.
8. **Internal test.** Testing › Internal testing › Testers: create an email list with the developer's own Google
   account, roll the release out, and install through the opt-in link. This checks the signed build and Health Connect
   on a real phone; internal releases are not reviewed and need no waiting period.
9. **Closed test.** Testing › Closed testing › Alpha. Create a Google Group for the testers (simplest for friends:
   they join the group, and the group is the tester list), add it under Testers, and set a feedback email. Promote the
   internal release to Alpha (or run `scripts/play.py upload AAB alpha`), choose the countries, and send it to review.
   Once approved, send the testers the opt-in link: each must open it while signed in to the Google account in the
   group, accept, and install from Play.
10. **Fourteen days.** Keep at least 12 testers opted in for 14 consecutive days, and keep shipping to Alpha during
    them; Play's application asks what testers used, what they said and what changed as a result, so note feedback as
    it arrives. The Dashboard counts testers and days.
11. **Apply for production.** Dashboard › Apply for production, once the Dashboard says the requirement is met. The
    questions and the answers to give:
    - *How easy was it to recruit testers?* Testers were friends of the developer who drink and wanted to cut down.
    - *Did testers use all features?* Say which they used, from their feedback; Health Connect is the one most likely
      not to have been, since it needs a wearable.
    - *Target audience:* adults in the UK who drink and want to keep count of it or reduce it, often while following
      a plan from a GP or alcohol service.
    - *Value:* a one-tap drink log in UK units with a gradual reduction plan, a record that keeps unlogged days apart
      from dry ones, and no account or data collection.
    - *Expected installs in the first year:* a modest range; the iOS app's numbers are the guide.
    - *Changes from the closed test* and *how readiness was judged:* from the notes kept in step 10.
    Review takes about a week. A refusal says what to fix, and can mean another 14-day test.
12. **Production.** Testing › Closed testing › Promote release › Production, or `scripts/play.py upload AAB
    production`. Choose the countries, start a staged rollout (for example 20%), and raise it to 100% when nothing
    goes wrong. Production releases are reviewed, typically within a few days.

After that, each release follows [releasing.md](releasing.md).
