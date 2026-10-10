# Cab Hustle — W1 product inventory and core-loop audit

Worktree: `C:\git\repos\taxiGame-pm` at `c514609` ("fix: make the UX exits re-entry safe, surface load failures, and report reset refusals (#240 #241 #242 #243 #244) (#259)"). Read-only review: no edits, commits, or pushes were made to the worktree. All commands ran from `C:\git\repos\taxiGame-pm\taxi_game` unless stated.

Method: code reads in `lib/` and `assets/levels/`, plus the shipped tuning tests, plus one probe test (written under the temp directory, outside the repo) that prints the per-skill run-length medians the shipped run-length suite does not print. The probe is disclosed as such and its own command is named.

---

## 0. Commands run (key output)

### 0.1 `flutter test test/economy_simulation_test.dart`

Result: 2 tests passed. Printed table (verbatim):

```
Endless coins per shift — 101 seeds (seeds 1000..1100), starter cab

new driver (reaction 0.4s, misjudge 0.1, lookahead 1.0s)
  median shift       : 2.9 km, 19 fares delivered, best chain x17
  fares-only floor   : p25 1033  median 1220  p75 1400
  brink-banked score : p25 3927  median 4847  p75 6740
  shift total        : p25 5055  median 6225  p75 8096

median driver (reaction 0.25s, misjudge 0.03, lookahead 1.25s)
  median shift       : 3.6 km, 23 fares delivered, best chain x16
  fares-only floor   : p25 1263  median 1522  p75 1737
  brink-banked score : p25 3936  median 5358  p75 7400
  shift total        : p25 5505  median 6995  p75 9033

good driver (reaction 0.16s, misjudge 0.005, lookahead 1.6s)
  median shift       : 6.2 km, 35 fares delivered, best chain x16
  fares-only floor   : p25 1850  median 2299  p75 2926
  brink-banked score : p25 4781  median 6497  p75 8882
  shift total        : p25 7115  median 9122  p75 12018

Shift total = fares-only floor + brink-banked chain score (1:1). Perfect-foresight banking is the ceiling; a real player's wallet lands between the floor and the ceiling.
```

**What this table measures, in one line:** what one simulated endless shift pays in coins, split into per-fare coins and banked chain score, across three stand-in skill profiles over 101 seeds (`test/economy_simulation_test.dart:8-15`, `:40-100`).

**Caveat in the table itself:** the line labelled `median shift : X km` is computed as `totalKm / runCount` — a **mean** distance, not a median (`test/economy_simulation_test.dart:62` `totalKm += run.distancePx / 10000;`, `:83` `'  median shift       : ${(totalKm / runCount).toStringAsFixed(1)} km, ...'`). The same line's fare count and best chain are true medians (`pct(fares, 0.5)` / `pct(chains, 0.5)`). This matters most for the good driver, where one tail of long runs pulls the mean (6.2) above the actual median (5.7, probe below).

### 0.2 `flutter test test/run_length_simulation_test.dart`

Run twice, once default reporter and once `--reporter expanded`: 12 tests pass, **and it prints no table**. The channel-visible output is the test list:

```
00:02 +12: All tests passed!
```

**What this suite measures, in one line:** whether a Monte-Carlo batch of 101 simulated endless shifts is fair — median distance in the 2–4 km band, opening-kilometre near-death-free, progressive death rates, and no fixed-skill driver outrunning the curve (`test/run_length_simulation_test.dart:9-29`, `:47-114`). Its target band is quoted in-code: "**The deliberate target band: a median shift of 2-4 km** (20,000-40,000 px) ... roughly three to six minutes of driving" (`test/run_length_simulation_test.dart:19-28`).

Because the shipped suite prints nothing per skill level, the minutes/km numbers below come from a probe run under `C:\Users\will\AppData\Local\Temp\opencode\taxi-pm\run_length_probe_test.dart` (outside the repo), which drives the **same shipping `RunLengthSimulator`, same 101 seeds, starter cab, and the same three skill profiles as the economy test**, and prints medians:

```bash
flutter test C:\Users\will\AppData\Local\Temp\opencode\taxi-pm\run_length_probe_test.dart
```

Key output:

```
new driver
  median shift: 3.0 km, 3.9 min (driven)
  p25: 2.6 km, 3.3 min | p75: 3.3 km, 4.3 min

median driver
  median shift: 3.7 km, 5.4 min (driven)
  p25: 3.2 km, 4.4 min | p75: 4.1 km, 6.4 min

good driver
  median shift: 5.7 km, 11.4 min (driven)
  p25: 4.5 km, 7.6 min | p75: 7.2 km, 15.7 min
```

**Typical shift length per skill level (driven time; crash stalls excluded — `lib/game/systems/run_length_simulator.dart:52-54`):**

