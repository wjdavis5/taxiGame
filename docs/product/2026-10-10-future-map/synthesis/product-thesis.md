# Cab Hustle product thesis

## Identity

> Cab Hustle is the one-thumb taxi score chase where every dropoff asks you to bank the shift or risk it on one more fare, and every day gives each player the same city course to master against a personal ghost.

The identity joins the two mechanics no reviewed competitor combines. Endless asks the player to cash out or keep risking a live score. Daily pins the course to the local date and lets the player race a stored best trace without a server. Evidence appears in `review/product-audit.md` section 2.2 items 6-7, section 2.4, and `review/competitors.md` section 3.

## Product pillars

### Every dropoff is a wager

**What it is.** A dropoff creates a five-second choice. Banking converts the at-risk chain score to coins and ends the shift. Pushing raises the next multiplier. A third crash forfeits the score that remains at risk.

**Evidence.** The prompt appears after every endless dropoff, defaults to push, and names the amount at risk. The first prompt freezes the road so the player can read it. Three lives and the final forfeit give the choice a real cost. Evidence appears in `review/product-audit.md` section 2.2 items 4-7 and `review/uniqueness-and-submission.md` section 1.2.

**What changes for the player.** The wager becomes the center of the HUD, feedback, summaries, missions, and store page. The player always knows what is safe, what is at risk, and what the next push can earn.

### Skill means serving fares under pressure

**What it is.** Cab Hustle rewards timely dropoffs, close passes, fare selection, and risk carried for a passenger. Traffic is not the theme by itself. Traffic creates choices inside the taxi job.

**Evidence.** Four fare kinds change payout, time, chain gain, and dropoff geometry. Close calls pay 15 points times the live multiplier, but the mechanic has no lesson, achievement, lifetime total, or menu explanation. Crazy Taxi and Taxi Drift Mania show why a taxi game needs fare or tip rewards tied to skill rather than a generic survival score. Evidence appears in `review/product-audit.md` sections 1.5 and 3.4, `review/uniqueness-and-submission.md` sections 1.3 and 1.5, and `review/competitors.md` sections 3 item 10 and 4 item 2.

**What changes for the player.** Every scored action gets a name and a readable consequence. A tutorial rung teaches close calls. Dropoffs explain on-time, late, chain, and tip outcomes. The player learns how to improve without opening a help page.

### The Daily is a personal rivalry on a shared road

**What it is.** The local date creates the same deterministic course on every device. One scored attempt settles the day. The player can then race the best local trace on that course.

**Evidence.** The Daily already has one attempt, local history, a ghost, a live gap readout, and a share card. It has no current-streak display or daily-specific payout. The first menu visit sells the shared course but not the ghost payoff. Evidence appears in `review/product-audit.md` section 2.4, `review/progression-retention.md` sections 4 and 7 item 1, and `review/uniqueness-and-submission.md` section 1.1.

**What changes for the player.** The menu promises the ghost before the first attempt. A visible streak and a specific local reward make tomorrow matter. The Daily remains fully offline and never pretends that the local ghost is another player.

### Every cab creates a different mastery problem

**What it is.** Vehicles are sidegrades with different speed, acceleration, steering, and body size. Missions and records ask the player to master those differences instead of buying one dominant upgrade.

**Evidence.** Seven vehicles ship with live handling differences, and tests enforce that no vehicle dominates every axis. The current garage has no per-cab mastery, no repeatable sink, and only three collection achievements. Evidence appears in `review/product-audit.md` sections 1.2 and 2.3, and `review/progression-retention.md` sections 5 and 7 item 2.

**What changes for the player.** Each cab supports a distinct route strategy and mastery track. The garage grows only when new vehicles have original art and a felt handling purpose. Price alone never defines progression.

### The game looks and responds like Cab Hustle

**What it is.** A custom city, custom hero cab, clear one-thumb controls, and event-specific sound and haptics make the game recognizable before the player reads its title.

**Evidence.** The current first screen uses a repeated blue Material gradient, stock icons, and standard buttons. The default cab comes from a CC0 pack. Entering play can show a blank dark screen, Level 1 places its only pickup at the edge of the reachable road, and steering and braking read as step functions in code. Several core events have no feedback of their own. Evidence appears in `review/uniqueness-and-submission.md` sections 1.6 and 3 items 1-2, and `review/first-session-and-feel.md` sections 1.3, 1.4, 2.2, and 3.

