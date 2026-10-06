# Shipping TruckRoute to TestFlight

A runbook for getting a build into TestFlight. Written to be followed on a Mac
with Xcode — the repository's CI environment has no Xcode and cannot archive,
sign or upload anything.

## Before anything else: this has never run

No part of this app has been launched on a simulator or a device. CI proves it
compiles and that the scheduling, ordering and money arithmetic are right; it
proves nothing about whether the UI works. **Run it in a simulator first.** If
something is broken it will almost certainly be broken in a way that is obvious
in thirty seconds and invisible in a diff.

Worth driving specifically, because each one is a bug that was fixed by reading
rather than by running:

1. Edit an existing load and change its drop-off. (A SwiftUI `onAppear` bug used
   to discard the new pick.)
2. Set the region to Germany and re-save a load that has a rate. ($2,400 used to
   save as $2.40.)
3. Plan a week where a drop-off's window opens the day after its pickup. (The
   next day used to start at 08:00 regardless, scheduling the truck in two
   places.)
4. Turn on a delivery window on a load dated next week. (It used to open onto a
   validation error.)
5. Plan a route, then edit a load, and go back to the Route tab. (It should now
   say the plan is stale.)
6. Share the route sheet and check the PDF opens and is paginated.

## What you need that isn't in the repository

| Thing | Where it comes from |
|---|---|
| Apple Developer Program membership | The owner's Apple account |
| Team ID (`DEVELOPMENT_TEAM`) | Apple Developer → Membership |
| A registered bundle ID | See below |
| An App Store Connect app record | See below |

Everything else — icon, version, export compliance — is already set in the
project.

## Bundle identifier

The project ships `com.n0funallowed.TruckRoute`.

This has to be registered to the owner's team before the first upload, and it is
**permanent for the life of the app record**. If a different identifier is
wanted, change it now, in both the Debug and Release configurations of the
`TruckRoute` target, not later.

```bash
# check what's currently set
grep PRODUCT_BUNDLE_IDENTIFIER TruckRoute.xcodeproj/project.pbxproj
```

Register it at <https://developer.apple.com/account/resources/identifiers>, then
create the app record at <https://appstoreconnect.apple.com> → Apps → "+" →
New App, selecting that bundle ID. Name, primary language, and SKU are asked for
there; none of them is in the project.

## Versioning

- `MARKETING_VERSION` is `1.0` — the version testers see.
- `CURRENT_PROJECT_VERSION` is `1` — the build number.

**Every upload needs a build number that has never been used for this version.**
A re-upload with the same one is rejected after the archive completes, which is
a slow way to find out. Bump it before each archive:

```bash
agvtool next-version -all          # or edit CURRENT_PROJECT_VERSION directly
```

## Archive and upload

### The short way

Xcode → select "Any iOS Device (arm64)" as the destination → Product → Archive →
Distribute App → TestFlight & App Store. Xcode handles signing if the Apple
account is added under Settings → Accounts.

### From the command line

```bash
# 1. Archive. TEAM_ID is the owner's; signing is Automatic.
xcodebuild archive \
  -project TruckRoute.xcodeproj \
  -scheme TruckRoute \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/TruckRoute.xcarchive \
  DEVELOPMENT_TEAM=TEAM_ID \
  CODE_SIGN_STYLE=Automatic

# 2. Export a signed .ipa.
xcodebuild -exportArchive \
  -archivePath build/TruckRoute.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist docs/ExportOptions.plist

# 3. Upload. Needs an app-specific password, or an App Store Connect API key.
xcrun altool --upload-app \
  -f build/export/TruckRoute.ipa \
  -t ios \
  -u APPLE_ID_EMAIL \
  -p APP_SPECIFIC_PASSWORD
```

`docs/ExportOptions.plist` is in the repository with `TEAM_ID` as a placeholder —
substitute the real team ID, and do not commit it filled in.

An app-specific password is generated at <https://account.apple.com> → Sign-In
and Security → App-Specific Passwords. Prefer an App Store Connect API key
(`--apiKey` / `--apiIssuer`) for anything automated; it isn't tied to one
person's Apple ID and can be revoked on its own.

## After the upload

- Processing takes roughly 5–30 minutes before the build appears in TestFlight.
- **Export compliance is already answered** — `ITSAppUsesNonExemptEncryption` is
  `NO` in the project, because the app uses nothing beyond Apple's own HTTPS.
  TestFlight should not ask.
- **Internal testers** (up to 100, on the owner's team) get the build as soon as
  it finishes processing, with no review.
- **External testers** need a Beta App Review first, plus a description and a
  contact email. For getting it on the owner's own phone today, internal testing
  is the path.

## Things that will come up

**"No profiles for 'com.n0funallowed.TruckRoute' were found."** The bundle ID
isn't registered to the team, or the Apple account isn't signed in to Xcode.

**"Invalid bundle. Missing app icon."** The icon lives at
`TruckRoute/Assets.xcassets/AppIcon.appiconset/`. It is a single 1024×1024 PNG
with no alpha channel, which is what iOS 17+ expects; an icon with an alpha
channel is rejected, so if it gets replaced, keep it opaque.

**"The bundle version must be higher than the previously uploaded version."**
Bump `CURRENT_PROJECT_VERSION` — see Versioning above.

**Planning a big week takes about a minute.** That's intended, not a hang.
MapKit refuses directions requests that come too fast, so legs are measured
about 1.25 seconds apart; a 25-load week is 51 legs. Progress is reported per
leg. Before this pacing existed, the requests were refused and the legs silently
went unmeasured, which understated the mileage and the rate per mile.

**The app needs a home base before it can route anything.** Settings → Home
base. An empty address book means the Route tab has nothing to start from, and
it says so rather than failing.