| Skill stand-in | Median distance | Median minutes | p25 | p75 |
|---|---:|---:|---:|---:|
| new | 3.0 km | 3.9 min | 2.6 km / 3.3 min | 3.3 km / 4.3 min |
| median (simulator defaults) | 3.7 km | 5.4 min | 3.2 km / 4.4 min | 4.1 km / 6.4 min |
| good | 5.7 km | 11.4 min | 4.5 km / 7.6 min | 7.2 km / 15.7 min |

The simulator's own safety cap is 80 km / 2 h (`run_length_simulator.dart:296-297`); 10 px = 1 m (`lib/game/systems/run_summary.dart:68`).

### 0.3 `flutter test test/vehicle_handling_test.dart` (ran to check the catalog invariants rather than take the comment on faith)

```
00:00 +12: All tests passed!
```

included: "every car is strictly beaten on at least one axis by some car", "no car holds the fleet best on every axis", "every car faster than the starter gives something up for it", "garage choice reaches the road (issue #9) the equipped car is the car whose stats are driven".

---

## 1. Shipped content inventory

### 1.1 Tutorial ladder — 10 levels

Ladder length is a code constant, not an asset probe: `static const int ladderLength = 10;` (`lib/game/levels/level.dart:13`), with the doc "The ten hand-made levels in `assets/levels/`" (`level.dart:7-12`). Ten JSON files ship in `assets/levels/`: `level_001.json` … `level_010.json`.

| # | Name | Coins (flat reward) | Difficulty | Pickups | Drops | Teaches banking | Traffic pattern | Spawn interval (s) |
|---|---|---|---:|---:|---:|---|---|---:|
| 1 | First Ride | 50 | easy | 1 | 1 | no | lesson_light | 4.5 |
| 2 | Cross Town | 75 | easy | 1 | 1 | no | lesson_light_plus | 4.2 |
| 3 | Two Fares | 100 | easy | 2 | 2 | no | lesson_light_medium | 3.8 |
| 4 | Picking Up | 125 | easy | 2 | 2 | no | lesson_medium_light | 3.4 |
| 5 | Against the Clock | 150 | medium | 1 | 1 | no | lesson_medium | 3.0 |
| 6 | Rush Hour Meter | 175 | medium | 2 | 2 | no | lesson_medium_plus | 2.8 |
| 7 | Chain Reaction | 200 | hard | 3 | 3 | no | lesson_medium_fast | 2.5 |
| 8 | Keep the Chain | 225 | hard | 3 | 3 | no | lesson_medium_heavy | 2.2 |
| 9 | Bank It | 250 | hard | 2 | 2 | **yes** | lesson_hard | 2.0 |
| 10 | Graduation Shift | 300 | hard | 3 | 3 | **yes** | lesson_graduation | 1.8 |

Table built from the 10 JSON files (`assets/levels/level_001.json` … `level_010.json`); example: `"name": "First Ride"`, `"coinReward": 50`, `"spawnInterval": 4.5` (`level_001.json:3`, `:11`, `:14`). `bankPrompt` parses with a missing key meaning "does not teach banking" (`lib/game/levels/level.dart:76-77`). Every ladder fare is standard-type by design — "a level's pickups are mandatory objectives, so there is no take-it-or-leave-it decision for a special fare to live in" (`lib/models/fare_type.dart:68-72`).

Level difficulty enum has four values: easy/medium/hard/expert (`level.dart:98-103`); shipped levels use the first three.

Level-mode rules that differ from endless: one crash fails the level (`lib/game/taxi_game.dart:1498-1507`), each passenger's coin reward is the level reward split across its pickups (`taxi_game.dart:907` `reward: currentLevel.coinReward ~/ currentLevel.pickupPoints.length,`), and completion pays the flat reward — or on the two banking rungs the **better** of chain score and flat reward if the player pushes to the end; a bank pays the chain score and forfeits the flat reward (`taxi_game.dart:1427-1444`, `:1183-1187`). Full-ladder flat rewards sum to **1,650 coins** (50+75+100+125+150+175+200+225+250+300), before replays.

### 1.2 Garage vehicles — 7

All seven have art and handling; the starter is owned from first launch (`lib/data/vehicle_catalog.dart:69-81`, `:103-188`).

| id | Name | Price | topSpeed px/s | accel px/s² | steering px/s | body w×h px | body area px² |
|---|---|---:|---:|---:|---:|---:|---:|
| taxi_yellow | Classic Cab (starter) | 0 | 150 | 400 | 300 | 40×60 | 2,400 |
| compact_red | City Compact | 5,000 | 132 | 380 | 345 | 34×50 | 1,700 |
| sedan_blue | Street Sedan | 7,500 | 158 | 415 | 285 | 40×62 | 2,480 |
| minivan_gray | Family Minivan | 12,000 | 138 | 480 | 255 | 48×72 | 3,456 |
| suv_green | Trail SUV | 16,000 | 162 | 470 | 270 | 46×70 | 3,220 |
| sports_black | Night Racer | 24,000 | 188 | 540 | 290 | 36×56 | 2,016 |
| luxury_white | The Executive | 40,000 | 172 | 370 | 315 | 46×76 | 3,496 |

