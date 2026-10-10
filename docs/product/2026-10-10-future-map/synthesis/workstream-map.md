# Cab Hustle workstream map

## Coverage and issue flags

The map keeps all eight coverage areas from `frame.md`. Each area has its own workstream because the evidence gives each one a different gate. First-session feel also appears in the identity and polish workstreams, but the ownership remains explicit.

| Workstream | Coverage area |
|---|---|
| 1. Prove an original product | Uniqueness and submission |
| 2. Win the first minute | First-session hook |
| 3. Make the wager and score readable | Core-loop fun |
| 4. Tune against human truth | Difficulty and fairness |
| 5. Build a taxi city worth mastering | Content variety |
| 6. Give every return a goal | Progression and retention |
| 7. Make every outcome feel authored | Feel and polish |
| 8. Make device truth the release truth | Capability and stability |

The flags have the following meanings.

- `[FS]` marks the first-session critical path.
- `[RS]` marks the 4.3(a) resubmission critical path.
- `[OPERATOR]` marks work that needs App Store Connect access or a physical iPhone.
- `P0` means do now, `P1` means next, and `P2` means later.
- `S`, `M`, and `L` are relative delivery sizes for roadmap ordering.

The map contains 28 issue candidates.

The following existing issues are dependencies, not new candidates.

- #212 owns the App Store Connect response, listing update, rejected-submission cleanup, and resubmission.
- #94 owns the release submit-gate defect.
- #40 owns the device-only crash and cannot move without an operator artifact.
- #250-#257 own the frame-hygiene batch already in flight.

## Workstream 1. Prove an original product

This workstream owns uniqueness and submission. It turns the shipped differentiators into first-glance product proof and removes claims the bundle contradicts.

### Correct the submission's originality claims `[RS]`

- **Acceptance.** The response, review notes, What's New text, Credits, and license inventory agree that Kenney vehicle assets are retained CC0 work and name only the code, authored levels, generated assets, and systems that are original to this project.
- **Size.** S
- **Priority.** P0
- **Evidence.** `review/uniqueness-and-submission.md` finding 2.1 and finding 3.1. The conflicting files are `docs/app-review/2026-10-08-4.3a-response.md` lines 20-22, `taxi_game/fastlane/review_notes.txt` lines 3-5, and `taxi_game/assets/licenses/LICENSES.txt` lines 52-99.

### Capture the bank and ghost storefront states `[RS]`

- **Acceptance.** `tool/screenshot_entry.dart` has deterministic bank and ghost targets, every documented capture command names a real script, and both final images verify as 1320 by 2868 with no alpha.
- **Size.** M
- **Priority.** P0
- **Evidence.** `review/uniqueness-and-submission.md` finding 2.2. The current target list appears in `taxi_game/tool/screenshot_entry.dart` lines 111-117. The image requirements appear in `CLAUDE.md` lines 44-82.

### Author an original hero cab, stage the traffic fleet after `[RS]`

- **Acceptance.** Stage one, for the submitted build: the default hero cab uses project-original art produced by a deterministic in-repo pipeline, the asset inventory records provenance, and the two flagship screenshot states use it. Stage two, tracked separately: every traffic vehicle sprite migrates to the same standard.
- **Size.** L. **Priority.** P0 for stage one, P1 for stage two.
- **Evidence.** `review/uniqueness-and-submission.md` finding 3.1 identifies fifteen Kenney vehicle sprites and the stock default cab as the strongest remaining clone-read signal. The current pipeline only recolors and pads the Kenney pack, so stage one is art production, not a code change, and it needs an art owner.

### Brand the first screen and state the flagship rules `[FS]` `[RS]`

- **Acceptance.** A fresh save opens on a custom Cab Hustle wordmark and control style, Endless names the three-crash bank-or-push rule, and Daily names both the shared course and the local ghost payoff.
- **Size.** M
- **Priority.** P0
- **Evidence.** `review/uniqueness-and-submission.md` findings 1.6, 2.4, and 3.2. `review/competitors.md` section 2 item 7 says presentation identity must be visible in a screenshot.

**Sequencing.** Correct the claims first because #212 must not send the current text. The visual shell and the hero cab can proceed together. Build screenshot states in parallel, but take the final images only after the visual work lands. The traffic fleet migrates after the submission. The operator then applies the listing, sends the response, clears or replaces the rejected submission, and resubmits through #212. The operator must verify the resulting App Store state manually while #94 remains open. The category candidates here besides the fleet are on the resubmission critical path.

## Workstream 2. Win the first minute

This workstream owns the first-session hook. It removes the blank transition, the silent touch trap, and the first fare's edge-only geometry before it changes the amount of content.

### Show a branded transition into every run `[FS]`

