# Verification pass — three numeric claims (issues #266, #270, #271)

Read-only measurement pass. Repo read: `C:\git\repos\taxiGame-pm` (taxiGame worktree).

Provenance note: HEAD is `daab300e16ac54717d46895892dde019f864b9cd` on `product/future-map-20261010`, one commit past `c51460928fd3796a77e1fdd6a4959aea529f0858` (the commit named in the brief; `git log -3` shows it as daab300's parent). `git diff --stat c514609..daab300` touches only `docs/app-review/2026-10-08-4.3a-response.md`, `taxi_game/fastlane/review_notes.txt`, and `taxi_game/tool/screenshot_entry.dart` — none of the evidence files — so the findings apply to both commits. Working tree clean.

---

## Claim 1 — issue #266: level 1's only pickup intersects just the outer 20 px of the cab's reachable range; a centre-line first drive misses it and ends in FARE MISSED

### Evidence (exact lines)

- `taxi_game/assets/levels/level_001.json:5-7` — the level's only pickup:
  ```json
  "pickupPoints": [
    [315, 400]
  ],
  ```
  (dropoff `[315, -300]`, line 9; one pickup in the file.)
- `taxi_game/lib/game/taxi_game.dart:491-493` — road geometry:
  ```dart
  // The road spans x 100..300 in world coordinates (center 200, width 200).
  static const double roadCenterX = 200;
  static const double roadWidth = 200;
  ```
- `taxi_game/lib/data/vehicle_catalog.dart:108-114` — the starter cab (Classic Cab, id `taxi_yellow`): `width: 40`, `height: 60`. `taxi_game/lib/models/save_data.dart:73` — default save: `selectedVehicle: 'taxi_yellow',`.
- `taxi_game/lib/game/components/player_vehicle.dart:147` — `final halfWidth = vehicleSize.x / 2;`; `:159-161` — level clamp `minX = TaxiGame.roadCenterX - TaxiGame.roadWidth / 2 + halfWidth;` / `maxX = TaxiGame.roadCenterX + TaxiGame.roadWidth / 2 - halfWidth;`; `:163` — `final clampedX = position.x.clamp(minX, maxX);` (level mode uses this fixed branch; `env` is endless-only).
- `taxi_game/lib/game/systems/collision_rules.dart:176` — `static const double playerHitboxScale = 0.75;`; `player_vehicle.dart:102-106` — hitbox `size: vehicleSize * CollisionRules.playerHitboxScale` (centred on the cab).
- `taxi_game/lib/game/components/pickup_zone.dart:31-32` — `static const double baseRadius = 30.0;` (drawn marker, pulses ±5) and `static const double detectionRadius = 40.0;`; `:49-53` — the detection `CircleHitbox(radius: detectionRadius, ...)` centred on the pickup position.
- Collision pathway is live: `taxi_game.dart:59` — `with HasCollisionDetection`; flame 1.34.0 `RectangleHitbox`/`CircleHitbox` default `CollisionType.active` (pub cache source, checked because no repo code sets it), so the pickup circle and cab rectangle are both active.
- `taxi_game/lib/game/taxi_game.dart:844,860-863` — start: `playerStartY = lowestPointY + 250` (= 650) and `PlayerVehicle(startPosition: Vector2(roadCenterX, playerStartY), ...)` — x = 200, the centre line.
- `taxi_game/lib/game/taxi_game.dart:1565-1577` — stranded-fare fail: `if (playerY < neededY - EndlessFareController.passHysteresis) { _failLevelForMissedFare(); ... }`; `endless_fare_controller.dart:113` — `static const double passHysteresis = 80.0;`; `lib/ui/screens/game_screen.dart:653` — the failing panel prints `'FARE MISSED!'`.

### Arithmetic (starter cab, the default car on level 1)

- Reachable range of the cab **centre**: halfWidth = 40 / 2 = 20 → minX = 200 − 100 + 20 = **120**, maxX = 200 + 100 − 20 = **280**.
- Cab hitbox: 0.75 × (40×60) = 30×45 px, centred on the cab centre → **half-width 15 px**.
- Pickup detection circle: centre x = 315, radius 40 → **x-extent [275, 355]**.
- Registration condition at the pickup's y: shapes overlap while |315 − cabX| ≤ 40 + 15 = **55**, i.e. cab centre x ∈ [260, 370]; intersected with the reachable [120, 280] gives the band **[260, 280] — exactly the outer 20 px of the reachable range**.
- Same result read as extents: circle [275, 355] vs reachable cab-hitbox extent [105, 295] → overlap [275, 295] = **20 px**.
- Centre-line drive: cab x = 200 → 115 px centre-to-centre; at closest the cab's right hitbox edge (215) sits **60 px clear** of the circle's left edge (275). It never touches, at any y. Once `y < 400 − 80 = 320` the stranded-fare check fails the level → **FARE MISSED!** (no pickup ever fired).
- Robustness across the fleet: band width = 25 − 0.125·w px (derived from the same clamp + 0.75 hitbox scale) → Classic Cab **20.0**, City Compact 20.75, Street Sedan 20.0, Family Minivan 19.0, Trail SUV 19.25, Night Racer 20.5, The Executive 19.25. The claim's 20 px is exact for the starter; the mechanism holds for every car at 19–20.75 px.

### Verdict
**CLAIM HOLDS.** The pickup registers only for cab centres in [260, 280] — the outer 20 px of the reachable [120, 280] — so a centre-line (x = 200) first drive passes 60 px clear and, past y = 320, fails the level with FARE MISSED!.

---

## Claim 2 — issue #270: close call pays 15 points × live multiplier; award window −9 to 14 px at ≥ 95 px/s; once per vehicle

### Evidence (exact lines)

- `taxi_game/lib/game/systems/near_miss.dart:48` — `static const double gapThreshold = 14.0;` (px; "Largest edge-to-edge lateral gap (px) at which a cleared pass is a close call", comment lines 40-47).
- `taxi_game/lib/game/systems/near_miss.dart:56` — `static const double contactSlack = 9.0;` (px; "Deepest logical overlap (px) a cleared pass may sit at and still count", comment lines 50-55).
- `taxi_game/lib/game/systems/near_miss.dart:61` — `static const double minPassSpeed = 95.0;` (px/s; "Slowest taxi forward speed (px/s) at which a pass can score", pinned to `ImpactFx.speedLinesStartSpeed`).
- `taxi_game/lib/game/systems/near_miss.dart:84-86` — the predicate:
  ```dart
  return gap > -contactSlack &&
      gap <= gapThreshold &&
      playerForwardSpeed >= minPassSpeed;
  ```
- `gap` units and sign: `near_miss.dart:63-74` — edge-to-edge distance along x between the two logical bodies, negative on overlap; "the award window runs from -[contactSlack] (a hitbox-miss interleave) to [gapThreshold]".
- `taxi_game/lib/game/systems/fare_chain.dart:104` — `static const int nearMissScore = 15;`; `:265-269` — `int awardNearMiss() { nearMisses++; final points = nearMissScore * multiplier; score += points; return points; }`.
- Speed actually passed: `taxi_game/lib/game/taxi_game.dart:1802-1805` — `playerForwardSpeed: -player.velocity.y,` (forward, up-screen speed); award at `:1808` `final points = fareChain.awardNearMiss();`.
- Once per vehicle: `taxi_game/lib/game/components/traffic_vehicle.dart:87` — `bool _nearMissJudged = false;`; `:455-463` — `_updateNearMissWatch()` sets `_nearMissJudged = true` at the first pass moment (line 459) and awards only `if (!contactedPlayer)` (line 460); the flag never re-arms and is called every frame from `update()` at `:290`. A touched vehicle is disqualified: `player_vehicle.dart:426-430` sets `other.contactedPlayer = true` at the start of any contact episode.

### Claim vs code

- "15 points times the live multiplier": exact — base constant 15, payout `nearMissScore * multiplier` into the run score.
- "Award window is −9 to 14 pixels": true as the interval **(−9, 14]**. `gap = -9` exactly does **not** score (`gap > -contactSlack` is strict); `gap = 14` exactly **does** (`gap <= gapThreshold` is inclusive). The values −9 and 14 are `-contactSlack` and `gapThreshold` in px of edge-to-edge clearance (negative = logical overlap).
- "At a speed of at least 95 px/s": exact — `playerForwardSpeed >= minPassSpeed` with the forward speed `-velocity.y`.
- "Once per vehicle": exact — one judgement per vehicle instance, whichever way it rules; contact disqualifies but still consumes the single judgement.

### Verdict
**CLAIM HOLDS.** Every constant and mechanism is exact: 15 pts × live multiplier; window gap ∈ (−9, 14] px; forward speed ≥ 95 px/s; one judgement per vehicle. Only refinement: the −9 endpoint is strictly excluded (14 is inclusive), so the precise predicate is `-9 < gap ≤ 14 && speed ≥ 95`.

---

## Claim 3 — issue #271: the garage-pricing comment quotes a coins-per-shift figure that disagrees with what the economy simulator prints

### The comment

`taxi_game/lib/data/vehicle_catalog.dart:69-76`:
```
/// Prices are sized against the **endless** economy (issue #34): a shift
/// pays its fares on delivery and banks the chain score 1:1, and the
/// instrument behind `test/economy_simulation_test.dart` measured the
/// result at 1,240–1,584 coins of fares alone per shift (p25–p75 across
/// three skill stand-ins) before banking — a competent banked shift lands
/// well past the audit's 800–2,000 figure. The ladder is priced off the
/// conservative wallet those floors imply: roughly 2,000 coins a shift
/// for a first-session player, 2,300–3,000 for a competent one.
```
Comment's coins-per-shift figure: **1,240–1,584** (fares alone, labelled p25–p75 across stand-ins), plus a wallet of **~2,000** (first-session) / **2,300–3,000** (competent).

### Garage prices and sum

Prices at `vehicle_catalog.dart:107,119,131,143,155,167,179`:
`0 + 5,000 + 7,500 + 12,000 + 16,000 + 24,000 + 40,000 = 104,500` coins for the full seven-car garage (starter is 0).

### Command line and printed output

Command (run in `C:\git\repos\taxiGame-pm\taxi_game`):
```
flutter test test/economy_simulation_test.dart --reporter expanded
```
Printed output (deterministic 101-seed batch, seeds 1000..1100, starter cab), verbatim:
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
00:10 +2: All tests passed!
```
Footnote on the print: the km figure on the "median shift" lines is `totalKm / runCount` — a **mean**, not a median (`economy_simulation_test.dart:62` accumulates `totalKm`, `:83` prints `(totalKm / runCount)`); the fares/chain figures on those lines are medians. The printed label is wrong for the km; it is not repeated in the analysis below.

### Comment vs print, side by side

Fares alone — the comment's basis — per profile, p25–p75:
| source | new | median | good |
|---|---|---|---|
| comment (one band "across three skill stand-ins") | **1,240–1,584** | | |
| printed fares-only floor | 1,033–1,400 | 1,263–1,737 | 1,850–2,926 |

Shift totals as printed (fares + brink bank), p25 / median / p75:
| source | new | median | good |
|---|---|---|---|
| comment's wallet figures | **~2,000** (first-session) | — | **2,300–3,000** (competent) |
| printed shift total | 5,055 / 6,225 / 8,096 | 5,505 / 6,995 / 9,033 | 7,115 / 9,122 / 12,018 |

### Implied shifts to buy the full garage (104,500 coins)

- Under the comment's figure: 104,500 / 1,240 = 84.3 → **85 shifts**; 104,500 / 1,584 = 66.0 → **66 shifts**. Under the comment's wallet: ~2,000 → **53**; 2,300 → **46**; 3,000 → **35**.
- Under the printed **shift totals** (p25 / median / p75): new **21 / 17 / 13** shifts; median profile **19 / 15 / 12**; good **15 / 12 / 9**.
- Under the printed **fares-only floors** (p25 / median / p75): new **102 / 86 / 75**; median **83 / 69 / 61**; good **57 / 46 / 36**.

### Provenance of the quoted 1,240–1,584 (context from git history)

The re-ladder commit that added the comment (`d861dd3`, "fix: price the garage against endless earnings and end the tutorial bank double-dip") lists its own batch's fares floors: new `1020/1240/1428`, good `1358/1584/1816`. So 1,240 is that batch's **new-profile median** floor and 1,584 the **good-profile median** floor — the comment's "(p25–p75 across three skill stand-ins)" mislabels its own endpoints. Today's run prints different values again (new floor median 1,220; good floor median 2,299), and the good profile's current entire p25–p75 band (1,850–2,926) sits above the comment's quoted top (1,584).

### Verdict
**CLAIM HOLDS.** Every quoted coins-per-shift figure disagrees with the current simulator print: 1,240–1,584 matches no current per-profile fares-only band (the current spread runs 1,033–2,926, and its quoted top is below the good profile's p25), and the comment's ~2,000/2,300–3,000 wallet is ~2.5–4× below the printed shift totals (5,055–12,018). Buying the full 104,500-coin garage takes ~66–85 shifts at the comment's figure versus ~9–21 shifts at the printed totals.

---

## Unverified

- The issue texts for #266, #270, #271 were not read (not available in this pass); only the paraphrased claims were verified.
- Whether any historical batch ever printed "1,240–1,584" as an honest p25–p75 band: no historical run output is checked into the repo. The re-ladder commit message's numbers (1240 = new median, 1584 = good median) indicate the pair are medians, but the raw old print could not be reconstructed.
- The brief named commit `c514609`, while the worktree's HEAD is its child `daab300`; none of the evidence files differ between the two commits (diff touches only docs/fastlane/screenshot-tool files), so the three verdicts stand for both revisions.

Correction appended at handback: claim 2 supports issue #269 (the close-call lesson). Issue #270 consumes the same constants through the settlement surface. The posted comment went to #269 correctly.