Values from `vehicle_catalog.dart:103-188` (starter `:104-115`, Executive `:176-187`). `VehicleStats` documents the axes: "these are the numbers the driving physics reads — forward top speed, throttle ramp, lateral speed at full steering lock — plus the logical body the hitbox is derived from" (`:5-8`); body area is `width * height` (`:44-45`). Unknown ids fall back to the starter's handling (`:198-201`). The design intent is no dominant car: "every car is strictly beaten on at least one axis by some other car, and any car faster than the starter gives something up for that speed" (`:10-14`), enforced and passing in `test/vehicle_handling_test.dart` (verified above). Prices are an ascending ladder sized against the endless economy (`:69-81`).

### 1.3 Traffic vehicle types — 5

`enum TrafficVehicleType { sedan, truck, sportsCar, suv, bus }` (`lib/models/traffic_pattern.dart:181-187`).

| Type | Size (px) | Speed multiplier |
|---|---|---:|
| sedan | 40×60 | 1.0 |
| truck | 45×80 | 0.7 |
| sports car | 38×55 | 1.3 |
| SUV | 42×70 | 0.9 |
| bus | 50×100 | 0.6 |

Sizes `traffic_pattern.dart:212-225`; multipliers `:227-240`. A second "vehicle kind" appears only as the construction cone in text ("'sedan', 'sports car', 'SUV', 'traffic cone'", `lib/game/systems/collision_rules.dart:42-48`) — cone lines are static construction barriers, not a spawned vehicle type. Ladder JSONs use three-lane patterns at x=160 / 200 / 240 with no explicit `oncoming` key; parsing defaults "left half of the road (and the center line) is oncoming" (`traffic_pattern.dart:119-122`), so 160 and 200 are oncoming and 240 is same-direction.

### 1.4 Environments and weather (endless runs only)

`RunEnvironment` is "the living world of an endless run (issue #24): road geometry, weather, time of day, construction, and intersections, all as pure functions of (seed, distance)" (`lib/game/systems/run_environment.dart:142-144`). Dimensions:

| Axis | Values | Where |
|---|---|---|
| Time of day | 4: day, dusk, night, dawn | `run_environment.dart:7`, `:702-709` |
| Weather | 3: clear, rain, fog | `run_environment.dart:10` |
| Road profile | 3: standard 200 px / 2 lanes, narrow 148 px / 2 lanes, avenue 264 px / 3 lanes | `run_environment.dart:86-99` |
| Construction | per-segment cone lanes, 600–1,100 px of cones, rolled `0.20 + 0.30·ramp` | `run_environment.dart:812-857` |
| Intersections | cross streets every 9,000 px, band ±160 px; no traffic spawns inside | `run_environment.dart:199-203`, `:901-907` |

Key tuning constants: one full day of driving is 60,000 px, so "the median shift (2-4 km) departs in daylight and drives into dusk or night" (`run_environment.dart:190-192`); full night darkness 0.82 (`:194-196`); the opening 8,000 px is always standard daylight street ("the calm open", `:210-216`). Rain rises `0.22 + 0.10·ramp` of weather segments, fog `0.14 + 0.08·ramp` (`:639-651`). Weather folds into the **same** difficulty curve: rain +0.06, fog +0.07, night +0.09 pressure, capped at +0.25 (`:221-233`); physical costs are 30% lateral grip loss in full rain and 35% sight distance in full fog (`:236-241`, `:670-678`). The difficulty curve itself is a slow ramp with a relief wave: full ramp at 52,000 px, creep to 240,000 px, relief pulse every 4,200 px at depth 0.42, online after 6,000 px (`lib/game/systems/difficulty_curve.dart:99-125`).

### 1.5 Fare kinds — 4

`enum FareType { standard, vip, longHaul, awkward }` (`lib/models/fare_type.dart:18-35`). "Every fare is one of four kinds, and the kind changes the deal — what it pays, how long the meter runs, and what it does to the chain on time — so each pickup is a small decision: take it, or drive past." (`:5-9`).

| Kind | Coin multiplier | Time scale | Chain bonus | Share of fares | Colour / label |
|---|---:|---:|---:|---:|---|
| standard | 1.0 | 1.0 | 0 | 70% | green / "FARE · N c" |
| vip | 3.0 | 0.6 | 0 | 10% | amber / "VIP ×3" |
| longHaul | 1.0 | 1.0 | +2 steps | 10% | deep purple / "LONG HAUL" |
| awkward | 1.5 | 0.8 | 0 | 10% | orange / "FAR SIDE" |

