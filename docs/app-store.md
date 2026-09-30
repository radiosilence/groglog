# App Store listing

What App Store Connect asks for, kept here so a change to the listing is reviewed like any other. `just store listing`
sends it to App Store Connect; the limits in brackets are Apple's.

## App information

- **Name:** GrogLog Drink Tracker
- **Subtitle** (30): Drink diary for cutting down
- **Primary category:** Health & Fitness
- **Secondary category:** Lifestyle
- **Copyright:** © 2026 James Cleveland
- **Marketing URL:** https://groglog.io
- **Support URL:** https://groglog.io/support.html
- **Privacy Policy URL:** https://groglog.io/privacy.html
- **Price:** Free, no in-app purchases

## Age rating

The questionnaire asks how often the app refers to alcohol. GrogLog is about nothing else, so the answer is
*frequent*, which rates it 18+, the intended audience.

## App Privacy

**Data Not Collected.** The app has no account, server, analytics or advertising SDK. iCloud sync stores the log in the user's private CloudKit database, which the developer cannot read; Apple does not count that as collected. Health
data it reads or writes never leaves the device, which Apple's definition of "collected" excludes.

## Promotional text (170)

Log a drink in one tap, see where the day stands, and follow a plan to drink less. Free, with no account, no adverts
and no tracking.

## Description

GrogLog is a drink diary for people who want to drink less. It keeps an honest count and puts it where you can see it.

LOG IN ONE TAP
Your usual drinks sit on one screen, and a tap logs one. Long-press for another size, a drink you had earlier, or
several at once. Over eleven hundred drinks are in the catalogue at their label strengths, from cask ale and craft
beer to wine, spirits and Polish vodka, so a new one is a search away.

SEE WHERE THE DAY STANDS
Today is a running total against yesterday and your usual day, with what it has cost and how much of today's budget
is left. A drink after midnight counts towards the evening it belonged to.

CUT DOWN AT A PACE YOU SET
Set a gradual reduction and GrogLog gives you a daily and weekly budget that comes down over time, within the limits
in UK clinical guidance for reducing without medication.

AN HONEST RECORD
A forgotten day stays a gap rather than counting as a dry one, so your averages and streaks describe what
happened. Reports chart each week and month against the ones before.

YOUR BODY, THE MORNING AFTER
If you allow it, GrogLog reads your heart rate, HRV and sleep from Apple Health and shows them against what you drank
the evening before. It can also copy your drinks into Health.

PRIVATE AND FREE
There is no account, no server, no analytics and no advertising. Your log is stored on your phone and synced
through your own iCloud account, so it comes back on a new iPhone; nobody else can read it. You can export all of it
whenever you want. GrogLog is free, with nothing held back for a paid tier.

GrogLog does not provide medical advice. It is intended to help you follow a plan agreed with your GP or an alcohol
service. If you are dependent on alcohol, stopping suddenly can be dangerous: please speak to a doctor before you begin.

## What's new

iCloud sync. Your log is kept in your own iCloud account, so it comes back on a new iPhone. Only you can read it,
and you can turn it off in Setup.

## Keywords (100)

alcohol,units,drinking,cut down,sober,taper,drink tracker,dry,sobriety,beer,wine,pint,habit,diary

## Review notes

Purpose and audience. GrogLog is a drink diary for adults who want to keep track of how much they drink, and to
cut down if they choose to. Each drink is logged with its strength and size, and the app converts it to UK alcohol
units, the measure UK health guidance uses. It shows the day's total against the person's usual day and the UK
low-risk guideline of 14 units a week, and can set a gradual reduction that lowers a daily and weekly budget over
time. The problem it solves is that people underestimate what they drink; a running count in units, kept honestly,
makes it visible. It is free, with no account, no adverts and no tracking.

Setting up and using it. No sign-in, account or sample file is needed. The app opens on the Log tab: tap a drink to
log it, long-press one for another size or time, or search the catalogue of over eleven hundred UK drinks. The Day tab
shows today's total; Calendar shows past days; Reports charts weeks and months. A reduction goal is set from the Goal
row in Setup or the Goal button on Reports. Apple Health is optional and off by default, with each switch in Setup.

External services. None of the developer's own. The app has no server and makes no network requests itself. It uses
only Apple frameworks: iCloud (CloudKit and the key-value store) to sync the user's log and settings to their own
private iCloud account, HealthKit to write drinks to Health and read heart rate, HRV and sleep if the user allows it,
and WidgetKit for the home screen widget. There are no analytics, advertising, authentication, payment or AI services.
The drinks catalogue and a snapshot of European Central Bank exchange rates are bundled in the app.

Regional differences. The app works the same in every region. It counts in UK units and cites UK guidance, because
those are what it is built around, and its catalogue is of drinks sold in the UK; a drink can be added by hand
anywhere. Prices can be shown in any currency the bundled exchange rates cover.

Regulated industry. GrogLog does not sell or promote alcohol and is not a medical device. It does not diagnose or
treat anything. The reduction limits it applies are taken from public guidance, the UK Department of Health and
Social Care's clinical guidelines for alcohol treatment (2025) and NICE guideline CG115, which the app links to in
the goal screen. Setup, the goal screen and the App Store description all state that the app does not provide
medical advice, and advise anyone dependent on alcohol to speak to a doctor before reducing. The age rating is 18+.

## Screenshots

`scripts/store-screenshots.sh <dir>` produces the 6.9-inch set App Store Connect requires for an iPhone app, from the
demo data with Apple's standard status bar. The same images are on the website.
