# Cab Hustle — working notes

A portrait, iPhone-only Flutter game built on Flame. Ships on the App Store as
**Cab Hustle**; the repo and Flutter package are still named `taxiGame` /
`taxi_game`.

All commands below run from `taxi_game/` unless stated otherwise. The Flutter
project is a subdirectory — running `flutter` at the repo root does nothing.

```bash
cd taxi_game
```

---

## Identity

| | |
|---|---|
| Bundle ID | `com.wjdavis5.taxigame` — **permanent**, bound to the App Store record |
| Apple Team ID | `5273C9R3V4` (individual, "William Davis") |
| App Store app ID | `6804508589` |
| Deployment target | iOS 15.0 |
| Device family | iPhone only (`UIDeviceFamily [1]`) |
| Orientation | Portrait only, enforced in `lib/main.dart` **and** `Info.plist` |

---

## Everyday commands

```bash
flutter pub get                  # after any pubspec change
flutter analyze                  # must be clean before committing
flutter test                     # full suite
flutter test test/settings_screen_test.dart   # one file
flutter run -d <device-id>       # run on a simulator or device
xcrun simctl list devices available | grep iPhone   # find a device id
```

CI runs `flutter analyze` and `flutter test` and blocks the release job on both.

---

## Screenshots for the App Store

Screenshots must be **1320×2868** (6.9″ iPhone) with **no alpha channel**.
App Store Connect rejects both wrong dimensions and any alpha channel, and
`sips` cannot strip alpha — hence the tool below.

Driving the UI from outside needs accessibility permissions this machine does
not grant, so `tool/screenshot_entry.dart` launches straight into one screen
instead. It is never referenced by `lib/main.dart` and ships in no build.

```bash
SIM=$(xcrun simctl list devices available | grep "iPhone 17 Pro Max" | grep -oE "[0-9A-F-]{36}")
xcrun simctl boot "$SIM"; open -a Simulator

# Clean status bar: Apple's 9:41, full signal, no notification banners.
xcrun simctl status_bar "$SIM" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3

# SHOT = menu | game | garage | credits | settings
flutter build ios --simulator --debug \
  -t tool/screenshot_entry.dart --dart-define=SHOT=settings
xcrun simctl uninstall "$SIM" com.wjdavis5.taxigame
xcrun simctl install  "$SIM" build/ios/iphonesimulator/Runner.app
xcrun simctl launch   "$SIM" com.wjdavis5.taxigame
sleep 6
xcrun simctl io "$SIM" screenshot /tmp/raw.png

# Strip the alpha channel App Store Connect rejects.
swiftc -O -o /tmp/strip_alpha ../tools/strip_alpha.swift
/tmp/strip_alpha /tmp/raw.png /tmp/03-settings.png
```

Verify before uploading:

```bash
sips -g pixelWidth -g pixelHeight -g hasAlpha /tmp/03-settings.png
# want: 1320 x 2868, hasAlpha: no
```

---

## App icon

The icon is generated, not hand-drawn. Editing the artwork means editing
`tools/make_app_icon.swift` and regenerating every size:

```bash
tools/generate_app_icons.sh      # from the repo root
```

It renders the 1024 master, downsamples all 15 declared sizes plus the launch
images, and **fails the run** if the marketing icon comes out with an alpha
channel — Apple rejects that outright.

---

## Building for release

```bash
# Compile check, no signing needed.
flutter build ios --release --no-codesign

# Signed archive. Requires a signed-in Xcode account.
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/ios/archive/Runner.xcarchive archive \
  -allowProvisioningUpdates

# Export a distributable .ipa (automatic signing, local).
xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath build/ios/ipa
```

`flutter build ipa` also works but does **not** pass
`-allowProvisioningUpdates`, so it fails whenever a provisioning profile needs
creating or refreshing. Prefer the `xcodebuild` form above.

### Signing gotcha — do not pass signing settings to `xcodebuild archive`

Signing settings on the `xcodebuild` command line apply to **every** target in
the workspace, and CocoaPods and Swift Package targets reject a provisioning
profile outright:

```
error: objective_c does not support provisioning profiles
```

Archive unsigned and sign during export instead — that is what CI does, and
`ios/ExportOptions-ci.plist` names the identity and profile explicitly:

```bash
xcodebuild ... archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild -exportArchive -exportOptionsPlist ios/ExportOptions-ci.plist ...
```

Two export options files exist and they are not interchangeable:

- `ios/ExportOptions.plist` — automatic signing, for a developer with Xcode
  signed in.
- `ios/ExportOptions-ci.plist` — manual signing against a named certificate and
  the `TaxiGame` profile, for CI.