Multipliers `fare_type.dart:40-45`; time scales `:52-57`; chain bonus `:63-66`; shares `:108-110` ("One fare in ten is a VIP, one a long-haul, one an awkward crossing; the other seven are the everyday rides"); draw order `:114-122`. Geometry is bent by kind: a long-haul gets the whole slot (`longHaulRideLength = slotLength − slotTailMargin − minPickupInset` = 1,100 px, `lib/game/systems/endless_course.dart:104-110`), an awkward fare forces a far-kerb dropoff with the shortest ride (551 px, `:112-119`, `:233-238`).

### 1.6 Achievements — 15

Catalog: `AchievementCatalog.all` lists 15 defs in records-screen order (`lib/models/achievements.dart:225-243`). Every achievement is "measure reaches threshold" (`:50-53`). Conditions as shipped:

| # | id | Title | Threshold | Condition |
|---|---|---|---:|---|
| 1 | chain_3 | HOT STREAK | 3 | ×3 fare chain in one shift |
| 2 | chain_5 | CHAIN ARTIST | 5 | ×5 fare chain in one shift |
| 3 | chain_8 | CHAIN MASTER | 8 | ×8 fare chain in one shift |
| 4 | distance_1000 | KNOWING THE STREETS | 1,000 | 1 km in a single shift |
| 5 | distance_3000 | MARATHON SHIFT | 3,000 | 3 km in a single shift |
| 6 | distance_5000 | CROSS-TOWN LEGEND | 5,000 | 5 km in a single shift |
| 7 | bank_clean_1 | SCOT-FREE | 1 | bank a shift with no life lost |
| 8 | bank_clean_5 | SURE HANDS | 5 | five such banks |
| 9 | bank_clean_15 | THE HOUSE ALWAYS WINS | 15 | fifteen such banks |
| 10 | cars_2 | TWO-CAB OPERATION | 2 | own 2 cars |
| 11 | cars_4 | FLEET BUILDER | 4 | own 4 cars |
| 12 | cars_7 | FULL FLEET | 7 | own every car in the garage (7) |
| 13 | streak_3 | HABIT FORMING | 3 | Daily Shift 3 days in a row |
| 14 | streak_7 | WEEKLY GRIND | 7 | Daily Shift 7 days in a row |
| 15 | streak_30 | MONTH ON THE METER | 30 | Daily Shift 30 days in a row |

Definitions `achievements.dart:104-223`; car thresholds count the 7-car fleet ("Thresholds count the fleet as shipped: 7 vehicles in the garage", `:176-178`). The clean-bank measure is a stored lifetime counter, deliberately never trimmed by the 200-shift window (`:22-29`, `lib/models/personal_bests.dart:99-106`). Daily streak is computed from the stored daily history as the longest run of consecutive `yyyy-MM-dd` keys (`achievements.dart:264-292`).

### 1.7 Every records / stats surface

| Surface | What it shows | Where it is defined / fed |
|---|---|---|
| Main menu | `BEST {endlessBestScore}` under ENDLESS SHIFT, only when > 0 | `lib/ui/screens/main_menu_screen.dart:291-301`; `lib/models/save_data.dart:32` |
| Main menu daily card | Today's result score/outcome, or "unplayed"; DAILY HISTORY link while unplayed | `main_menu_screen.dart:336-407`; `lib/ui/screens/daily_screen.dart:149-256` |
| Records screen — Personal bests | 4 rows: Best banked score, Longest chain (×N), Furthest distance, Most fares in one shift | `lib/ui/screens/records_screen.dart:113-136` |
| Records screen — Achievements | "N of 15 earned" plus all 15 cards; locked ones show progress toward threshold | `records_screen.dart:159-256`; `lib/services/game_state_service.dart:85-86` |
| Stats screen — Totals | 6 lifetime rows: Shifts ended, Total score, Distance driven, Fares delivered, Lives lost, Time driven | `lib/ui/screens/stats_screen.dart:154-170`; `lib/models/lifetime_run_totals.dart:24-51` |
| Stats screen — Typical shift | Median score, median distance, median duration (window-scoped) | `stats_screen.dart:173-183`; `lib/models/run_stats.dart:123-137` |
| Stats screen — Run lengths | 5 bands: Under 500 m, 500 m–1 km, 1–2 km, 2–4 km, Over 4 km, with counts and bars | `stats_screen.dart:186-207`; `run_stats.dart:226-232` |
| Stats screen — Bank or push | Banked count, wrecked/forfeited count, banked share | `stats_screen.dart:210-216`; `run_stats.dart:139-151` |
| Run summary panel | Outcome banner (bank +N Coins / forfeited N coins), PB banner, achievement banners, and rows: Score, Best chain, Fares delivered, Close calls, Distance, Coins earned | `lib/ui/widgets/run_summary_panel.dart:116-171`, `:276-281`; `lib/game/systems/run_summary.dart:11-68` |
| Daily screen | Today's score + banked/wrecked, PLAY/RACE YOUR GHOST, history list | `daily_screen.dart:149-256`, `:324-369`, `:443-479` |
| Player records storage | 5 personal bests (best banked score, longest chain, furthest distance px, most fares, clean banked shifts) | `personal_bests.dart:31-61` |
| Shift history | fixed window of 200 `RunRecord`s (endedAt, distance, score, fares, near misses, longest chain, lives lost + distances, banked, duration) | `game_state_service.dart:22`; `lib/models/run_record.dart:15-71` |
| Daily history | one `DailyResult` per day, window of 400 (dateKey, score, banked, completedAt) | `game_state_service.dart:26-28`, `:442-451`; `lib/models/daily_result.dart:13-37` |
| Ghost trace | one stored trace for one day only: dateKey, score, banked, vehicleId, flat `[x,y]` samples every 0.2 s, cap 2,400 pairs (~8 min, ~25 KB) | `lib/models/ghost_trace.dart:22-84` |

