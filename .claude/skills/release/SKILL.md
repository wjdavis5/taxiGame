---
name: release
description: Ship a Cab Hustle release. Bumps the version, pushes to main, watches the CI pipeline build/sign/upload to TestFlight, and reports whether the App Store submission fired. Use when the user wants to release, ship, cut a version, publish to TestFlight, or submit for App Store review.
---

# Release

Ships an iOS release of Cab Hustle through the GitHub Actions pipeline. The
user never handles an `.ipa` — pushing to `main` builds, signs, and uploads
(while the version's train on App Store Connect still accepts builds), and
submits while the version is unsubmitted.

**Never upload manually when the pipeline can do it.** Manual Xcode Organizer
uploads exist only as a fallback for when CI is broken.

## The one rule that shapes everything

**App Store review submission fires while App Store Connect shows no
unfinished review submission for the app and no submitted or handled
version matching `version:` in `pubspec.yaml`.** Apple permanently rejects
a second submission for a version string already submitted, so the
pipeline asks Apple (`tools/asc_version_state.rb`) — two sources, failing
closed on any answer it cannot trust — and decides like this:

- Any `reviewSubmissions` record actively holding Apple's review slot
  (`REVIEW_IN_FLIGHT` — `WAITING_FOR_REVIEW`, `IN_REVIEW`, `COMPLETING`,
  `CANCELING`, or any state the gate does not recognize) → build and
  upload to TestFlight **only**, whatever the version records said. This
  is the guard that would have stopped the build-1074 run, which read a
  version list that came back without the in-review version as "no
  version yet" and tried to submit over a live review (issue #93).
- A submission stuck with no review running (`REVIEW_STUCK` —
  `UNRESOLVED_ISSUES`, where Apple parks a submission after rejecting the
  version, or `READY_FOR_REVIEW`, created but never confirmed) → build
  and upload to TestFlight **only**, with a `::warning::` annotation. No
  second submission may be created while it exists, and no push — a
  version bump included — can clear it: resolve the rejection or remove
  the submission in App Store Connect first (issue #102).
- No record for the version yet (`NONE`), or every matching record still
  machine-editable (`PREPARE_FOR_SUBMISSION`, `INVALID_BINARY`) → build,
  upload to TestFlight, **and submit for review**.
- Any matching record submitted or handled but still open to builds —
  `WAITING_FOR_REVIEW`, `IN_REVIEW`, `REJECTED`, `METADATA_REJECTED`,
  `DEVELOPER_REJECTED`, `PENDING_CONTRACT`, `WAITING_FOR_EXPORT_COMPLIANCE`,
  `READY_FOR_REVIEW` → build and upload to TestFlight **only**.
- Any matching record closed to new builds — approved
  (`PENDING_APPLE_RELEASE`, `PENDING_DEVELOPER_RELEASE`,
  `PROCESSING_FOR_APP_STORE`), on sale (`READY_FOR_SALE`,
  `PREORDER_READY_FOR_SALE`), removed, `REPLACED_WITH_NEW_VERSION`, or any
  state the gate does not recognize → **no build at all**: the run skips
  the whole build lane, stays green, and emits a `::warning::` naming the
  version bump as the only way to ship again (issue #119). Apple refuses
  new builds for a closed train, so uploading is a guaranteed red after a
  full macOS build.

Human rejections (`REJECTED`, `METADATA_REJECTED`) are TestFlight-only on a
routine push (issue #93): a person at Apple sent reasons someone must read
and act on, and this repo's automation pushes about hourly —
auto-resubmitting would fire unaddressed rejections at Apple with no human
involved. Resubmit deliberately: bump the version (new string → `NONE`) or
use the manual dispatch below — and clear the rejected submission in App
Store Connect first: while it sits `UNRESOLVED_ISSUES` neither route
submits anything, because the gate answers `REVIEW_STUCK` and every push
ships TestFlight only with a warning annotation (issue #102).
`INVALID_BINARY` still auto-resubmits
because it is Apple rejecting the artifact itself; the fix is a new build
and the next push attaches it.

Bumping the version is still the release signal: it is what makes the check
find no record on Apple's side yet. The decision is idempotent, so a bump
whose own run fails before the Submit step is submitted by the next push —
the old gate compared against the previous commit, logged "Version
unchanged", and lost such submissions forever (issue #89). A failed state
query fails the run rather than defaulting to TestFlight-only — and so
does an answer the gate cannot trust, such as an empty version list (a
live app always has version records) or a page-limit-truncated one.

Build numbers come from `github.run_number + 1000` and are set by CI. The
`+build` suffix in `pubspec.yaml` is ignored — never hand-edit it to control
the build number.

## Steps

### 1. Establish where things stand

Run all of these before proposing anything:

```bash
cd "$(git rev-parse --show-toplevel)"
git status --short                      # must be clean
git branch --show-current               # must be main
git fetch -q origin && git log --oneline origin/main..main   # unpushed commits
grep '^version:' taxi_game/pubspec.yaml
ruby .claude/skills/release/scripts/asc.rb status
```

The `asc.rb status` output is authoritative — read it rather than assuming.
It reports every build and its processing state, the editable version and its
state, whether a build is attached, whether a submission exists, and whether
the listing has description, keywords, support URL, and screenshots.

### 2. Check the blockers

Stop and tell the user if any of these hold. Do not push through them.

- **A version is already `WAITING_FOR_REVIEW` or `IN_REVIEW`.** A new version
  cannot be submitted while one is in review. The user must either wait for
  Apple, or remove the current submission in App Store Connect first. Say which
  version is blocking.
- **Working tree is dirty, or the branch is not `main`.** Releases come from
  `main`; anything else is a mistake.
- **The listing is missing description, keywords, support URL, or
  screenshots.** `asc.rb status` prints `*** EMPTY ***` for missing fields.
- **Screenshots do not match what the build will look like.** If UI changed
  since the screenshots were captured, they must be recaptured — a reviewer
  comparing a screenshot to the app is a real rejection path. See CLAUDE.md
  for the capture pipeline.

Also **remind, do not check**: App Privacy is not exposed on this API version
(`appDataUsages` and friends 404). If this is the first submission, the user
must have answered it in the App Store Connect UI.

### 3. Decide the release type

Ask the user, unless they already said which they want:

- **TestFlight only** — no version change. For testing a build on device
  before committing to a release. Only works while the current version's
  train is open: once the shipped version is approved or on sale, the gate
  skips the build entirely with a warning (issue #119) and nothing ships
  until the version is bumped.
- **Patch** (`1.0.0` → `1.0.1`) — bug fixes.
- **Minor** (`1.0.0` → `1.1.0`) — new functionality.
- **Major** (`1.0.0` → `2.0.0`) — a significant rework.

### 4. Verify locally before spending CI minutes

```bash
cd taxi_game && flutter analyze && flutter test
```

CI gates the release on both, so a failure here is a failure there — catch it
in seconds instead of minutes.

### 5. Bump and push

For a TestFlight-only release, skip the version edit and push whatever commits
are pending.

For a real release, edit only the marketing version in `taxi_game/pubspec.yaml`
(`version: 1.0.1+1` — leave the `+1`, CI overrides it), then:

```bash
git commit -am "release: 1.0.1"
git push origin main
```

### 6. Watch the run and verify the result

Watch the run for *this* push's commit, never "the newest run". Every push to
`main` fires this workflow, and its `ios-release` concurrency group queues
rather than cancels — so at any moment a newer run can be another push's, and
the old recipe (sleep a fixed 20 s, take `--limit 1`) watched whatever push
registered in that window and reported that push's result and build number as
this release's (issue #153). Steps 1–2 verified a clean tree on `main` and
step 5 just pushed, so `HEAD` is the pushed head for both release types —
capture it, then poll until GitHub registers a run for exactly that commit:

```bash
SHA=$(git rev-parse HEAD)
ID=""
for i in $(seq 1 30); do
  # --commit pins the lookup to this push; `// empty` keeps jq silent on a
  # miss so the emptiness check below fires (plain .[0] would print "null").
  ID=$(gh run list --repo wjdavis5/taxiGame --workflow=ios-release.yml --commit "$SHA" --json databaseId --jq '.[0].databaseId // empty')
  [ -n "$ID" ] && break
  sleep 5
done
gh run watch "$ID" --repo wjdavis5/taxiGame --exit-status --interval 20
```

If `$ID` is still empty after the loop (~2.5 minutes), stop and report that no
run registered for the pushed commit — never fall back to the newest run.
Every push to `main` triggers the workflow and the concurrency group queues
rather than cancels, so the newest run is easily someone else's push, and
reporting its result and build number as the release's is exactly the
failure of issue #153.

If it fails, read the actual failure rather than guessing:

```bash
gh run view "$ID" --repo wjdavis5/taxiGame --log-failed | tail -40
```

Then confirm the build genuinely arrived — a green run is not proof Apple
accepted it. Processing takes a few minutes, so allow for a delay:

```bash
sleep 90
ruby .claude/skills/release/scripts/asc.rb status
```

Expect a new build numbered `run_number + 1000` in state `PROCESSING` then
`VALID`. Get the run number with:

```bash
gh run view "$ID" --repo wjdavis5/taxiGame --json number --jq .number
```

### 7. Report

Tell the user, concretely:

- The build number that landed and its processing state.
- Whether the App Store submission fired, or that it was TestFlight-only and
  why.
- For a submission: that the version is `WAITING_FOR_REVIEW`, and what its
  release type means for the user — read the actual value from
  `asc.rb version`, never assume. `release=MANUAL` (what the submit lane
  writes) means the approved build ships only when a human presses Release
  in App Store Connect. `release=AFTER_APPROVAL` or `release=SCHEDULED` —
  which `asc.rb` flags as "goes live automatically" — means approval itself
  puts the build on the store, so the release moment belongs to Apple, not
  the user.

## Known failure modes

- **`Process completed with exit code 64`** in a build step — an invalid
  `xcodebuild` flag. Exit 64 is a usage error and xcodebuild dumps its help
  text. Read the flags, not the help.
- **Duplicate build number** — should be impossible given the run-number
  offset. If it happens, either someone uploaded manually or a run whose
  upload already succeeded was re-run — `run_number` does not change on a
  re-run, so it recomputes the same number (issue #137); check
  `asc.rb builds`.
- **The submit lane fails while the upload succeeded** — the build is safely in
  TestFlight. Fix the lane and push: the next run re-decides from App Store
  Connect state, so an unsubmitted version submits by itself. Re-running the
  failed run does **not** work: `run_number` is stable across re-runs, so the
  re-run recomputes the same build number and Apple refuses the upload as a
  duplicate — the next push gets a fresh number and re-decides submission
  (issue #137).
- **A run fails *before* the Submit step** (tests, archive, signing, upload) —
  nothing was submitted, and nothing is lost: fix the failure and push. The
  next run asks App Store Connect and submits the still-unsubmitted version.
  This is the recovery the old version-diff gate made impossible, when any
  push after the bump logged "Version unchanged" and shipped TestFlight only
  (issue #89).
- **The gate answers `REVIEW_IN_FLIGHT`** — normal while any version is in
  review: the run ships TestFlight only and stays green. Nothing to fix;
  wait for Apple, or remove the submission in App Store Connect first.
- **The gate reports a closed version train** (issue #119) — the pubspec
  version is approved, on sale, removed, or replaced. Apple refuses new
  builds for that train, so the run skips build, sign, export, and upload,
  and stays green with a `::warning::`. Nothing was lost — nothing can ship
  on this train again. Tell the user plainly: the next release needs a
  version bump, and the push after the bump builds, uploads, and submits by
  itself.
- **The gate answers `REVIEW_STUCK`** (issue #102) — a submission sits in
  `UNRESOLVED_ISSUES` (the aftermath of a rejection) or `READY_FOR_REVIEW`
  (never confirmed). No review is running, but no new submission may be
  created either, so the run ships TestFlight only with a `::warning::`
  annotation and stays green. Tell the user plainly: the version bump did
  not submit and cannot, until someone resolves the rejection or removes
  the submission in App Store Connect — then the next push submits by
  itself.
- **The state query itself fails** (`ruby tools/asc_version_state.rb` exits
  non-zero) — the run fails loudly instead of guessing TestFlight-only.
  Read the log: an HTTP code means an App Store Connect outage (a re-run
  fixes it), while "returned an empty list" or a page-limit message means
  the answer came back broken (wrong app, wrong key role, API change) and
  needs a human looking at `asc.rb version` before trusting the gate again
  (issue #93).
- **Signing failure in CI** — the distribution certificate expires
  **2027-08-23**. Renewal means regenerating `IOS_DIST_CERT_P12_BASE64` and
  `IOS_PROVISION_PROFILE_BASE64`. See CLAUDE.md.

## Force a submission without a version bump

Rarely needed now that every push re-decides from App Store Connect state,
but it still covers "Apple has the version but I want it submitted anyway":

```bash
gh workflow run ios-release.yml --repo wjdavis5/taxiGame -f submit_for_review=true
```

The ticked box submits regardless of what state Apple reports, so check
`asc.rb version` first: if the version is already `WAITING_FOR_REVIEW` or
later, this only crashes into Apple's duplicate-submission rejection. If
the version's train is closed (approved or on sale), the dispatch still
builds and tries the upload — `altool` refuses it and the run goes red.
The box forces a submission attempt; it cannot force Apple to accept a
build for a closed train. Bump the version instead.

## Manual fallback

Use only when CI is broken and a release cannot wait. Full commands are in
CLAUDE.md under *Publishing → Manual*. The essentials:

```bash
cd taxi_game
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/ios/archive/Runner.xcarchive archive -allowProvisioningUpdates
open build/ios/archive/Runner.xcarchive   # then Distribute App in Organizer
```

Never pass signing settings to `xcodebuild archive` — they apply to every
target and CocoaPods/SPM targets reject a provisioning profile.