**What changes for the player.** The first tap leads through a branded transition into a visible cab and a reachable first fare. Touch mistakes produce guidance. Banking, pushing, lateness, close calls, and wrecks each have a distinct response.

## Double down on the parts only Cab Hustle owns

- Keep bank-or-push at every dropoff and keep the third crash final. The final loss makes earlier banking choices meaningful. A revive or insurance prompt would weaken the game's own wager and imitate the free-to-play failure patterns in Drift Boss, Traffic Rider, and Moto Rider GO. Evidence appears in `review/product-audit.md` section 2.2 and `review/competitors.md` sections 2 item 2 and 3 item 4.
- Build around close calls, fare types, and passenger outcomes. These systems already share one chain economy, but the product does not teach why they matter. Evidence appears in `review/product-audit.md` sections 1.5 and 3.3-3.4, and `review/uniqueness-and-submission.md` section 1.3.
- Make the local Daily, ghost, history, and share card the return loop. This is the strongest complete retention loop in the shipped game and has no server dependency. Evidence appears in `review/progression-retention.md` sections 6 and 7 item 1.
- Preserve handling sidegrades. The no-dominant-car rule is a stronger basis for mastery than a linear upgrade tree. Evidence appears in `review/product-audit.md` section 1.2 and the verified `test/vehicle_handling_test.dart` result in section 0.3.
- Use the deterministic systems and simulator as development tools. Pure course, environment, collision, score, and ghost systems make new local modes and repeatable tests cheaper than they are in most games. Evidence appears in `review/capability-and-risks.md` sections 1.1-1.3.

## Cut or refuse the parts that blur the product

- Refuse generic highway-racer language and screenshots. The crowded category already contains name and copy clones. Cab Hustle must present as a taxi wager game, not another endless traffic game. Evidence appears in `review/competitors.md` sections 1.10 and 6.5.
- Remove or rewrite every unsupported originality claim. The current response says the vehicle art is original while the license inventory and Credits name Kenney. Honest provenance is mandatory. Evidence appears in `review/uniqueness-and-submission.md` section 2.1.
- Refuse cosmetic-only resubmission work. Apple guidance and practitioner evidence say that a rename, recolor, or rushed resubmit does not establish uniqueness. Evidence appears in `review/competitors.md` section 6.4.
- Refuse global leaderboards, multiplayer, cloud saves, analytics, remote configuration, and server events. They conflict with the product's no-network claim. Local records, deterministic dates, share cards, and a personal ghost are the substitutes. Evidence appears in `review/competitors.md` section 5 and `review/capability-and-risks.md` section 2.1.
- Do not build on `totalGems`. It is a dead saved field with no source or sink. A second currency would add complexity without adding play. Evidence appears in `review/progression-retention.md` sections 2.1 and 7 item 2.
- Do not lengthen the ten-rung tutorial to hide every new rule. Repurpose a current rung for close calls, then move advanced objectives into the post-tutorial City License. The ladder is already a one-way ten-level path, and no measured level-completion timing exists. Evidence appears in `review/product-audit.md` sections 1.1 and 2.1, and `review/product-audit.md` section 5.
- Defer shareable video. The score-card path already gives the game a local social artifact. Video adds a new native encoder and recording system with no current test seam. Evidence appears in `review/capability-and-risks.md` section 1.6.

## The fun ladder

The moments below are product targets. The reviews contain no human first-session timing or retention data, so none is presented as observed behavior. Evidence for that limit appears in `review/product-audit.md` section 5 and `review/first-session-and-feel.md` under Unverified.

| Moment | What must be fun | Grounding and decision |
|---|---|---|
| Minute one | One tap starts play. The cab is visible, moves on the first valid touch, gives feedback for a touch in the dead upper half, and reaches an obvious first pickup. Pickup and dropoff feel rewarding. | The menu already reaches play in one tap, but the load window is blank, the first hint disappears after one low touch, and the Level 1 pickup is reachable only near the far road edge. Fix those before adding content. Evidence appears in `review/first-session-and-feel.md` sections 1.2-1.4 and friction findings 2, 4, 8, and 9. |
| Minute ten | The player can explain on-time versus late, make a close call on purpose, read the live amount at risk, and choose bank or push for a reason. The first loss creates an immediate desire to retry rather than confusion. | A simulated new-driver shift has a median driven time of 3.9 minutes, and the median profile has 5.4 minutes. Bank-or-push can therefore create repeated decisions inside an early session, but close calls and late settlement are under-taught. Evidence appears in `review/product-audit.md` section 0.2 and `review/first-session-and-feel.md` friction findings 11 and 14. |
| Shift one hundred | The player returns for mastery rather than a remaining price. The City License, per-cab mastery, Daily streak, ghost improvement, records, and original districts create goals that coins cannot finish. | The modeled full-garage range is about 15 shifts near the brink, 42-53 shifts on the pricing assumption, or 46-86 shifts on fare-only floors. The current coin rail is therefore exhausted before shift 100 under every modeled range. Evidence appears in `review/progression-retention.md` section 3.3 and section 7 item 2. |