Notes: `cleanBankedShifts` is the fifth personal best but is not one of the four rows on the Records screen — it surfaces only through the bank-clean achievements' progress. The 6 Totals rows are lifetime counters; the medians, run-length bands and bank-vs-push counts are scoped to the 200-shift window (`run_stats.dart:14-23`).

### 1.8 On-device-only claim (spot check)

A `grep` for `dart:io|package:http|HttpClient|Socket|url_launcher` across `lib/` matches only `lib/services/audio_service.dart:2` (`import 'dart:io' show Directory, File;`). No HTTP client, socket, or URL launcher is used in `lib/`, consistent with the "progress is on-device only / makes no network calls" claim in `CLAUDE.md`. (The full app also has no analytics, no ads, no IAP by inventory; that was not separately audited here.)

---

## 2. The interlocking loops, with entry points

### 2.1 Minute one — the tutorial ladder

- Entry: the menu's `play_button`, labelled START DRIVING while the ladder is unfinished and PLAY once it is (`main_menu_screen.dart:238-261`). It pushes `GameScreen` with no daily seed: level mode.
- Ten rungs, one crash fails a level, completion unlocks the next (`taxi_game.dart:1449-1461` unlock via `gameState.completeLevel`, `game_state_service.dart:363-366`). The ladder teaches "hold-and-steer, pickup and dropoff, the fare timer, the chain multiplier, and finally banking — after which the game hands off to an endless shift" (`level.dart:7-12`).
- Rungs 9–10 (`Bank It`, `Graduation Shift`) enable the bank prompt (`assets/levels/level_009.json`, `level_010.json`), so "a new player reaches Endless having already made the choice" (`level.dart:23-30`).
- After rung 10 the completion panel's button calls `startFirstShift()` and starts an endless run in the same session (`taxi_game.dart:1463-1496`).

### 2.2 The shift loop (endless) — fare, chain, bank-or-push

1. A shift is a fresh seed; the seed fully determines the course, sky, weather (`taxi_game.dart:263-268` comment; `daily_shift.dart:12-16`).
2. Fares are dealt one per 1,400 px slot (`endless_course.dart:75-77`); a pickup waits on the kerb; delivering pays coins **immediately** (`taxi_game.dart:1050-1059`), and a timer sized to the ride starts at pickup (`fare_chain.dart:197-213`).
3. The chain: an on-time delivery scores `fareValue × multiplier` and steps the multiplier up; a late one pays ×1 and breaks the chain back to 1x; a zero-crossing expiry also breaks it once, on the frame it happens (`fare_chain.dart:215-240`, `:285-304`).
4. Near-misses ride the same chain: a cleared pass inside the award window at speed pays `nearMissScore (15) × multiplier` into the same at-risk score, never touching the multiplier itself (`fare_chain.dart:98-104`, `:251-270`; windows in `near_miss.dart:40-87`: edge-to-edge gap −9…14 px, forward speed ≥ 95 px/s).
5. Crashes: severity needs closing ≥ 110 px/s along the impact axis **and** positive player contribution; struck-from-behind is at most a scrape (`collision_rules.dart:174-194`, `:239-245`). A scrape keeps 35% speed and pushes 3 px clear; it costs no life (`collision_rules.dart:189-194`). A crash spends one of three lives, breaks the chain, keeps the banked-at-risk score, and freezes the world for a 1.2 s stall (`taxi_game.dart:1604-1654`, `lib/game/systems/lives.dart:12-15`).
6. Every dropoff arms the bank-or-push prompt for 5.0 s; the default resolution is push (`lib/game/systems/bank_prompt.dart:32-36`, `:62-73`). To choose otherwise the player taps BANK: "the accumulated score becomes permanent — paid into the wallet 1:1 in coins — and the run ends" (`taxi_game.dart:1148-1151`, `:1206-1247`). Pushing adds +1 multiplier step on top of the delivery's step — and pays the same whether tapped, timed out, or driven straight through (`fare_chain.dart:242-249`; `taxi_game.dart:1189-1202`).
7. The third crash ends the shift and forfeits everything unbanked (`taxi_game.dart:1668-1671`). The pause menu's BANK & QUIT routes through the same bank path (`taxi_game.dart:1134-1146`).

