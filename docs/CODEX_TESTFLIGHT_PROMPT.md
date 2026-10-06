# Deploy TruckRoute to TestFlight

You're on a Mac with Xcode. Get a build of TruckRoute into TestFlight for internal testing today. Repository: https://github.com/N0FunAllowed/TruckRoute

## Ground rules

- **Read `docs/TESTFLIGHT.md` first.** It's the runbook, with the exact commands and the errors you're likely to hit. This prompt is the plan; that file has the detail.
- **Don't change app code** unless a build or upload error forces it. If it does, make the smallest fix, commit it on a branch, and tell me. Don't push to `master`.
- **Don't commit secrets.** The team ID, Apple ID, app-specific password and API keys stay out of git. `docs/ExportOptions.plist` has a `TEAM_ID` placeholder: fill it in a local copy or at the command line, and don't commit the filled-in file.
- **Stop and ask me** before anything you can't undo or anything that needs my Apple account: registering the bundle ID, creating the App Store Connect record, choosing an app name or SKU, and the upload itself.

## Step 0: Get the right code

PR #9 holds the whole app. Check whether it's merged:

- **Merged:** work from `master`.
- **Not merged:** work from branch `claude/trucking-app-routing-prompt-5ckvae` and tell me it isn't merged yet. Don't merge it yourself.

The last verified commit is `d057d4e`. CI is green on it: 53 unit tests pass, and a Release arm64 device build passes `-validate-for-store` with no warnings. If HEAD is newer than `d057d4e`, say what changed.

## Step 1: Build and test locally

```bash
xcodebuild test -project TruckRoute.xcodeproj -scheme TruckRoute \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Use whichever iPhone simulator is installed. All 53 tests should pass. If any fail, stop and report.

## Step 2: Run it in the simulator (don't skip this)

**Nobody has ever run this app.** CI shows it compiles and that the calculations are right. It shows nothing about whether the UI works. Launch it in the simulator and check these six things. Each is a fix made by reading the code, never confirmed by running the app:

1. Add a home base (Addresses, then Settings → Home base), two or three addresses, and a couple of loads. Plan a route. Confirm the map, stops and times appear.
2. Edit an existing load and change its drop-off. The new drop-off must stick after Save.
3. Set the simulator region to Germany. Re-save a load with a rate of 2400. It must still read $2,400, not $2.40.
4. Turn on a delivery window on a load dated next week. The form must not open straight onto a validation error.
5. After planning a route, edit a load and go back to the Route tab. It should say the plan is stale and offer Replan.
6. Share the route sheet. The PDF should open and be readable.

Planning makes about one MapKit request every 1.25 seconds, so a week with many loads takes up to a minute. That's intended, not a hang.

Report each item as pass or fail, with a screenshot for any failure. A crash, or anything badly broken in items 1–3, is a reason to stop before uploading: tell me what broke. Cosmetic issues are worth listing but shouldn't block the upload.

## Step 3: Signing and App Store Connect (needs me)

Before archiving, confirm with me:

- **Bundle ID:** the project uses `com.n0funallowed.TruckRoute`. It's permanent once the App Store Connect record exists, so ask me whether to keep it. If I want a different one, change `PRODUCT_BUNDLE_IDENTIFIER` in both the Debug and Release configurations of the `TruckRoute` target.
- **Team ID:** ask me for it (Apple Developer → Membership).
- Whether the bundle ID is already registered, and whether an App Store Connect app record already exists. If not, either walk me through creating them or do it with my go-ahead.

## Step 4: Archive, export, upload

Follow `docs/TESTFLIGHT.md` → "Archive and upload": either Xcode Organizer, or `xcodebuild archive` → `xcodebuild -exportArchive` → `xcrun altool --upload-app` (or an App Store Connect API key).

- `MARKETING_VERSION` is `1.0` and `CURRENT_PROJECT_VERSION` is `1`. That's fine for the first upload. **Bump the build number before any re-upload**, or App Store Connect will reject it.
- Export compliance is already declared (`ITSAppUsesNonExemptEncryption = NO`), so TestFlight shouldn't ask about encryption.
- The app icon is a single 1024×1024 opaque sRGB PNG. If you replace it, keep it opaque.

## Step 5: TestFlight

- Wait for processing (5–30 minutes).
- Add me as an **internal tester**. Internal testing needs no Beta App Review. Don't submit for external testing unless I ask.

## When you're done, report

- The commit you built from and whether PR #9 was merged.
- Test results, and pass/fail for each of the six simulator checks.
- Bundle ID, version and build number uploaded.
- Whether the build finished processing and is available to internal testers.
- Any warnings from archive, export or upload, quoted exactly, plus any changes you had to make and where you committed them.