---

## Verifying a build before uploading

Every failed upload permanently burns a build number, so check the archive
first. These are the two defects that got the first upload rejected:

```bash
APP=build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
plutil -extract UIDeviceFamily         json -o - "$APP/Info.plist"   # want [1]
plutil -extract MinimumOSVersion       raw  -o - "$APP/Info.plist"   # want >= 15.0
plutil -extract CFBundleIdentifier     raw  -o - "$APP/Info.plist"
plutil -extract CFBundleShortVersionString raw -o - "$APP/Info.plist"
plutil -extract CFBundleVersion        raw  -o - "$APP/Info.plist"
ls "$APP/PrivacyInfo.xcprivacy"                                      # must exist
codesign -dvv "$APP" 2>&1 | grep Authority
```

CI runs equivalent assertions and fails in seconds rather than after an upload
round trip.

---

## Publishing

Run **`/release`** — it handles the whole flow: preflight checks, version bump,
push, watching the pipeline, and verifying the build reached App Store Connect.
The rest of this section is what that skill automates, for when you need to do
it by hand or debug it.

### Automatic (preferred)

Pushing to `main` runs `.github/workflows/ios-release.yml`: analyze, test,
archive, export, verify, upload to TestFlight.

**App Store review submission fires while App Store Connect shows no
unfinished review submission for the app and no submitted or handled
version matching `version:` in `pubspec.yaml`.** Apple rejects a second
submission for a version string already submitted, so the pipeline asks
Apple's API (`tools/asc_version_state.rb`) — two sources, and it fails
closed on any answer it cannot trust. First, `reviewSubmissions` for the
app: any record actively holding a review slot — `WAITING_FOR_REVIEW`,
`IN_REVIEW`, or a state the gate does not recognize — prints
`REVIEW_IN_FLIGHT` and the run goes TestFlight only, whatever the version
records said — the build-1074 run of issue #93 read a version list that
came back without the in-review version as "no version yet" and tried to
submit over a live review. A record parked in `UNRESOLVED_ISSUES` (where
Apple leaves a submission after rejecting the version) or
`READY_FOR_REVIEW` (created, never confirmed) prints `REVIEW_STUCK`:
still TestFlight only — no second submission may be created while it
exists — but with a `::warning::` annotation, because no push can clear
it and a version bump alone will not submit (issue #102). Second, the
version's own records: submit when the version is not
on Apple's side yet (`NONE`) or every matching record is still
machine-editable (`PREPARE_FOR_SUBMISSION`, `INVALID_BINARY`). Any other
state — in review, approved, on sale, developer-rejected — goes to
TestFlight only. Human rejections (`REJECTED`, `METADATA_REJECTED`) no
longer auto-resubmit on a routine push: the issue sweep pushes about
hourly, and resubmitting a rejection nobody has addressed must be a human
act — bump the version or use the manual dispatch below, and clear the
rejected submission in App Store Connect first: until it is gone the gate
answers `REVIEW_STUCK` and neither route submits. An answer the
gate cannot trust (non-200, an empty version list — a live app always has
version records — page-limit truncation) fails the run outright rather
than guessing either way. The decision is idempotent: a bump whose own
run fails before Submit is picked up by the next push, where the old
compare-against-the-previous-commit gate logged "Version unchanged" and
lost the submission (issue #89). Bumping the version is still the signal
that a release is intended — it is what makes the state check find no
record yet.

```bash
# Ship 1.0.1 to review: edit pubspec.yaml, then push.
#   version: 1.0.1+1        <- the +build part is ignored; CI sets its own
git commit -am "release: 1.0.1" && git push
```

Build numbers come from `github.run_number + 1000`, so they are monotonic and
cannot collide with anything uploaded by hand.

To force a submission without a version bump: Actions → **iOS Release** → Run
workflow → tick *Submit for App Store review*.

Required repository secrets (all set):
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`,
`IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`,
`IOS_PROVISION_PROFILE_BASE64`.

### Manual

Archive and export as above, then open the archive in Xcode's Organizer and use
**Distribute App → App Store Connect → Upload**:

```bash
open build/ios/archive/Runner.xcarchive
```

---

## Querying App Store Connect

Quickest path is the helper the release skill uses:

```bash
ruby .claude/skills/release/scripts/asc.rb status   # builds, version, listing gaps
ruby .claude/skills/release/scripts/asc.rb builds
ruby .claude/skills/release/scripts/asc.rb version
```

It needs `.env` (gitignored) with `ASC_KEY_ID` and `ASC_ISSUER_ID`, plus that
key's file — named exactly `AuthKey_<ASC_KEY_ID>.p8` (any other `AuthKey_*.p8`
on the machine is ignored) — in `~/Downloads` or
`~/.appstoreconnect/private_keys`.

### Raw API

Faster and more reliable than clicking through the site, and the only way to
answer "did my build actually arrive". Needs `.env` (gitignored) holding
`ASC_KEY_ID` and `ASC_ISSUER_ID`, plus the `.p8` key file.

The API authenticates with a short-lived ES256 JWT. Ruby's stdlib can build one
with no gems — see the client used during setup, which signs a JWT and hits
endpoints like:

```
GET  /v1/apps?limit=50
GET  /v1/builds?filter[app]=6804508589
GET  /v1/builds/{id}/buildBetaDetail            # TestFlight readiness
GET  /v1/apps/6804508589/appStoreVersions       # appStoreState
GET  /v1/appStoreVersions/{id}/appStoreVersionLocalizations
PATCH /v1/ageRatingDeclarations/{id}
POST /v1/appScreenshots                          # then PUT bytes, then PATCH uploaded:true
```

**App Privacy is not exposed on this API version** — `appDataUsages`,
`appDataUsageCategories`, and `appDataUsagePublishState` all 404. It must be
answered in the App Store Connect UI.

---

## Conventions and constraints worth knowing

- **Never commit signing material.** `.env`, `*.p12`, `*.p8`, `*.cer`,
  `*.mobileprovision` are gitignored. CI gets them from GitHub secrets.
- **`project.pbxproj` and `Info.plist` use CRLF line endings.** Editing them
  with a script that rewrites newlines turns a 12-line change into a 616-line
  diff. Preserve them (`open(path, newline='')` in Python).
- **Ship no placeholder UI.** Buttons that show "coming soon" are an App Store
  Guideline 2.1 rejection trigger. The sound and music toggles are surfaced in
  settings and drive the real audio settings (issue #4); any new toggle must
  change something the player can perceive or it does not ship.
- **Audio ships.** `AudioService` plays through `flame_audio` (issue #4).
  Every bundled audio file is listed in `assets/licenses/LICENSES.txt` with a
  confirmed source — the Kenney CC0 packs (converted OGG → WAV, since no
  Apple platform decodes Vorbis) and three files synthesized in-repo by
  `taxi_game/tool/make_generated_audio.dart` (byte-stable, seeded). Anything
  attribution-required must be credited in `lib/data/credits.dart`; nothing
  attribution-required currently ships. The test suite enforces the
  inventory: every asset under `assets/audio/` must be named in
  LICENSES.txt (`test/audio_service_test.dart`).
- **Attribution has one owner:** `lib/data/credits.dart`. The credits screen
  renders it; do not inline credit text in the UI.
- **Progress is on-device only** (`shared_preferences`). The app makes no
  network calls at all, which is what the privacy policy and the
  `PrivacyInfo.xcprivacy` manifest both claim. Adding any network call means
  updating both plus the App Privacy answers.

---

## Layout

```
taxiGame/
├── .github/workflows/
│   ├── flutter-builds.yml     # analyze/test/build on push + PR (Android + unsigned iOS)
│   └── ios-release.yml        # signed release pipeline, main only
├── docs/
│   ├── plans/                 # implementation plans
│   ├── privacy-policy.md      # published via GitHub Pages
│   └── support.md             # published via GitHub Pages
├── tools/
│   ├── asc_version_state.rb   # App Store Connect version + review-submission
│   │                          #   state — the release workflow's fail-closed
│   │                          #   submit gate asks it (two sources)
│   ├── make_app_icon.swift    # icon artwork
│   ├── generate_app_icons.sh  # renders every declared size
│   └── strip_alpha.swift      # removes the alpha channel from a PNG
└── taxi_game/                 # the Flutter project
    ├── lib/
    │   ├── game/              # Flame components, levels, systems
    │   ├── data/credits.dart  # attribution, single source of truth
    │   ├── services/          # storage, game state, audio, haptics, share
    │   └── ui/screens/        # menu, game, daily, garage, records, stats,
    │                          #   settings, credits
    ├── tool/screenshot_entry.dart   # dev-only, launches into one screen
    ├── fastlane/              # submit lane only; build/upload live in the workflow
    └── ios/
        ├── ExportOptions.plist      # local, automatic signing
        └── ExportOptions-ci.plist   # CI, manual signing
```

Published pages:
<https://wjdavis5.github.io/taxiGame/privacy-policy> ·
<https://wjdavis5.github.io/taxiGame/support>