### 2.3 The meta loop — coins to garage

- All income lands in one wallet: `totalCoins` (`save_data.dart:7`). Sources: endless fare deliveries (`taxi_game.dart:1058`), endless bank payout (`:1241`), level completion payouts (`_completeLevel` → `gameState.completeLevel` → `addCoins`, `:1444`; `game_state_service.dart:345-350`, `:363-366`).
- Spend: `unlockVehicle(vehicleId, cost)` spends and unlocks in one transaction (badge comment: "The spend and the unlock are one transaction (issue #230)"), refusing when `totalCoins < cost` (`game_state_service.dart:455-467`); owned cars can be selected (`:479-484`).
- Selection changes the car the physics drives: `VehicleCatalog.statsFor(id)` feeds handling (`vehicle_catalog.dart:198-201`), verified live by "garage choice reaches the road" in `test/vehicle_handling_test.dart`.
- Earnings context from the current table: a median-profile shift totals p25 5,505 / median 6,995 / p75 9,033 coins; the first car (5,000) is inside one median shift, the Executive (40,000) is ~4.4 median-good shifts (9,122) or ~5.7 median shifts (6,995). The catalog comment sizes them as "the first car costs two to three shifts, the mid fleet about a week of dailies, and The Executive is a real grind" (`vehicle_catalog.dart:76-80`) — the ladder's prices are unchanged, but the shipped instrument now prints higher per-shift totals than the in-code rationale quotes ("roughly 2,000 coins a shift for a first-session player, 2,300–3,000 for a competent one", `:74-77`; current medians 6,225 / 6,995 / 9,122). Flagging as a stale comment, not a code disagreement.

### 2.4 The daily loop — attempt, result, ghost

- Entry: the DAILY SHIFT button on the menu, which becomes TODAY'S RESULT after today's attempt is spent (`main_menu_screen.dart:306-341`); a DAILY HISTORY link shows while today is unplayed (`:391-407`).
- The course is date-seeded, computed locally: seed = a pure hash of `yyyy-MM-dd` (`daily_shift.dart:35-73`), so "every player in the world gets the identical course on the same day" with no server, and "the daily shift **is** an endless shift ... the same endless ramp, shared seed" (`daily_shift.dart:5-19`).
- One attempt per day: the attempt is spent when the shift ends, banked or wrecked (`taxi_game.dart:1277-1289` comment: "a shift abandoned to the menu never ends, and so never spends the attempt"). The day's result stores score + banked + timestamp, one per date key (`game_state_service.dart:442-451`; `daily_result.dart:13-37`).
- Ghost: a finished daily-course run offers its path; a trace is stored only if it beats the current ghost's score ("a tie keeps the older ghost"), replacing an earlier day's trace outright (`game_state_service.dart:196-225`, `ghost_trace.dart:14-17`). After the attempt, RACE YOUR GHOST reruns the same course with the translucent best run (`taxi_game.dart:1348-1377`); the race never touches the settled result and keeps the better score (`taxi_game.dart:110-117` comment).
- The ghost is sampled on **driven** time (crash stalls excluded) at 0.2 s, cap 2,400 pairs (`ghost_trace.dart:32-42`, `:62-76`).
- Daily streaks feed the three streak achievements via the daily history (`achievements.dart:264-292`).

### 2.5 Where the loops connect — and where they do not

| Connection | Evidence |
|---|---|
| Ladder → endless: rungs 9–10 teach the real bank-or-push prompt; level 10 hands off to a live endless run in-session | `level.dart:23-30`; `taxi_game.dart:1488-1496` |
| Daily = endless rules on a pinned seed; daily results also enter the endless shift history | `daily_shift.dart:12-16`; `taxi_game.dart:1261-1289` (`recordEndlessRun` runs for every endless ending, and `recordDailyResult` additionally when `isDailyShift`) |
| Both modes pay the same wallet, and the garage reads that wallet | `taxi_game.dart:1058`, `:1241`, `:1444`; `game_state_service.dart:455-467` |
| Achievements read the interlocking outputs: bests, clean banks, owned cars, daily streaks | `achievements.dart:8-48`, `:104-292` |
| Run summary is the one place a shift's score, chain, close calls, distance and coins are reported together; it also drains newly earned achievements | `taxi_game.dart:1291-1308`; `run_summary_panel.dart:276-281` |