- **Acceptance.** `GameWidget` shows an authored loading state from navigation until the road, cab, and HUD are ready, and a widget test fails on either a blank `#1A1A1A` frame or a visible road without the cab.
- **Size.** S
- **Priority.** P0
- **Evidence.** `review/first-session-and-feel.md` finding 1.3 and friction findings 2-3. The missing `loadingBuilder` is in `taxi_game/lib/ui/screens/game_screen.dart` lines 145-153.

### Rebuild First Ride around a reachable first fare `[FS]`

- **Acceptance.** A natural straight initial drive can encounter the first pickup, the road teaches curb alignment before failure, and tests pin both the pickup geometry and the corrective miss message.
- **Size.** M
- **Priority.** P0
- **Evidence.** `review/first-session-and-feel.md` finding 1.4 and friction finding 8 show that the pickup intersects only the outer 20 pixels of the cab's reachable range.

### Keep the control lesson until the player demonstrates it `[FS]`

- **Acceptance.** The hint persists until the player has accelerated and steered, an upper-half touch produces an immediate cue to move the thumb lower, and one low touch no longer dismisses the lesson forever.
- **Size.** M
- **Priority.** P0
- **Evidence.** `review/first-session-and-feel.md` finding 1.4 and control finding 2.2 item 3. The current dismissal happens on the first lower-half landing in `taxi_game/lib/game/taxi_game.dart` lines 548-551.

### Tune one-thumb handling on a physical iPhone `[FS]` `[OPERATOR]`

- **Acceptance.** The operator compares the current response with a weighted-steering and coasting variant on the same TestFlight route, records the choice, and the selected constants and behavior tests agree.
- **Size.** M
- **Priority.** P0
- **Evidence.** `review/first-session-and-feel.md` control findings 2.2 items 1-2 show direct lateral velocity, full lock after a short glide, and release-to-stop in 0.25 seconds. Its Unverified section says lived feel needs a device session.

**Sequencing.** The loading state and First Ride geometry can land first. The revised lesson should use the final first-fare geometry. Handling constants wait for the operator's device comparison and should not be chosen from static analysis. The first-session critical path closes only after one cold-start physical-device pass covers all four candidates.

## Workstream 3. Make the wager and score readable

This workstream owns core-loop fun. It teaches the hidden skill economy, explains fare outcomes, and makes the taxi job affect scoring.

### Turn a tutorial rung into the close-call lesson `[FS]`

- **Acceptance.** One of the existing ten rungs requires and explains a qualifying close call, the first award says that speed and proximity feed the at-risk chain, and tests prove that the lesson can be completed.
- **Size.** M
- **Priority.** P0
- **Evidence.** `review/uniqueness-and-submission.md` findings 1.3 and 2.3 show that close calls have no lesson despite paying 15 points times the multiplier. `review/product-audit.md` section 1.1 fixes the current ladder at ten rungs.

### Explain every fare settlement

- **Acceptance.** Each dropoff names on-time or late status, the fare value, the multiplier effect, any skill bonus, and the resulting at-risk total, and the live game no longer discards `FareSettlement`.
- **Size.** M
- **Priority.** P0
- **Evidence.** `review/first-session-and-feel.md` juice findings for late delivery and chain break show identical or absent feedback. The ignored settlements appear in `taxi_game/lib/game/taxi_game.dart` lines 989 and 1043.

### Reward passenger thrill as a taxi-native tip

- **Acceptance.** Named skill events completed while a passenger is aboard produce a deterministic and capped tip at dropoff, and the simulator, run summary, and pure scoring tests include the same rule.
- **Size.** M
- **Priority.** P1
- **Evidence.** `review/competitors.md` section 3 item 10 and section 4 item 2 identify fare or tip rewards tied to skilled driving as the missing taxi-native scoring bar. `review/capability-and-risks.md` section 1.1 shows that the scoring systems are pure and simulator-ready.

**Sequencing.** Teach close calls before adding another score source. Land settlement breakdowns next so the player can read the current economy. Add tips only after those surfaces exist, then rerun the economy workstream because tips change the wallet. Do not add a revive or insurance branch. The final crash remains final.

## Workstream 4. Tune against human truth

This workstream owns difficulty and fairness. It fixes misleading output, records physical play in a privacy-consistent form, and delays economy changes until banking behavior is known.

### Make the simulator report honest statistics

- **Acceptance.** The economy output labels means as means, prints actual median distance and driven time for each skill profile, and keeps the 101-seed command and expected fields under test.
- **Size.** S
- **Priority.** P0
- **Evidence.** `review/product-audit.md` section 0.1 and cross-checks 1-2 show that the printed "median shift" distance is a mean and that the run-length suite prints no per-profile table.

### Calibrate the simulator with physical play `[OPERATOR]`