## Uniqueness and submission strategy

### Earn a new review instead of asking for one

1. Make the unique concept obvious in the first 30 seconds. The fresh-save menu must name the bank-or-push rule, three-strike consequence, shared Daily course, and ghost payoff. The first tutorial session must teach one non-generic scoring skill. Practitioner evidence summarized by the competitor slice says visible functional differentiation must appear within the first 30 seconds. Evidence appears in `review/competitors.md` sections 6.3-6.5 and `review/uniqueness-and-submission.md` sections 1.3 and 2.4.
2. Replace the strongest clone-read signals. The submitted first impression needs a custom Cab Hustle shell and project-original hero vehicle art. The default cab and stock Material shell currently work against the originality argument. Evidence appears in `review/uniqueness-and-submission.md` section 3 items 1-2.
3. Tell the truth about provenance. The response, review notes, What's New text, Credits, and license inventory must agree about original code, generated assets, authored levels, the world renderer, and retained CC0 assets. Evidence appears in `review/uniqueness-and-submission.md` sections 2.1 and 2.5.
4. Show the proof Apple will inspect. The first two App Store images should show a live ghost race and a live bank-or-push choice. The capture tool must create those exact states at 1320 by 2868 with no alpha. It cannot do so today. Evidence appears in `review/uniqueness-and-submission.md` section 2.2 and `CLAUDE.md` lines 44-82.
5. Give the reviewer a short route through the build. Review notes should name the unique mechanics, the exact taps that reach them, and the local-only architecture. Annotated screenshots should match that route. Evidence appears in `review/competitors.md` section 6.4 and `review/uniqueness-and-submission.md` section 4.
6. Let the operator complete the account actions in #212 only after the product proof and truthful package are ready. The operator must update the hand-maintained listing, clear or replace the rejected submission, reply in Resolution Center, and resubmit. The team must verify the resulting App Store state manually while #94 remains open. Evidence appears in `review/capability-and-risks.md` section 2.2 under issues #212 and #94.

No product change guarantees acceptance. Apple's exact reasoning and the outcome of a new review remain unknown until the operator resubmits. Evidence appears in `review/uniqueness-and-submission.md` under Unverified and `review/capability-and-risks.md` under Unverified.

### Meet a concrete genre bar

The category is large and mature. Traffic Racer reports 470 million Android installs, Traffic Rider reports more than 500 million, and Moto Rider GO reports more than 100 million. The iOS quality anchors in the scan sit at 4.6 stars from 2.1 thousand, 48 thousand, and 88 thousand ratings. Evidence appears in `review/competitors.md` section 2 items 9-10.

