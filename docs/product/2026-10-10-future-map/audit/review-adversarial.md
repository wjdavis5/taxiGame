# Adversarial review of the 2026-10-10 Cab Hustle future map

Reviewer: second model family (adversarial pass). Date: 2026-10-10.
Inputs: tracker #290; issues #262-#289 (all 28 read in full); `docs/product/2026-10-10-future-map/` thesis,
workstream map, six reviews and `frame.md` (in `taxiGame-pm-docs` @ d10a70a); code read in
`C:\git\repos\taxiGame-pm` (branch `product/future-map-20261010` @ daab300, which equals review commit
c514609 + PR #260's three-file fix; `git log` confirms daab300's only parent is c514609).

Method: every cited file opened at the cited line range; numbers re-derived from code; issue bodies
compared line-by-line against `product-thesis.md`, `workstream-map.md` and the reviews. Read-only; no
GitHub writes.

---

## 1. Evidence audit (sampled 16 issues across all three milestones)

Verified clean:

- **#262** — `assets/licenses/LICENSES.txt:52` starts the Kenney Racing Pack vehicle section; 15 player+traffic
  sprites listed (`:324-345` in the file). Claim holds.
- **#263** — `taxi_game/tool/screenshot_entry.dart:111-117` is the `homeForShot` switch with exactly
  `game|garage|credits|settings|menu`; the game shot is default `GameScreen()` (ladder level 1). Claim holds.
  (Corollary finding M-3 below.)
- **#265** — `lib/ui/screens/game_screen.dart:145-153`: `GameWidget` has `errorBuilder` but no
  `loadingBuilder`; fallback color `0xFF1A1A1A` at `taxi_game.dart:554`. Claim holds.
- **#266** — `assets/levels/level_001.json:5-10` pickup `[315, 400]`; road is x100-300
  (`taxi_game.dart:492-493`), cab clamp x120-280 (`components/player_vehicle.dart:147-162`), so the pickup
  intersects only the outer 20 px and a centre-line drive misses. Claim holds (but path is wrong, see finding M-6).
- **#267** — `taxi_game.dart:548-551` is `onStickEngaged()` removing `controlHint` and writing
  `dismissControlHint()`; upper-half rejection at `components/virtual_stick.dart:180-181`. Claim holds.
- **#269** — `nearMissScore = 15` (`fare_chain.dart:104`), `awardNearMiss` multiplies by live multiplier
  (`:265-270`); no near-miss entry in `AchievementCatalog` (achievements.dart:104-223). Claim holds.
- **#270** — `taxi_game.dart:989` and `:1043` are both `fareChain.completeFare(...)` with the return value
  unused; `FareSettlement` is declared at `fare_chain.dart:7`. Claim holds.
- **#271** — `test/economy_simulation_test.dart:83` prints `${totalKm / runCount}` under the label
  "median shift" (line 62 accumulates the sum); `run_length_simulation_test.dart` has no `print(` at all.
  Claim holds.
- **#275/#289** — 7 catalog vehicles (`vehicle_catalog.dart:103-188`); 15 achievements
  (`achievements.dart:93` comment; catalog `:104-223`); no per-vehicle mastery anywhere in `lib/models`.
  Claims hold.
- **#279** — fare shares `vipShare=0.10, longHaulShare=0.10, awkwardShare=0.10` (`fare_type.dart:108-110`).
  Claim holds.
- **#281** — no streak field in `save_data.dart`; streak computed only from history (`achievements.dart:264-292`).
  Claim holds.
- **#287** — `DailyShift.seedForDateKey` exists and is the frozen hash (`daily_shift.dart:50-73`). Claim holds.
- **#288** — date-hash weekly build-out is on-device as the review states. Claim holds as an intent; no code exists yet.

Findings:

- **[major] M-1 — #262's P0 acceptance presumes an art capability the repo does not have.** The issue requires
  "project-original art produced by a deterministic in-repo pipeline" (only `tool/make_vehicle_sprites.py`
  exists, and per `LICENSES.txt:349-364` it *recolors/pads the Kenney pack*), while the uniqueness review
  (3.1) calls the fix "real art work, not a code change" and the tracker's own `needs-human` definition
  covers "an art decision" — yet #262 carries no `needs-human` label. Fix: add `needs-human`, name the art
  production path (drawn assets vs a new generator) and re-size before it sits on the resubmission path.
- **[minor] M-2 — two issues cite paths that do not resolve.** #266 cites
  `taxi_game/lib/game/player_vehicle.dart:157-162` and #268 cites the same plus
  `taxi_game/lib/game/systems/virtual_stick.dart:49-52`; the real paths are
  `lib/game/components/player_vehicle.dart` and `lib/game/components/virtual_stick.dart` (the line numbers
  are correct in the real files). Fix: correct the four pointers.
- **[minor] M-3 — #263's acceptance item 2 is already satisfied or vacuous.** "Every documented capture command
  names files that exist" referred to the missing `tool/capture_screenshots.sh` reference, which PR #260
  (daab300) already removed (`screenshot_entry.dart:12` now points at CLAUDE.md). Fix: drop or re-state the item.
- **[minor] M-4 — #277 inventts a "fourth figure".** The catalog comment it disputes
  (`vehicle_catalog.dart:69-81`: ~2,000 first-session, 2,300-3,000 competent coins/shift) is the *source* of
  the 42-53-shift band in the review (§3.3), not a separate fourth pacing figure; and the spread is 15 to 86
  (~5.7x) at its extremes, only ~3x against the bottom of the middle band. Fix: restate as "the catalog
  comment's wallet figures are one of the three bases and are stale against the current instrument."
- **[minor] M-5 — theses/reviews contain no false quotes I could find.** Spot-checked quotes from the thesis
  ("defaults to push", "the first prompt freezes the road", "seven vehicles with no dominant car",
  "15 points times the multiplier", "five-second choice") all resolve in code
  (`bank_prompt.dart:25-27,35,65-73`; `taxi_game.dart:1092-1104`; `vehicle_handling_test.dart` claims per
  product-audit §0.3; `fare_chain.dart:104,265-270`). No action.
- **[minor] M-6 — code worktree label drift.** The brief describes `taxiGame-pm` as "main @ c514609"; it is on
  `product/future-map-20261010` @ daab300 (c514609 + PR #260). Reviews were run at c514609, and the only
  delta is the 3-file PR #260 fix, so no review claim is invalidated — but the map's "done" claim rests on
  this unmerged branch (see Blocker B-2). Fix: state the tree/commit the map was validated against.

## 2. Coverage gaps

The eight areas are genuinely covered by the 28 issues; I found no blocker-level hole. The six reviews'
material findings all have an owner except the following.

- **[minor] C-1 — store What's New identity text has no issue.** Uniqueness review 2.5 asks the resubmission
  What's New to *name the modes* ("Daily Shift with a ghost...", "bank-or-push"); PR #260 only fixes
  provenance, and #264 covers the in-app menu. Fix: fold "What's New names the two modes" into #264 or #263.
- **[minor] C-2 — tutorial completion earns nothing (progression §5 last bullet).** No issue rewards or even
  acknowledges rung 10; #278's City License starts after the tutorial. Fix: add a completion record/reward to
  #278 or #283.
- **[minor] C-3 — no issue explains the garage bars.** Uniqueness 1.4: "no sentence anywhere says the bars
  change how the car drives." #289 and #282 don't add it. Fix: one line in #279/#282 scope (garage copy).
- **[minor] C-4 — launch latency (first-session friction 1) and accessibility (capability §1.6) are uncovered**
  by design. The reviews explicitly downgrade both ("launch latency, not confusion"; canvas a11y "a design
  project"), so I read these as accepted omissions, not gaps — but they are not recorded as accepted anywhere.
  Fix: add one "explicitly out of scope" line to the tracker.
- **[minor] C-5 — bank-panel crowding and short-phone menu scroll (friction 14-15) have no issue.** Both are
  reviewer-visible surface issues with existing evidence. Fix: fold into #273/#264 or accept explicitly.

## 3. Priority attacks

- **[blocker] B-1 — the resubmission set ships the sprites the map calls the strongest clone-read signal.**
  Workstream map, Workstream 1: "Replace the stock vehicle set with original art" is **P0** with acceptance
  "Every player **and traffic** vehicle sprite in the submitted build uses reproducible project-original source
  art... All four candidates are on the resubmission critical path." The tracker splits this into #262 (hero cab,
  P0) and #275 (traffic fleet, **P1/Next**, "After the hero cab"). Nothing in the tracker or the thesis records
  the descope. As shipped, the plan answers a 4.3(a) Design Spam rejection while keeping 15 CC0 pack sprites
  (uniqueness review 3.1). Fix: decide explicitly and make both documents agree — either move #275 into P0 and
  re-scope the milestone, or amend the map's P0 acceptance and state that Kenney traffic may ship.
- **[major] B-2 — the tracker reports the highest-risk submission fix as done while its PR is open.** #290:
  "Done in this run. The submission package's provenance claims were corrected... (PR #260)." PR #260 is
  `state: OPEN, mergedAt: null`; the fix exists only on `product/future-map-20261010`, and main still carries
  the false "original art" reply the map says "#212 must not send." Fix: mark it "proposed, pending merge" and
  gate #212 on the merge.
- **[major] B-3 — #271 and #272 are P0 in the "next submission" milestone but are not submission work.**
  The milestone contract is "Finish it before the app earns a new review" (#290). Simulator reporting (#271) is
  internal tooling and #272 (playtest calibration) feeds only garage pricing, which the map itself parks to
  P1 (#277) and calls "a regression guard, not player truth." Fix: move both to Next or rename the milestone.
- **[major] B-4 — #274's acceptance claims it will supply the #40 artifact; a passing device pass cannot.**
  #40's needs are a crash report, issuer ID, or crash reproduction artifact (capability §2.2); #274's
  acceptance allows "either a crash log or an explicit no-crash result" and then says "The first pass supplies
  the artifact #40 has been waiting for." The pinned tension in #290 says the operator must provide a *fresh
  crash report* first. Fix: drop that sentence or condition it on "if the crash reproduces during the pass."
- **[minor] B-5 — flag misuse: #274 carries `[FS]` (first-session critical path)** though it is release
  process, not first-session product. #285/S-2 aside, flags should drive routing; mislabeled [FS] work can be
  picked up under the wrong assumption. Fix: remove [FS] from #274.
- **[minor] B-6 — sequencing references sit within one milestone.** #280 "after the determinism guards" (#287,
  same Next milestone) and #278 "after fare contracts" (#279, same milestone) are order dependencies without
  stated in-milestone ordering beyond the issue text. Acceptable, but the tracker lists them as parallel
  checkboxes. Fix: state "do #287 and #279 before their dependents" in the tracker.

## 4. Constraint audit

- **Pass — no network, server, analytics, account, or Android path is implied anywhere.** Grep of all 28
  issue bodies: only refusals/negations (#272 "adds no network path", #278 "depends on the network" refused,
  #288 "No network, account, or leaderboard path"). #286 profiling uses local Instruments traces; #272's
  export is on-device. The only platform words are "iPhone"/"physical" in #268/#274/#286, consistent with
  portrait iPhone-only.
- **[minor] S-1 — #285's dispatcher voice has no production or licensing owner.** The issue requires
  "Original dispatcher callouts... appear in the audio license inventory" but does not say whether lines are
  synthesized (the repo has `tool/make_generated_audio.dart`) or recorded, and carries no `needs-human`
  despite the tracker's definition covering operator decisions. Fix: state the production method and add
  `needs-human` if recorded.
- **[minor] S-2 — #276's tip must land in the simulator before #277's price decision; both are P1 and the
  tracker does not order them.** The map does ("tips change the wallet"), and #277's acceptance repeats it;
  the tracker checkboxes don't. Fix: annotate #277 "blocked by #276."
- **Checked, no finding:** #263's screenshot states are capturable with the existing dev entrypoint once
  extended (CLAUDE.md:44-82 pipeline is real); #272's playtest export is new instrumentation but builds on the
  existing local diagnostics export (`settings_screen.dart:223-277`); no issue assumes iCloud, notifications,
  or an account.

## 5. Contradiction hunt

- **[blocker] X-1 — map vs tracker on traffic art** (same finding as B-1; the map's P0 acceptance and the
  tracker's P1 #275 cannot both be right).
- **[major] X-2 — "Done in this run" vs open PR #260** (same finding as B-2).
- **[major] X-3 — tracker defines `needs-human` as including "an art decision" but #262 has no
  `needs-human` label.** `#262` labels: `enhancement,assigned,roadmap`. Fix: add the label or narrow the
  tracker's definition. (This also hides the art dependency from the hourly sweep, which `assigned` reserves.)
- **[minor] X-4 — #278 says "After the ten-rung ladder and six cars, progression exhausts"; the fleet is
  seven vehicles** (six purchasable + starter). The progression review's exhaustion point is "104,500 coins
  and 15 achievements." Fix: say "after the ladder and the six purchases" or just "after the garage."
- **[minor] X-5 — the two "28" counts are not the same 28.** The map's 28 candidates include the
  claims-correction item (completed as PR #260, never an issue); the tracker's 28 include a hero/traffic split
  (#262+#275). #290 says "The map contains 28 issue candidates" next to "This tracker holds 28 issues," which
  reads as one set. Fix: note the substitution in the tracker.
- **Adjacent references handled correctly:** no issue duplicates #212, #94, #40, or #250-#257; each appears as
  a dependency/owner only (#274→#40, #286→#250-257, #263/#264/#275→submission package, #288/#287→current
  systems). The `assigned` label on all 28 matches the hourly-sweep convention stated in #290.
- **[minor] X-6 — #284's title/acceptance ("Coin pops... only when the wallet receives it") could be read as
  removing the existing level coin-pop animation entirely;** the review's complaint is only that the HUD
  counter must not lie (coins credited at completion, `taxi_game.dart:1438-1444`). Fix: clarify keep the pops,
  defer the counter/credit claim.

## 6. Number spot checks (re-derived from the worktree)

| Number | Where used | What I found |
|---|---|---|
| Full garage price | progression review §2.2/§3.3: 104,500; thesis §fun ladder ranges | 0+5,000+7,500+12,000+16,000+24,000+40,000 = **104,500**. Correct (`vehicle_catalog.dart:107-179`). |
| Vehicle count | thesis "seven vehicles"; #289 "seven sidegrades"; #278 "six cars" | **7 catalog entries, 6 purchasable + starter** (`vehicle_catalog.dart:103-188`; `cars_7` achievement threshold 7). #278's "six cars" is defensible but drifts; see X-4. |
| Achievement count | thesis "only three collection achievements"; #283 lists missing tracks | **15 total** (3 chain, 3 distance, 3 clean-bank, 3 cars, 3 streak), collection = cars_2/4/7 = **3**. Correct (`achievements.dart:93,104-223`). |
| Near-miss value | thesis/#269: "15 points times the live multiplier" | `nearMissScore = 15` (`fare_chain.dart:104`); `points = nearMissScore * multiplier` (`:265-270`). **15 × live multiplier. Correct.** |
| Five-second bank window | thesis "five-second choice"; #270/§2.2 | `BankPrompt.windowSeconds = 5.0` (`bank_prompt.dart:35`); timeout resolves `BankDecision.pushed` (`:62-73`). **Correct.** |
| Fare shares (bonus) | #279 "ten percent each" for VIP/long-haul/awkward | 0.10/0.10/0.10 (`fare_type.dart:108-110`), standard 70%. **Correct.** |
| Road profiles (bonus) | #280 "standard, narrow, avenue" | product-audit §1.4: 200/148/264 px profiles in `run_environment.dart:86-99`. **Correct.** |
| Thesis minute-ten timings | "3.9 min new driver, 5.4 min median" | Matches product-audit §0.2 probe table (probe outside repo, disclosed). **Consistent with its cited source.** |

## Summary of severities

Blockers: B-1/X-1 (traffic-art scope contradiction). Majors: M-1 (#262 capability/owner), B-2/X-2 (PR #260
reported done), B-3 (#271/#272 mispriority), B-4 (#274/#40 artifact), X-3 (needs-human missing on #262).
Minors: M-2, M-3, M-4, M-6, C-1..C-5, B-5, B-6, S-1, S-2, X-4, X-5, X-6. No unchecked area remains except
the competitor market numbers in §94 of the thesis (web desk-research, outside this repo/read-only scope).