- **Acceptance.** A repeatable local playtest export records seed, vehicle, distance, driven time, fares, declines, crashes, and bank timing, and a report compares each captured run with the same-seed simulator before changing its assumptions.
- **Size.** M
- **Priority.** P0
- **Evidence.** `review/capability-and-risks.md` risk 2.3 item 3 says the simulator omits fare detours and has no human ground truth. `review/progression-retention.md` section 8 says the real wallet and bank behavior are unknown.

### Reprice the garage after banking behavior is measured

- **Acceptance.** A written target cadence, the physical-play comparison, and a fresh 101-seed economy table support one price ladder, and prices, comments, and tests all state the same assumptions.
- **Size.** M
- **Priority.** P1
- **Evidence.** `review/progression-retention.md` findings 3.3-3.4 show full-garage estimates of about 15, 42-53, or 46-86 shifts under different bank assumptions. `review/product-audit.md` cross-check 4 identifies the stale catalog rationale.

**Sequencing.** Correct reporting first. Add the local export and run the operator playtest second. Reprice only after the comparison exists. Passenger tips from workstream 3 must enter the simulator before the final price decision. Simulator bands remain regression guards rather than claims about players.

## Workstream 5. Build a taxi city worth mastering

This workstream owns content variety. It extends existing deterministic systems instead of adding disconnected modes or server events.

### Build a post-tutorial City License board

- **Acceptance.** A local challenge board offers replayable named objectives across banking, close calls, fare kinds, weather, and vehicle tradeoffs, persists completion, and contains no unavailable or placeholder entry.
- **Size.** L
- **Priority.** P1
- **Evidence.** `review/competitors.md` section 7 item 1 and section 4 item 6 set a structured objective mode as the genre bar. `review/product-audit.md` section 2.5 shows that the current ladder is linear and the garage unlocks no content.

### Turn fare kinds into readable passenger contracts

- **Acceptance.** VIP, long-haul, and awkward offers state their payout and cost before accept or skip, the first encounter gives a short playable explanation, and settled records preserve accepted and declined counts by fare kind.
- **Size.** M
- **Priority.** P1
- **Evidence.** `review/product-audit.md` section 1.5 defines the four fare kinds and their 70, 10, 10, and 10 percent shares. `review/uniqueness-and-submission.md` finding 1.5 says the decision exists but is never explained beyond the offer bar.

### Turn the three road profiles into recognizable districts

- **Acceptance.** Standard, narrow, and avenue roads each gain a distinct district identity through road silhouette, curbside landmarks, palette, and traffic behavior while seed determinism and simulator parity remain intact.
- **Size.** L
- **Priority.** P1
- **Evidence.** `review/product-audit.md` section 1.4 counts three road profiles but no named districts. `review/competitors.md` sections 2 item 7 and 4 item 7 require a screenshot-proven identity.

### Add an offline weekly gauntlet

- **Acceptance.** A local week key chooses a deterministic objective and modifier, stores a best result, explains that the device calendar controls the event, and uses no network, account, or leaderboard.
- **Size.** M
- **Priority.** P2
- **Evidence.** `review/progression-retention.md` section 6 says a date-derived weekly challenge is fully buildable on-device. `review/capability-and-risks.md` section 1.2 says the date hash is frozen and local-calendar based.

**Sequencing.** Fare contracts establish the objective vocabulary. The City License can then reuse it. Determinism guards from workstream 8 must land before districts or weekly modifiers change generator behavior. The weekly gauntlet follows the Daily streak work so both calendar loops use one tested date model.

## Workstream 6. Give every return a goal

This workstream owns progression and retention. It makes existing records visible, gives the Daily a payoff, and extends mastery beyond the finite garage wallet.

### Make the Daily streak visible and rewarding

- **Acceptance.** The menu and Daily screen show current and best streaks, one declared reward can settle once per date, and calendar tests cover missed days and daylight-saving transitions.
- **Size.** M
- **Priority.** P1
- **Evidence.** `review/progression-retention.md` findings 6 and 7.1 show that only the longest streak feeds hidden achievements and no current streak or payout exists. `review/capability-and-risks.md` section 1.3 identifies the existing calendar test seam.

### Surface the next goal and the shift stats

- **Acceptance.** The menu and run summary show the next reachable car, achievement, or City License objective, and the full shift-stats screen is reachable without entering Settings.
- **Size.** M
- **Priority.** P1
- **Evidence.** `review/progression-retention.md` findings 6 and 7.3 show that next-goal copy appears only after a failed purchase and that the stats wall is buried under Settings.

### Add mastery records for the systems the game celebrates

- **Acceptance.** Records and achievements cover lifetime close calls, score tiers, nonconsecutive Daily participation, and lifetime driving volume, with save migration, visible progress, and unlock banners.
- **Size.** M
- **Priority.** P1
- **Evidence.** `review/progression-retention.md` section 5 lists each missing mastery track and identifies the stored counters already available for several of them.

