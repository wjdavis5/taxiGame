# Cab Hustle — Progression & Retention Audit (W3)

Run: 2026-10-10, product-manager fan-out, slice W3 of the Cab Hustle future map.
Repo read: `C:\git\repos\taxiGame-pm`, main @ c514609. Read-only.
Report file: `C:\Users\will\AppData\Local\Temp\opencode\taxi-pm\review\progression-retention.md`.

Evidence rules used here: every code claim cites path + line + a short quote; every number names its
source (code constant with line, a pasted simulator table line, the commit message that recorded a
batch, or arithmetic from those, shown inline). Estimates are labelled. Anything I could not evidence
is in the final **Unverified** section.

---

## 1. The product as shipped (one paragraph)

A portrait iPhone-only Flutter/Flame taxi arcade game. A 10-rung hand-made tutorial ladder
(`GameLevel.ladderLength = 10`, `taxi_game/lib/game/levels/level.dart:13`) hands off to an endless
procedural shift with three lives and bank-or-push at every dropoff; a date-seeded Daily Shift gives
everyone the same course once a day; a garage sells six handling-different cabs; records, lifetime
stats, 15 achievements, a daily history and a one-day ghost round it out. Everything is on-device
(`shared_preferences`), no network calls at all — `CLAUDE.md:327-330` ("Progress is on-device only
(`shared_preferences`). The app makes no network calls at all"), enforced by a dependency list with
no network or notification package (`taxi_game/pubspec.yaml:9-44`: flame, flame_audio, flutter_svg,
provider, shared_preferences, path_provider, vector_math, meta). Progress is two coins-denominated
rails — one-time tutorial/garage — plus records.

---

## 2. Coin faucets and sinks

### 2.1 Faucets — every way to earn coins

| # | Faucet | Amount | When it lands | Evidence |
|---|--------|--------|---------------|----------|
| 1 | Endless fare delivery | `reward = round((20 + rideLength/30 + bonus0-15) × fareType.rewardMultiplier)` — standard ≈ 38-68, VIP ≈ 114-204, far-side ≈ 57-102, long-haul ≈ 57-72 | immediately at each dropoff | `lib/game/systems/endless_course.dart:333-334`; `lib/models/fare_type.dart:40-45`; credited at `lib/game/taxi_game.dart:1058` (`gameState.addCoins(passenger.reward);`) |
| 2 | Bank the chain (endless) | chain score ×1 coin, whole amount, ends the shift | at the BANK button, or pause-menu BANK & QUIT | `lib/game/taxi_game.dart:1241` (`gameState.addCoins(lastBankedScore!);`); pause path `:1141-1146` |
| 3 | Level completion (tutorial) | flat 50/75/100/125/150/175/200/225/250/300 per rung (sum **1,650**); a banked level pays the chain score instead (`:1183-1187`); on the banking rungs an unbanked finish pays `max(chain, flat)` (`math.max(fareChain.score, currentLevel.coinReward)`, `:1438-1442`) | at level complete | `assets/levels/level_001.json` … `level_010.json` (`"coinReward"` values 50…300); payout at `lib/game/taxi_game.dart:1438-1444` |
| 4 | Near-miss ("close call") | `nearMissScore = 15` × live multiplier into the at-risk chain score — becomes coins only if banked | at the pass, but paid as coins at the bank | `lib/game/systems/fare_chain.dart:104` (`static const int nearMissScore = 15;`), `:265-270` (`final points = nearMissScore * multiplier;`) |
| 5 | Push-on bonus | +1 multiplier on the next fare (future score, not coins) | at each pushed dropoff | `lib/game/systems/fare_chain.dart:96` (`static const int pushBonusStep = 1;`), `:246-248` |

No other faucet exists. In particular the recurring `totalGems` field is never written by gameplay:
it only round-trips in the save (`lib/models/save_data.dart:8`, `:71`, `:127`) and is exposed by the
service (`lib/services/game_state_service.dart:61`) — a dead currency.

### 2.2 Sinks — every price

| # | Sink | Price (coins) | Evidence |
|---|------|---------------|----------|
| 1 | City Compact | 5,000 | `lib/data/vehicle_catalog.dart:119` |
| 2 | Street Sedan | 7,500 | `lib/data/vehicle_catalog.dart:131` |
| 3 | Family Minivan | 12,000 | `lib/data/vehicle_catalog.dart:143` |
| 4 | Trail SUV | 16,000 | `lib/data/vehicle_catalog.dart:155` |
| 5 | Night Racer | 24,000 | `lib/data/vehicle_catalog.dart:167` |
| 6 | The Executive | 40,000 | `lib/data/vehicle_catalog.dart:179` |
| | **Full garage (all six purchases)** | **104,500** | sum |

The starter cab is free and pre-owned (`price: 0`, `lib/data/vehicle_catalog.dart:107`;
`unlockedVehicles: ['taxi_yellow']`, `lib/models/save_data.dart:72`). A new save starts at 0 coins
(`totalCoins: 0`, `lib/models/save_data.dart:70`). Vehicles are the *only* sink —
`spendCoins` is called from exactly one place, `unlockVehicle` (`lib/services/game_state_service.dart:353`,
`:455-476`), i.e. one-time cart purchases with no repeatable or cosmetic sink behind them.

---

## 3. Pacing math

### 3.1 Inputs

**The current simulator batch** (fresh, run by the parallel worker; 101 seeds 1000-1100, starter cab,
`flutter test test/economy_simulation_test.dart --reporter expanded`, output captured at
`C:\Users\will\AppData\Local\Temp\opencode\taxi-pm\economy_sim.out.txt:41-61`):

| profile | median shift | fares-only floor p50 | brink-banked score p50 | shift total p50 |
|---------|--------------|----------------------|------------------------|-----------------|
| new (0.40s/0.10/1.00) | 2.9 km, 19 fares | 1,220 | 4,847 | **6,225** |
| median (0.25s/0.03/1.25) | 3.6 km, 23 fares | 1,522 | 5,358 | **6,995** |
| good (0.16s/0.005/1.60) | 6.2 km, 35 fares | 2,299 | 6,497 | **9,122** |

"Shift total = fares-only floor + brink-banked chain score (1:1). Perfect-foresight banking is the
ceiling; a real player's wallet lands between the floor and the ceiling."
(`economy_sim.out.txt:61`; the same definition is in `lib/game/systems/shift_earnings.dart:40-47`.)

**The ladder's pricing assumption** (the batch that set today's prices, commit d861dd3, and the
catalog comment): "roughly 2,000 coins a shift for a first-session player, 2,300–3,000 for a
competent one" (`lib/data/vehicle_catalog.dart:75-76`; commit d861dd3 message: "priced off the
conservative wallet the floors imply"). That batch's table (commit d861dd3): new total p50 6,808,
median 8,368, good 8,077; floors new 1,240 / median 1,444 / good 1,584. A later re-measure in the
test comment: "the batch after that fix re-measured new 6001 / median 7134 / good 7697"
(`test/economy_simulation_test.dart:117`).