| Disconnection | Evidence |
|---|---|
| Level runs never write a `RunRecord` and never appear in the stats screen — only endless endings call `_finalizeRunSummary`, "the on-device record of one ended endless shift" | `taxi_game.dart:1249-1260` ("Only ever reached from the endless endings"); `run_record.dart:3-10` |
| Free play never records or shows a ghost; the trace is only ever attached to a daily course, "Endless free play is freshly seeded every shift, so a trace recorded there would compare two different roads" | `ghost_trace.dart:7-12`; `taxi_game.dart:1310-1318` (`_ghostDateKey` null for free play) |
| No vehicle changes payouts: fare rewards are computed from the course and fare kind only; the garage is purely handling + cosmetics | `endless_course.dart:329-334`; `vehicle_catalog.dart:15-46` |
| No leaderboard/network comparison exists; the daily's comparison is social by screenshot, and progress is local-only | `daily_shift.dart:5-10`; `daily_result.dart:3-4` |
| The ladder is linear and not replay-gated by performance beyond completion (a first crash simply restarts the level) | `taxi_game.dart:1449-1461` |
| Garage purchases do not gate or unlock content other than the cars themselves and the 3 car-count achievements | `game_state_service.dart:455-489`; `achievements.dart:176-199` |

---

## 3. Economy constants table (from code)

### 3.1 Coins per fare (endless)

Formula (`endless_course.dart:329-334`):

```dart
final baseReward = 20 + (rideLength / 30).round() + rewardBonus;
final reward = (baseReward * fareType.rewardMultiplier).round();
```

- `rewardBonus` is a per-fare draw `random.nextInt(16)` → 0–15 (`endless_course.dart:215`).
- `rideLength` is drawn 550–850 px, grows up to +125 px with the difficulty ramp, is capped to the slot tail, and is re-read post-junction-nudge (`endless_course.dart:91-94`, `:217-220`, `:301-303`). Long-haul = 1,100 px exactly (`:104-110`); awkward = 551 px (`:112-119`).
- Resulting standard fares ≈ **38–68 coins** (comment: "~40–70 coins a standard fare", `:329-332`); VIP ×3, awkward ×1.5, long-haul ×1.
- Level fares instead pay `coinReward ~/ pickupPoints.length` per delivery (`taxi_game.dart:907`).

### 3.2 Fare timer budget (feeds whether a fare is on time)

| Term | Pressure 0 (levels / run start) | Pressure 1 (deep endless) | Scale |
|---|---:|---:|---|
| Flat allowance | 6.0 s | 4.0 s | × `FareType.timeScale` |
| Per-px | 1/75 s/px | 1/85 s/px | × timeScale |
| Floor | 8.0 s | 7.0 s | × timeScale |
| Ceiling | 25.0 s | 18.0 s | × timeScale |

`fare_chain.dart:70-86`, `:141-159`; VIP's 0.6 and awkward's 0.8 time scales (`fare_type.dart:52-57`). "No fare is unwinnable at any distance" at the worst ride (`fare_chain.dart:128-132`).

### 3.3 Chain multiplier behavior

| Event | Effect | Where |
|---|---|---|
| On-time delivery | score += reward × multiplier; multiplier += 1 (+2 extra for long-haul) | `fare_chain.dart:226-240`; `fare_type.dart:63-66` |
| Late delivery | score += reward × 1; multiplier resets to 1 | `fare_chain.dart:231-236` |
| Timer crosses zero while aboard | multiplier resets to 1, once, on the crossing frame | `fare_chain.dart:293-304` |
| Push on at a dropoff (tap, timeout, or driving straight through) | multiplier += 1 | `fare_chain.dart:92-96`, `:242-249`; `taxi_game.dart:1189-1202` |
| Crash | multiplier resets to 1; banked-at-risk score untouched | `fare_chain.dart:277-283`; `taxi_game.dart:1622-1623` |
| Near-miss | +15 × multiplier into score; multiplier untouched | `fare_chain.dart:251-270` |

Best chain is tracked separately and never falls (`fare_chain.dart:113-116`).

### 3.4 Near-miss economy

- Award: 15 points × live multiplier (`fare_chain.dart:104`, `:265-270`).
- Qualifying pass: edge-to-edge lateral gap > −9 px and ≤ 14 px, forward speed ≥ 95 px/s, no contact this episode, judged once per vehicle at the pass, both directions of thread counted (`near_miss.dart:40-87`). Payouts land in the same at-risk-until-banked score as fares (`fare_chain.dart:251-258`).