### Grow an original fleet with per-cab mastery

- **Acceptance.** The fleet reaches at least ten project-original vehicles, every new handling profile preserves the no-dominant-car invariant, and each cab has a local mastery record with an earned visual reward and no in-app purchase.
- **Size.** L
- **Priority.** P2
- **Evidence.** `review/competitors.md` section 4 item 4 sets a target around ten or more vehicles. `review/product-audit.md` section 1.2 verifies seven current sidegrades. `review/progression-retention.md` section 5 identifies the lack of per-vehicle mastery.

**Sequencing.** Surface current goals before adding more of them. Daily streak and mastery records can proceed after their save migrations are designed together. Fleet expansion waits for original-art production, calibrated garage prices, and the City License objectives that give each new cab a purpose. Do not revive the unused gems field as a second currency.

## Workstream 7. Make every outcome feel authored

This workstream owns feel and polish. It fills specific feedback holes rather than adding unmeasured visual density.

### Give silent outcomes distinct feedback

- **Acceptance.** Bank, push, chain break, late delivery, scrape, Daily settlement, pause, and summary actions each have a distinct visual, sound, or haptic cue that respects the existing settings and passes a physical-device checklist.
- **Size.** M
- **Priority.** P0
- **Evidence.** `review/first-session-and-feel.md` section 3 under "Events with no feedback at all" enumerates the missing feedback for each named event.

### Make level coin feedback tell the truth

- **Acceptance.** Coin pops and the HUD claim value only when the wallet receives it, and the completion panel reconciles the visible level payout exactly with the credited amount.
- **Size.** S
- **Priority.** P1
- **Evidence.** `review/first-session-and-feel.md` section 3 says level dropoffs show coin pops while the wallet changes only at completion. Friction finding 12 calls out the mismatch.

### Give the city an original dispatcher personality

- **Acceptance.** Original dispatcher callouts react to pickup, urgency, close calls, banking, and wrecks, avoid competitor phrases, respect sound settings, and appear in the audio license inventory.
- **Size.** M
- **Priority.** P1
- **Evidence.** `review/competitors.md` sections 1.7 and 2 item 7 show that Dashy Crashy's announcer makes personality part of the product. `review/first-session-and-feel.md` section 3 shows Cab Hustle's current event-audio gaps.

**Sequencing.** Fix the direct event feedback first. Correct level coin truth independently. Add dispatcher callouts only after score and risk terms are final so the voice layer teaches stable rules. More particles, traffic, or full-screen effects wait for the frame profile in workstream 8.

## Workstream 8. Make device truth the release truth

This workstream owns capability and stability. It closes the gap between a large headless suite and the iPhone behavior that players and App Review see.

### Establish a physical-device release acceptance loop `[FS]` `[RS]` `[OPERATOR]`

- **Acceptance.** Every release candidate has a named iPhone and build artifact covering cold launch, tutorial, Endless, Daily, ghost, bank, wreck, and garage, with diagnostics, screenshots, and either a crash log or an explicit no-crash result.
- **Size.** M
- **Priority.** P0
- **Evidence.** `review/capability-and-risks.md` risks 2.2 under issue #40 and 2.3 items 2-3 show that green headless tests do not settle device crashes or feel. `review/first-session-and-feel.md` under Unverified lists the device-only claims still open.

### Profile the game after the frame-hygiene batch `[OPERATOR]`

- **Acceptance.** After #250-#257, the operator captures frame-time and allocation traces on the oldest supported available iPhone in rain, night, and dense traffic, then records a regression budget before any density or effects increase.
- **Size.** M
- **Priority.** P1
- **Evidence.** `review/capability-and-risks.md` section 2.2 under #250-#257 and risk 2.3 item 4 say the costs are static findings with no device profile and grow with scene density.

### Protect deterministic courses as content grows

- **Acceptance.** Golden seeds pin course, environment, fare, and ghost behavior, intentional generator changes use explicit versioning, and `DailyShift.seedForDateKey` remains unchanged.
- **Size.** M
- **Priority.** P1
- **Evidence.** `review/capability-and-risks.md` sections 1.1-1.2 say draw order is load-bearing and the Daily hash must never be improved. `review/product-audit.md` section 2.4 shows that Daily and ghost depend on exact course reproduction.

**Sequencing.** The operator artifact requested by #40 is the first stability gate. The physical acceptance loop then becomes the proof path for first-session, feel, and resubmission work. #250-#257 must finish before profiling sets a budget. Determinism guards must land before districts, weekly modifiers, or scoring changes touch course generation. #94 remains the separate release-state gate, and the operator must verify App Store Connect after any attempted submission until that issue closes.