**Tutorial cash before endless**: 1,650 coins (sum of the ten flat rewards, §2.1 row 3), one-time and
not replayable — the menu's PLAY loads the save's current rung only
(`lib/game/taxi_game.dart:599`, `await loadLevel(gameState.currentLevel);`), and no level-select UI
exists anywhere in `lib/ui`. (`game_state_service.dart:363-364` says "Replaying an old level only
earns coins", but no shipped screen offers a replay.)

**Shift length**: "roughly three to six minutes of driving" (`test/run_length_simulation_test.dart:21`).
A median shift of 3.6 km = 36,000 px (`RunSummary.pixelsPerMetre = 10.0`,
`lib/game/systems/run_summary.dart:68`) at the starter's 150 px/s top speed
(`vehicle_catalog.dart:109`) is ≥ 240 s before any kerb stop — so ~4-6 minutes is the derived band
(estimate; the sim's `drivenSeconds` is not printed by the test).

### 3.2 First vehicle — City Compact, 5,000 coins

Arithmetic, using the tutorial cash of 1,650 first:

- Shortfall after the tutorial: 5,000 − 1,650 = **3,350**.
- At the new-player floor (1,220/shift): 3,350 / 1,220 = **2.7 more shifts**.
- At the new-player ceiling (6,225/shift): 3,350 / 6,225 = **0.5 more shifts**.

Ignoring the tutorial entirely for a lower bound: 5,000/6,225 = **0.8**, 5,000/6,995 = **0.7**,
5,000/9,122 = **0.5** shifts at the three ceiling medians; 5,000/1,220 = **4.1**,
5,000/1,522 = **3.3**, 5,000/2,299 = **2.2** shifts at the floors. The commit's own target —
"City Compact 150 -> 5000 (2.5 new shifts: first car in 2-3 shifts)" (d861dd3) — assumes the
~2,000/shift wallet, i.e. roughly the floor plus partial banking.

**Verdict: the first car lands in the first session, within roughly 1-4 endless shifts** (certain
unless the player never finishes a shift). Because the wreck floor still pays every fare collected
(`ShiftEarnings.wreckCoins`, `lib/game/systems/shift_earnings.dart:80-81`), even a three-wreck session
moves the bar. — consistent across every reading.

### 3.3 Full garage — 104,500 coins

All arithmetic for the same capstone across the three measurement bases:

| Basis (source) | per shift | shifts for 104,500 |
|----------------|-----------|--------------------|
| new ceiling (economy_sim.out.txt:47) | 6,225 | 104,500 / 6,225 = **16.8 → ~17** |
| median ceiling (:53) | 6,995 | 104,500 / 6,995 = **14.9 → ~15** |
| good ceiling (:59) | 9,122 | 104,500 / 9,122 = **11.5 → ~12** |
| new floor (:45) | 1,220 | 104,500 / 1,220 = **85.7 → ~86** |
| median floor (:51) | 1,522 | 104,500 / 1,522 = **68.7 → ~69** |
| good floor (:57) | 2,299 | 104,500 / 2,299 = **45.5 → ~46** |
| ladder wallet, first-session (vehicle_catalog.dart:75) | 2,000 | 104,500 / 2,000 = **52.3 → ~53** |
| ladder wallet, competent (vehicle_catalog.dart:76) | 2,500-3,000 | **42 → 35** |

So the honest answer is a **range, not a number: ~15 shifts if a player banks near the brink; ~42-53
on the wallet the ladder was priced against; ~46-86 if they never bank and only collect fares.**
The single biggest cause is not skill (floors and ceilings differ ~3x inside one profile) but *when
the player chooses to bank*, which the simulator models only at the perfect-foresight brink
(`shift_earnings.dart:40-47`).

Milestones inside the garage, same bases:

- **Mid fleet**: first three cars = 5,000+7,500+12,000 = 24,500. Ceiling: 24,500/6,225 = 3.9 (new),
  24,500/6,995 = 3.5 (median). Ladder basis: 24,500/2,500 = 9.8 ↔ the catalog's "mid fleet about a
  week of dailies" (`vehicle_catalog.dart:77-78`). Floor: 24,500/1,220 = 20.1 (new).
- **The Executive**: 40,000. Commit target: "16 median shifts" (40,000/2,500 = 16). Ceiling:
  40,000/6,995 = **5.7**, 40,000/9,122 = **4.4** (good). Floor: 40,000/1,220 = **32.8** (new).

**Daily-Shift cadence** (because the Daily is an ordinary endless shift, one attempt per day —
`lib/game/systems/daily_shift.dart:12-19`, `:33-45`): playing only the daily, the Executive is
**6 days** (median ceiling) to **33 days** (new floor); the full garage is **15 days to 86 days**.
The same coins-per-shift rules apply — the daily has no bonus of its own (§5).

**Wall-clock** (estimate): at the 3-6 min/shift figure, ~15 shifts ≈ 0.75-1.5 h; ~42 ≈ 2-4 h;
~86 ≈ 4.5-8.5 h. Labelled estimate.

### 3.4 Pacing red flag — two incompatible "wallet" figures in the codebase

`lib/data/vehicle_catalog.dart:71-76` reports the instrument "measured the result at 1,240–1,584
coins of fares alone per shift (p25–p75 across three skill stand-ins) before banking" and prices off
"roughly 2,000 coins a shift". The current simulator agrees on fares (medians 1,220/1,522/2,299 —
`economy_sim.out.txt:45,51,57`) but puts the *shift total* — fares + brink bank — at
6,225/6,995/9,122. The two statements are both true under different banking behavior, but they imply
capstone grinds that differ by ~3x (15 shifts vs 42-53). Nothing on-device measures which is real.
This should be resolved by the roadmap before any price is touched.

---

## 4. Every progression and reward surface, with its reward and cadence

| Surface | What the player gets | Cadence | Evidence |
|---------|----------------------|---------|----------|
| Tutorial ladder (10 rungs) | 50-300 coins/rung, next rung unlocks, the Endless handoff panel ("TUTORIAL COMPLETE!" + START SHIFT), level names shown on completion | one-way, one-time, first sessions | `level.dart:13`; `assets/levels/*.json`; `game_state_service.dart:365-372`; handoff `taxi_game.dart:595-599`, `:1493-1496`; `game_screen.dart:482-576` |
| Endless Shift | Fare coins on the spot; bank converts chain 1:1; PB detection + "NEW PERSONAL BEST"; run summary (score, chain, fares, close calls, distance, coins earned); achievements banners; DRIVE AGAIN | any time, ~3-6 min per shift | `taxi_game.dart:1058`, `:1241`, `:1261-1308`; `run_summary_panel.dart:173-218`, `:276-314` |
| Daily Shift | Same coins as endless, but runs the shared date-seeded course; a day is "spent" when it ends; result + row in history; streak feeds hidden achievements; the trace becomes the ghost | once per day | `daily_shift.dart:3-19`; `game_state_service.dart:442-452`; `daily_screen.dart:264-273` |
| Ghost race | The day's course is replayable after the scoring attempt; own ghost car on the road; can pay coins, set the endless PB, update the ghost; never changes the day's result | after the day's attempt, until midnight | `taxi_game.dart:1348-1377`; `game_screen.dart:42-46`; `daily_screen.dart:328-374`; `ghost_trace.dart:5-17` |
| Near-miss economy | 15 × multiplier into the at-risk chain; on-road pop + system click; per-run "Close calls" count on the summary | every tight pass | `fare_chain.dart:104`, `:265-270`; `near_miss.dart:48`, `:61`; `run_summary_panel.dart:279` |
| Garage | Six buying decisions with felt stat trade-offs (bars), auto-equip on purchase, fleet achievements at 2/4/7 | coin-gated, one-time purchases | `vehicle_catalog.dart:3-14`, `:103-188`; `garage_screen.dart:342-375`; `achievements.dart:179-199` |
| Records screen | 4 personal bests (best banked score, longest chain, furthest distance, most fares) + all 15 achievements with earned state or `n/threshold` progress | read anytime; written at shift end, daily, garage | `records_screen.dart:113-138`, `:148-179`; `personal_bests.dart:31-53` |
| Stats screen | Lifetime totals (shifts, score, distance, fares, lives lost, time), typical-shift medians, run-length bands, bank-vs-push share, median crash distance | read anytime (Settings → Shift stats) | `stats_screen.dart:154-262`; entry only at `settings_screen.dart:320-336` |
| Menu | Level/"TUTORIAL COMPLETE", coin balance, endless "BEST n", daily status line ("DONE FOR TODAY", score) | every launch | `main_menu_screen.dart:80-102`, `:291-301`, `:375-389` |
| Share score card | A shareable image/plain-text card with score, chain, distance, date, daily seed and a rank title (RADIO ROOKIE → GIG-LEGEND, "SO CLOSE IT HURTS") via the iOS share sheet | after a settled shift | `score_card.dart:5-12`, `:70-87`; `run_summary_panel.dart:315-324` |
| Daily history | Dated rows (JAN 01 · score · banked/wrecked), capped at 400 results (~a year) | after each daily | `game_state_service.dart:24-28`; `daily_screen.dart:120-135`, `:410-455` |

Persisted-record caps: 200 shift records (`game_state_service.dart:19-22`) and 400 daily results
(`:24-28`); totals/PBs are lifetime counters (`lifetime_run_totals.dart:4-19`, `personal_bests.dart:12-20`).

---

## 5. Achievements — what they cover, and what they miss

15 achievements across 5 tracks (`lib/models/achievements.dart:93-99`, all listed `:227-243`):

| Track | Awards | Thresholds | Evidence |
|-------|--------|-----------|----------|
| Chains | HOT STREAK / CHAIN ARTIST / CHAIN MASTER | ×3 / ×5 / ×8 chain in one shift | `:104-124` |
| Distance | KNOWING THE STREETS / MARATHON SHIFT / CROSS-TOWN LEGEND | 1 / 3 / 5 km in one shift | `:128-148` |
| Clean banking (a bank with no life lost) | SCOT-FREE / SURE HANDS / THE HOUSE ALWAYS WINS | 1 / 5 / 15 clean banks, lifetime | `:152-172` |
| Cars collected | TWO-CAB OPERATION / FLEET BUILDER / FULL FLEET | own 2 / 4 / 7 | `:179-199` |
| Daily streaks | HABIT FORMING / WEEKLY GRIND / MONTH ON THE METER | 3 / 7 / 30 consecutive completed dailies | `:203-223` |

Playstyles the set **misses**, against systems that exist in the game:

- **Near-miss mastery** — the game celebrates and pays close calls (`fare_chain.dart:104`) and records
  `nearMisses` per shift (`run_record.dart:44-49`), but there is no achievement, no lifetime stat
  (RunStats never aggregates it, `run_stats.dart:51-82`) and no records row.
- **Fare-choice play** — declining VIPs/far-side fares is a designed decision
  (`endless_fare_controller.dart:143-161`, tracked as `faresDeclined`), but nothing reads that count
  outside the live controller.
- **Score tiers** — "CERTIFIED HUSTLER"/"TRAFFIC MENACE"/"GIG-LEGEND" exist only inside the share
  card rank (`score_card.dart:83-86`); no achievement uses score at all despite
  `bestBankedScore`/`endlessBestScore` being stored.
- **Getting good at a car** — no per-vehicle use/mastery measure despite seven handling profiles.
- **Lifetime volume** — no "deliver 1,000 fares", "drive 100 km", "bank 100 shifts" style award;
  the stored counters to compute them already exist (`lifetime_run_totals.dart:24-43`).
- **Daily participation without a streak** — a lapsed streak leaves the 3/7/30 as the only daily goals;
  "play 10 dailies" (total) is not a thing.
- **Tutorial completion** — finishing all ten rungs is a big visible moment but earns nothing.

Completion cadence: achievements are evaluated at shift end (`game_state_service.dart:404-427`), at
daily record (`:442-452`) and at garage purchase (`:469-473`); upgrades re-evaluate on load silently
(`:302-308`). Unlocks surface as banners on the run summary (`run_summary_panel.dart:219-274`) and
garage snackbars (`garage_screen.dart:352-374`).

---

## 6. Against what this genre uses for retention

What endless/arcade mobile games lean on: daily ritual, streaks, collections, near-term goals,
mastery signals, discovery/variety, events/seasons, leaderboards/social, push reminders.

| Mechanic | Genre standard | Cab Hustle today | On-device (no-network) verdict |
|----------|----------------|------------------|-------------------------------|
| Daily ritual | one seeded/content day | **Has, finished well**: shared date-seed course, "SAME FOR EVERYONE" copy, one attempt, result screen, history, ghost race, share card (`daily_shift.dart:3-19`, `main_menu_screen.dart:375-389`, `daily_screen.dart`) | Keep; strongest thing in the game |
| Streaks | visible counter + escalating reward; a miss stings | **Weak**: no current-streak value in the save at all; only the longest-ever run computed from history feeds 3 achievements (`achievements.dart:34-37`, `:276-292`); no streak UI, no daily bonus | Fully buildable on-device: store current streak, show it beside the daily, pay a date-scaled coin bonus |
| Collections | sets, cosmetics, completion chase | Partial: 6 one-time cars with completion achievement; no cosmetics, no paints/titles/horns | Buildable on-device; note the garage is the *only* sink |
| Near-term goals | "X more to unlock Y" nudges | Weak: price list + balance in the garage; the only nudge is a failed-purchase snackbar ("you need N more", `garage_screen.dart:377-397`); menu never shows a goal | Buildable on-device: next-car progress on the menu |
| Mastery signals | stat walls, ranks, personal bests | **Has**: 4 PBs, lifetime totals, medians, rank titles, ghost, per-run summary (`records_screen.dart`, `stats_screen.dart`, `score_card.dart:70-87`) — but the stats wall hides behind Settings (`settings_screen.dart:320-336`) | Move/mirror to menu; add near-miss + decline stats already recorded |
| Discovery/variety | new content over time | Partial: 4 fare kinds, per-run environment/weather, 7 cars; no unlockable content after the fleet | Buildable on-device: date-seeded daily modifiers, vehicle-specific challenges |
| Events/seasons | live-ops calendar | **Missing** | Date-derived weekly/monthly "gauntlet" seed needs no server (`DailyShift.seedForDateKey` is pure arithmetic, `daily_shift.dart:61-73`) |
| Leaderboards/social | global boards, friends | **By design impossible** (no network; privacy claims, `CLAUDE.md:327-330`). The share card is the compliant substitute | Keep the share card; it is the only compliant social channel |
| Reminders | push notification at a good hour | **Missing** — no notification package in `pubspec.yaml:9-44`; the silence is a deliberate-looking consequence of the privacy posture | A *local* daily reminder is possible without network; it needs a permission prompt and a privacy-policy check before it ships |

**What retention can still be built on-device** (all local, contract-safe): current-streak storage,
display and reward; next-goal surfacing for the garage; daily-participation and near-miss/decline
achievements and stats; a date-seeded weekly challenge or modifier reusing `DailyShift.seedForDateKey`;
vehicle mastery counters; local daily notification. **Not shippable** under the current claims:
leaderboards, server events, any analytics, and — because the policy says no network calls —
cross-device/iCloud sync.

---

## 7. The three strongest and three weakest retention facts

### Strongest

1. **A complete, self-contained daily ritual exists** — shared date-seeded course, one attempt,
   same-for-everyone framing, result + history, a ghost to race all day, and a shareable card. It
   delivers the genre's whole daily loop with zero backend (`daily_shift.dart:3-19`;
   `main_menu_screen.dart:321-417`; `daily_screen.dart:148-374`; `score_card.dart:5-12`).
2. **The core loop is stakes + instant retry, with no dead sessions.** Three lives
   (`lives.dart:13`), bank-or-push asked at *every* dropoff on a 5-second live window with push as
   the default (`bank_prompt.dart:26-35`), bank pays the chain 1:1 (`taxi_game.dart:1241`), and
   DRIVE AGAIN restarts without a menu trip — the code says why: "the friction between 'I died' and
   'I'm driving again' is where retention is won or lost" (`taxi_game.dart:1329-1333`). Even a wreck
   keeps the fares already collected (`shift_earnings.dart:80-81`).
3. **Dense on-device mastery + record layers that grow forever.** 4 stacked personal bests
   (`personal_bests.dart:31-53`), 6 lifetime totals that the 200-shift window can't shrink
   (`lifetime_run_totals.dart:4-19`), 15 achievements with visible progress
   (`records_screen.dart:148-260`), rank-titled share cards (`score_card.dart:70-87`) and a
   same-day ghost (`ghost_trace.dart:5-17`).

### Weakest

1. **The streak machine stops at "longest ever run" and pays nothing.** There is no current streak
   in the save (`save_data.dart:50-78` has no streak field), no streak on any screen, and the only
   payoff is three hidden achievements (`achievements.dart:203-223`). Missing a day costs the player
   nothing they can see; nothing ever brings them back the next day.
2. **Progression exhausts at 104,500 coins and 15 achievements** — two one-time rails with no
   repeatable or cosmetic sink behind them (`vehicle_catalog.dart:103-188`; `spendCoins` has one
   caller, `game_state_service.dart:353`, `:455`). The `totalGems` currency exists in the save but
   is never earned or spent (`save_data.dart:8`, `:71`, `:127`) — a live placeholder for a second
   sink.
3. **The progression signals are recorded but buried or unread.** The stats wall (the game's whole
   mastery surface) sits behind a Settings tile (`settings_screen.dart:320-336`); the near-miss and
   fare-decline data the game is proud of is per-run only — `nearMisses` is stored in every record
   (`run_record.dart:44-49`) but `RunStats` never aggregates it (`run_stats.dart:51-82`); and the
   game never states a next goal anywhere except a failed purchase
   (`garage_screen.dart:377-397`).

---

## 8. Unverified

- **The real wallet per shift.** No analytics and no device playtest data exist; the sim brackets
  (floor vs brink bank) are arithmetic, not measured humans. The ladder's 2,000-3,000/shift and the
  sim's 6,000-9,000/shift totals are not reconciled by any on-device number.
- **The fresh economy table** (`economy_sim.out.txt:38-63`) is another worker's captured test output;
  I read it but did not re-run the command myself. The commit-batch numbers (d861dd3) are historical
  and differ slightly from the fresh run.
- **Median real-shift wall time**: derived from distance (3.6 km) + top speed, not from the sim's
  `drivenSeconds` (which the test does not print). Labelled estimate in §3.1.
- **Whether any non-`lib` path writes `totalGems`**: I grepped `lib/**/*.dart` only; no writer was
  found there.
- **Whether a local notification would violate the published privacy policy**: not checked against
  `docs/privacy-policy.md` wording; only that no notification dependency exists today.
- **Motivational effect of the daily/streak/ghost** on real players: zero behavioral evidence exists
  in the repo, and none can be gathered by the project without changing the privacy claims.

---

## 9. Source index

Code (repo `taxi_game/`): `lib/data/vehicle_catalog.dart`; `lib/models/save_data.dart`,
`personal_bests.dart`, `lifetime_run_totals.dart`, `run_record.dart`, `run_stats.dart`,
`achievements.dart`, `ghost_trace.dart`, `fare_type.dart`; `lib/game/taxi_game.dart`;
`lib/game/systems/endless_course.dart`, `shift_earnings.dart`, `fare_chain.dart`, `bank_prompt.dart`,
`lives.dart`, `daily_shift.dart`, `near_miss.dart`, `run_summary.dart`, `score_card.dart`,
`endless_fare_controller.dart`, `difficulty_curve.dart`; `lib/services/game_state_service.dart`;
`lib/ui/screens/main_menu_screen.dart`, `daily_screen.dart`, `garage_screen.dart`,
`records_screen.dart`, `stats_screen.dart`, `settings_screen.dart`, `game_screen.dart`;
`lib/ui/widgets/run_summary_panel.dart`, `bank_prompt_overlay.dart`; `assets/levels/level_001..010.json`;
`pubspec.yaml`.
Tests: `test/economy_simulation_test.dart` (table command + re-measured comment),
`test/run_length_simulation_test.dart` (shift length), `test/vehicle_handling_test.dart` (no
dominating car), `test/achievements_test.dart` (fleet count).
Process: commit `d861dd3` ("fix: price the garage against endless earnings…", full batch table and
re-ladder targets); commit `b5f9f8f` (re-measure note); `CLAUDE.md` §Conventions.
Captured outputs: `C:\Users\will\AppData\Local\Temp\opencode\taxi-pm\economy_sim.out.txt` (fresh
economy table), `run_length_sim.out.txt` (run-length test pass, no table printed).