### 3.5 Crash and scrape penalties

| Event | Cost | Where |
|---|---|---|
| Scrape | speed ×0.35, pushed 3 px clear, no life, no chain break | `collision_rules.dart:189-194` |
| Crash threshold | closing ≥ 110 px/s along impact axis **and** player contribution > 0 | `collision_rules.dart:182-187`, `:239-245` |
| Endless crash | −1 life (of 3), chain → 1x, 1.2 s world freeze, score survives at risk | `taxi_game.dart:1604-1654`; `lives.dart:12-15` |
| Third endless crash | shift ends; everything unbanked forfeit; nothing paid | `taxi_game.dart:1668-1671` |
| Level crash | first crash fails the level ("the level-fail behaviour") | `taxi_game.dart:1498-1507` |
| Risky play | LEVEL-bank in a banking rung pays the chain score and forfeits the flat reward; pushing to level completion pays `max(score, flatReward)` on those rungs, else the flat reward | `taxi_game.dart:1427-1444` |

### 3.6 Bank payout and prompt

| Item | Value | Where |
|---|---|---|
| Bank payout | chain score → coins, 1:1, ends the shift | `taxi_game.dart:1148-1151`, `:1206-1247` |
| Prompt window | 5.0 s; default resolution is push | `bank_prompt.dart:32-36`, `:62-73` |
| Primer | the save's first-ever offer is the only one that freezes traffic | `taxi_game.dart:1074-1106` |
| Per-fare coins | paid at delivery, before any bank; earned however the shift ends | `taxi_game.dart:1050-1059`; `shift_earnings.dart:57-61` |
| Wrecked shift | fares already paid stay; chain score forfeit | `taxi_game.dart:1668-1671` |

### 3.7 Garage prices

0 / 5,000 / 7,500 / 12,000 / 16,000 / 24,000 / 40,000 coins for Classic Cab → City Compact → Street Sedan → Family Minivan → Trail SUV → Night Racer → The Executive (`vehicle_catalog.dart:103-188`, price lines `:107`, `:119`, `:131`, `:143`, `:155`, `:167`, `:179`). Purchase is one transaction (`game_state_service.dart:455-467`).

---

## 4. Cross-checks and observations

1. **The economy table's "median shift" km is a mean.** `test/economy_simulation_test.dart:62` accumulates `run.distancePx / 10000` and `:83` divides by `runCount`. My probe prints the actual medians with the same simulator and seeds: 3.0 / 3.7 / 5.7 km vs the table's 2.9 / 3.6 / 6.2 km. The good-driver gap (5.7 median vs 6.2 mean) is one long tail of runs.
2. **The run-length suite prints no per-skill table at this commit** (no `print(` in the file; 12 assertions pass). Any per-skill minutes/km figure therefore has to come from the probe; the shipped suite only pins the default profile's median band (2–4 km) and the fairness profile.
3. **The run-length suite's default profile is the "median" stand-in and it lands at 3.7 km median — inside its 2–4 km band** (probe output; band comment `test/run_length_simulation_test.dart:19-28`).
4. **The garage rationale in `vehicle_catalog.dart:69-81` quotes older, lower per-shift earnings** (~2,000 first-session / 2,300–3,000 competent) than the current instrument's shift totals (median 6,225 / 6,995 / 9,122). With prices unchanged, the first car and mid fleet are cheaper in real terms than the comment describes; the Executive remains the long grind.
5. **Levels do not appear in stats, and free play has no ghost** — two deliberate asymmetries of scope worth knowing before any "records" work: `_finalizeRunSummary` is endless-only by contract, and `_ghostDateKey` is null outside daily-course runs.

---

## 5. Unverified

- The App Store 1.0.0 rejection under Guideline 4.3(a) Design Spam and the TestFlight-only pipeline: stated in the brief; not verified in this worktree (no App Store Connect call was made, per the read-only constraint).
- "No ads, no IAP": not audited. The `pubspec.yaml` dependency list was not reviewed for ad/IAP packages; the only direct check was that `lib/` contains no HTTP/socket/url-launcher imports.
- The claim "every asset under `assets/audio/` is named in LICENSES.txt" and other audio/licensing assertions: not audited in this slice.
- Exact per-fare reward distributions in live play (declines of VIP/awkward offers are possible but unmodelled in `ShiftEarnings`, per `shift_earnings.dart:28-38`); the simulation is deliberately "optimistic" on that axis and "conservative" on meter reading. Real-player wallet is bounded between the floor and the ceiling, not measured.
- Per-level playtime, churn, retention, or fun: nothing on device or in the repo measures these (the game ships no analytics, by design).
- My probe's exact minutes rest on the simulator's reflex driver, not human players; it is the same stand-in the shipped suite and economy table use, and is labelled as such.