| Bar | Cab Hustle standard | Evidence |
|---|---|---|
| Immediate input | Start the first run in one tap and keep gameplay at no more than two control affordances. Every ignored touch needs a cue. | `review/competitors.md` section 4 item 1 and `review/first-session-and-feel.md` section 2.2 item 3. |
| Readable scoring | Ship at least three named bonus outcomes with live feedback and at least one taxi-native fare or tip outcome. | `review/competitors.md` section 4 item 2. |
| Visible risk | Keep the amount that can be lost on the HUD and ask for a bank-or-push choice at every dropoff. | `review/competitors.md` section 4 item 3 and `review/uniqueness-and-submission.md` section 1.2. |
| Fleet depth | Grow from seven to at least ten handling-distinct, original vehicles. Preserve the rule that no cab dominates every axis and give each cab a mastery reason to exist. | `review/competitors.md` section 4 item 4 and `review/product-audit.md` section 1.2. |
| Daily value | Pair the shared course and local ghost with a visible streak, a specific payout, and records that survive a missed day. | `review/competitors.md` section 4 item 5 and `review/progression-retention.md` section 6. |
| Structured breadth | Add a post-tutorial objective mode. Do not try to match Traffic Rider's 90-plus missions by volume. Make each Cab Hustle objective teach a taxi-specific skill or a vehicle tradeoff. | `review/competitors.md` sections 1.2, 3 item 1, and 4 item 6. |
| Screenshot identity | A screenshot without the title must still read as Cab Hustle through the cab, city, HUD, and bank decision. | `review/competitors.md` sections 2 item 7 and 4 item 7. |
| Public quality | Treat 4.6 stars at meaningful rating volume as the post-launch quality target, not a prelaunch acceptance test. Plan substantive updates more than once a year. | `review/competitors.md` section 4 item 8. |
| Honest premium position | Keep play offline, with no ads and no in-app purchases. All ten scanned games use ads, in-app purchases, or both, so this is a real market distinction. | `review/competitors.md` sections 2 item 10 and 4 item 9. |

Cab Hustle should not chase Traffic Racer's 40-plus cars or Traffic Rider's 90-plus missions through filler. It should beat them on the clarity of its wager, the taxi-specific scoring, the local Daily ghost, and the absence of monetization interruptions. Evidence for the competitor counts appears in `review/competitors.md` sections 1.1-1.2.

## Decisions and parked tensions

| Tension | Decision | Evidence |
|---|---|---|
| Tutorial runs never enter shift history | Keep tutorial records separate. Endless and Daily stats should continue to describe ended shifts. Add explicit tutorial and City License progress instead of mixing incompatible runs into medians. | `review/product-audit.md` section 2.5 and section 4 item 5. |
| Garage pacing has two unreconciled figures | Park every price change. The full garage can model as about 15, 42-53, or 46-86 shifts depending on banking behavior. Measure human bank timing before choosing a cadence. | `review/progression-retention.md` sections 3.3-3.4. |
| The simulator is optimistic | Keep it as a regression guard, not player truth. It omits fare detours and cannot model real bank choices. Calibrate it against repeatable physical-device playtests. | `review/capability-and-risks.md` sections 1.6 and 2.3 item 3. |
| The close-call economy is invisible | Decide now. Repurpose one tutorial rung, explain the first close call, show its score path, and add lifetime mastery. | `review/uniqueness-and-submission.md` sections 1.3 and 2.3. |
| Entering play can show a blank screen | Decide now. Add a branded loading state and hold it until the cab and HUD are ready. | `review/first-session-and-feel.md` sections 1.3 and 4 finding 2. |
| The game has a stock first glance | Decide now. Replace the stock shell and hero vehicle art before resubmission. Honest copy alone is not enough after a design-spam rejection. | `review/uniqueness-and-submission.md` section 3 items 1-2 and `review/competitors.md` section 6.4. |
| Steering and braking look binary in code | Park exact constants until a physical-device comparison. The code proves the response shape, not how it feels in a hand. | `review/first-session-and-feel.md` section 2.2 and its Unverified section. |
| Level coin pops imply money that is not yet credited | Decide now. Make the animation and HUD match the actual completion-time payout. | `review/first-session-and-feel.md` section 3 and friction finding 12. |
| A revive could add a failure decision | Refuse it. The final forfeit protects the bank-or-push identity. Improve the loss presentation and retry speed instead. | `review/competitors.md` section 3 item 4 and `review/progression-retention.md` section 7 item 2. |
| The first Daily has no ghost yet | Keep the first attempt honest. Promise the ghost payoff on the menu, create it after the settled run, and never show a fake opponent. | `review/uniqueness-and-submission.md` section 1.1. |
| A device-only crash remains unexplained | Keep #40 as a release-readiness gate. The operator must provide a fresh crash report, an issuer ID, or a screenshot with timing and build number before implementation starts on that defect. | `review/capability-and-risks.md` section 2.2 under issue #40. |
| The submission gate can report green without a submission | Keep #94 as a shipping gate and verify App Store state manually until it closes. Do not create a duplicate roadmap issue. | `review/capability-and-risks.md` section 2.2 under issue #94. |
| Frame costs are static findings rather than measurements | Let #250-#257 finish. New traffic density, weather, and effects depend on a physical-device profile after that batch. | `review/capability-and-risks.md` section 2.2 under the frame hygiene batch. |
