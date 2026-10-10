# W6 — Capability & Risk Scan — Cab Hustle (`taxiGame`)

Read from `C:\git\repos\taxiGame-pm`, worktree at main, commit `c514609` ("fix: make the UX exits re-entry safe, surface load failures, and report reset refusals (#240 #241 #242 #243 #244) (#259)"). Read-only: no edits, no builds, no `flutter` runs. Issue text read via `gh issue view` for #40, #94, #212, and #250–#257; all other claims cite path and line.

---

## Part 1 — Capability inventory

### 1.1 Game systems (`taxi_game/lib/game/systems`, 18 files)

All of the following are deliberately **pure logic, no Flame state** (each file's header says so), which is the single most important reuse property in the codebase: they run identically in the live game, in headless tests, and in the Monte-Carlo harness.

| System | What it does | Key cites |
|---|---|---|
| `CollisionRules` | Contact severity (scrape vs life) from closing speed on the impact axis and the player's share of it; `CrashReport` feeds FX, HUD, records | `collision_rules.dart:171`, `:25` |
| `DifficultyCurve` | Continuous pressure over distance: smoothstep ramp (`fullRampDistance = 52,000`), Gaussian relief wave (`waveLength = 4,200`), creep, traffic core, fare-timer pressure; environment modifier folds weather/night into the same curve | `difficulty_curve.dart:85`, `:99`, `:107`, `:204`, `:225` |
| `RunEnvironment` | The living world of an endless run, pure function of `(seed, distance)`: road width/lanes (`standard`/`narrow`/`avenue`), weather (`clear`/`rain`/`fog`), time of day (`day`/`dusk`/`night`/`dawn`), construction zones, cross streets, kerb positions, traffic containment + merge schedules | `run_environment.dart:164`, enums `:7–10`, `:86`, `weatherAt:623`, `timeOfDayAt:703`, `difficultyModifierAt:717`, `constructionInRange:794`, `junctionBandContains:893`, `hash01:921` |
| `EndlessCourse` | Deterministic fares as pure function of `(seed, index)`: slot of 1,400 px, pickup/dropoff side, ride length, reward, `FareType` (standard/long-haul/awkward/VIP), junction nudges, relocation hops; order-independent so the Daily Shift reproduces exactly | `endless_course.dart:62`, `:77`, `:205`, `:226`, `:255`, `:143` |
| `EndlessFareController` | Live frame for the course: spawns fares ahead of the taxi, culls passed ones | `endless_fare_controller.dart:37` |
| `FareChain` | Scoring backbone: per-fare countdowns, multiplier chain, push bonus, near-miss payouts, break-on-expiry-once | `fare_chain.dart:54`, `:141`, `:226`, `:265`, `:293` |
| `LivesTracker` | Three-strike budget; floors at zero | `lives.dart:11`, `:13`, `:30` |
| `BankPrompt` | Timed 5 s bank-or-push window; resolve-once semantics; default is push | `bank_prompt.dart:32`, `:35`, `:65` |
| `NearMissRules` | Close-call geometry: 14 px gap window, −9 px contact slack, 95 px/s speed floor; judged once per pass | `near_miss.dart:37`, `:48`, `:56`, `:61` |
| `RunLengthSimulator` | Headless Monte-Carlo shift rebuild of the live systems (spawning cadence, environment, physics, collision rulings, reflex driver); `RunLengthEstimate` medians/survival/hazard windows; `@visibleForTesting PresetTrafficVehicle` for pinned scenarios | `run_length_simulator.dart:230`, `:75`, `:107`, `:151`, `:195–229` |
| `ShiftEarnings` | Prices a simulated run under the live payout rules (fares, chains, brink bank) — the garage-ladder economy instrument | `shift_earnings.dart:48`; `economy_simulation_test.dart:8–31` |
| `GhostRecorder` / `GhostPlayback` | Position trace recorder/replayer on the driven-time clock; linear interpolation; bounded | `ghost_replay.dart:17`, `:48`; `ghost_trace.dart:35` (0.2 s grid), `:42` (2,400 pair cap ≈ 8 min / ~25 KB) |
| `RoadChunkManager` | Recycled 800 px road chunks around the camera; culls with cone children | `road_chunk_manager.dart:30`, `:38`, `:104`, `:144` |
| `WorldOrigin` | World-y folding every period so long runs stay numerically sound | `world_origin.dart:48` |
| `ImpactFx` (`ShakeEnvelope`, `HitStop`, palettes) | Crash feel: hit-stop, shake, particles | `impact_fx.dart:9`, `:117`, `:173` |
| `RunSummary`, `ScoreCardData`, `DailyShift` | Settled shift numbers; shareable card data; date-seeded daily with a test-pinnable clock and a frozen hash | `run_summary.dart:11`; `score_card.dart:16`; `daily_shift.dart:23`, `:33`, `:61` |

The run seed reaches everything: `TaxiGame` seeds the traffic spawner `math.Random(seed ^ 0x5EEDCAB5)` (`taxi_game.dart:748–749`), `RunEnvironment(seed)` and `EndlessCourse(seed)` are pure, and `freshSeed()` derives from the clock (`taxi_game.dart:244`). A shift is therefore reproducible from its seed plus the player's input trace — the property the Daily Shift and ghost already exploit.

### 1.2 Level and course generators

- **Tutorial ladder**: 10 hand-authored JSON levels (`taxi_game/assets/levels/level_001.json` … `level_010.json`), with `GameLevel.ladderLength = 10` held in sync by a test that loads the real assets (`level.dart:7–13`); the last rungs teach banking via `bankPromptEnabled` (`level.dart:23–30`). Levels steer traffic via `trafficPattern` JSON (`level.dart:75–81`). The loader checks the asset manifest, caches, and throws a typed `LevelLoadException` instead of substituting a test level (`level_loader_service.dart:54`, `:13`, `:91–107`).
- **Endless course**: procedural, deterministic, order-independent (`endless_course.dart:52–60`); draw order is documented as load-bearing (`:208`), and junction avoidance is pure band arithmetic with no fresh RNG so a seed's road is never rewritten (`:244–299`, `:351–357`).
- **Environment/weather/works**: `RoadProfile` per segment, weather per 4,400 px segment with 500 px fades, a 60,000 px day cycle, junctions every 9,000 px, construction zones — all hashed from `(seed, salt, index)` (`run_environment.dart:175–241`, `:274–286`, `:623–740`, `:794–831`).
- **Daily Shift**: `DailyShift.seedForDateKey` is an explicitly frozen hash — "once shipped it must never be 'improved'" (`daily_shift.dart:50–73`) — and the day key is local-calendar, not UTC.
- **Vehicles**: seven player vehicles with distinct handling stats and an invariant that no car strictly dominates (`vehicle_catalog.dart:15–46`, `:100–188`), enforced by `test/vehicle_handling_test.dart`.

### 1.3 Test suite: size and seams

- **Size**: 96 test files, ~30,096 lines; ~1,070 cases (866 `test(` + 205 `testWidgets(` as anchored matches), 262 `group(`s. Roughly 3:2 test-to-lib code (lib is 78 files / ~20,300 lines).
- **Headless live-game seam**: the dominant pattern mounts a real `TaxiGame`, drives it with real `update()` ticks, and drains component mounts — `mountGame` + `advanceGameTime` (`test/endless_run_test.dart:59–78`, `:85–104`; 26 test files use `mountGame`, 12 use `advanceGameTime`). Clamped frames mirror the production `maxUpdateDelta` (`taxi_game.dart:237`), so tests exercise the same time invariant the game runs under.
- **Pinned-scenario seam**: `PresetTrafficVehicle` injects exact cars before the first tick without perturbing the spawner's RNG stream (`run_length_simulator.dart:145–183`) — the only way to construct specific contacts deterministically.
- **Monte-Carlo tuning seam**: 101 seeds drive the simulator; thresholds pin the 2–4 km median band, early-death rate, survival fractions, hazard windows, and determinism (`test/run_length_simulation_test.dart:30–113`); a second harness prints the coins-per-shift tuning table for three skill profiles (`test/economy_simulation_test.dart:40–80`).
- **Fakes**: an in-memory prefs store whose writes/removes can fail, refuse, or park on a completer (`test/helpers/fake_prefs_store.dart:16–93`, `installFailingPrefsStore:100`); a full fake audioplayers platform that records every call, can add latency, and can make named calls throw (`test/helpers/fake_audio_platform.dart:15`, `:67–211`, `:217–257`); used by widget tests that pump live screens (15 files).
- **Widget tests**: 65 files / 205 widget cases pump real screens; screen tests, HUD tests, layout/hint/panel tests (`test/control_hint_test.dart`, `test/bank_or_push_test.dart`, `test/run_summary_screen_test.dart`, etc.).
- **Workflow/CI tests**: the release gate's Ruby script is executed from Dart through injected JSON fixtures, no network or credentials (`tools/asc_version_state.rb:69–74`; `test/release_submit_gate_test.dart`); shell guard blocks are extracted and pinned structurally (`test/helpers/workflow_guards.dart:16–50`).
- **Calendar seam**: daily tests walk calendar days at noon to avoid DST arithmetic bugs (`test/helpers/calendar_days.dart:27–36`).
- **Device-ish seam**: launch lifecycle probes fire real iOS scene sequences headlessly and are kept as permanent guards for issue #40 (`test/launch_lifecycle_probe_test.dart`, 166 lines; issue #40 body).

### 1.4 CI workflows (`.github/workflows`)

- **`flutter-builds.yml`** (PR checks + dispatch): analyze and test on macOS (`:54–58`); unsigned release iOS build (`:64–67`); bundle assertions — `UIDeviceFamily [1]`, min OS ≥ 15, privacy manifest present (`:69–84`); boot a simulator, install, launch, and assert the process is alive after 8 s — the only on-simulator runtime check (`:86–112`); Android is opt-in behind `workflow_dispatch` (`:114–154`).
- **`ios-release.yml`** (push to main + dispatch): `verify` (analyze/test, `:66–87`) → `release` on macOS. Build number = `github.run_number + 1000`, re-run-stable by design (`:106–131`); the submit gate calls `tools/asc_version_state.rb` and branches fail-closed (`:133–308`), with red-before-build guards for `fastlane/whats_new.txt` (`:276–286`) and `fastlane/review_notes.txt` — the 4.3(a) guard (`:295–305`); keychain/profile install (`:317–381`); archive unsigned, export signed, then verify the `Apple Distribution` authority, bundle id, device family, min OS, privacy manifest (`:403–474`); TestFlight upload (`:476–491`); submit step carries `continue-on-error: true` as the issue #94 interim mitigation (`:493–501`); IPA and dSYMs uploaded as artifacts for crash symbolication (`:528–547`).
- Release control: `fastlane/Fastfile` submit lane attaches the build after polling processing state, pins `MANUAL` release, writes What's New and review notes (`Fastfile:14`, `:101`, `:178`, `:234`, `:318`).

### 1.5 Tools (`tools/`, `taxi_game/tool/`, plus release scripts)

- `tools/asc_version_state.rb` — the fail-closed ASC state reader (verdicts `REVIEW_IN_FLIGHT` / `REVIEW_STUCK` / `NONE` / state list; `:8–37`; fail-closed contract `:40–49`; fixture-driven test seam `:69–74`).
- `tools/make_app_icon.swift` + `tools/generate_app_icons.sh` — generated icon in all 15 sizes; fails if the marketing icon carries alpha (`CLAUDE.md:86–97`).
- `tools/strip_alpha.swift` — strips alpha from screenshots (App Store Connect rejects it; `CLAUDE.md:44–48`, `:72–74`).
- `.claude/skills/release/scripts/asc.rb` — interactive ASC status/queries used by the release skill (`CLAUDE.md:264–277`; present in the worktree).
- `taxi_game/tool/screenshot_entry.dart` — dev-only entrypoint that launches directly into one screen (`SHOT=menu|game|garage|credits|settings`), mirrors production providers, ships in no build (`:1–14`, `:33`, `:54–63`).
- `taxi_game/tool/sprite_probe_entry.dart` — PM diagnostic from issue #40: renders the same taxi sprite via `SpriteComponent`, raw `drawImageRect`, and `Image.asset` to isolate device renderer failures (header `:1–13`).
- `taxi_game/tool/make_generated_audio.dart` — seeded, byte-stable synthesis of 3 shipped audio files (`:1–18`).
- `taxi_game/tool/make_vehicle_sprites.py` — deterministic sprite regeneration from the CC0 Kenney pack (`:1–19`).
- Photo pipeline: `xcrun simctl` + status-bar override + `strip_alpha`, all documented in `CLAUDE.md:44–82`.

### 1.6 Feasibility read — cheap vs expensive

| Plausible addition | Verdict | Why (cited) |
|---|---|---|
| **New game mode** | Moderate, unusually cheap for the mechanics, cost is in surface area | Mode branching already exists (`isEndless`, `taxi_game.dart:163`); pure systems (Lives/Bank/FareChain/Course/Environment) compose into any new ruleset. Costs: a new save/records shape, menu entry, overlay builders, records/stats wiring, and CI-visible tests — plus the "no placeholder UI" rule (`CLAUDE.md:312–315`). No server/config work is needed. |
| **Replay** | Cheap for a ghost-of-a-run; moderate for full fidelity | Position traces already record/replay (`ghost_replay.dart:17`, `:48`), bounded at 2,400 samples (`ghost_trace.dart:42`), but today they are daily-only and store no inputs/events (`ghost_trace.dart:3–12`). Seed determinism (`taxi_game.dart:748–749`, `endless_course.dart:52–60`) means a whole shift is re-simulatable given the seed plus a recorded player path — so an endless "watch your best run" is mostly plumbing. |
| **Shareable video** | Expensive | Nothing records frames or encodes video today. The only outbound channel is the OS share sheet over a PNG or text (`share_service.dart:5–11`; native side `AppDelegate.swift:142–219`). Video needs screen capture or a frame-by-frame encoder — a new native surface (AVAssetWriter/ReplayKit) with no existing test seam, and any permitted path must keep the local-only claim intact (`PrivacyInfo.xcprivacy:5–22`). The score card PNG is the cheap 90% of social sharing. |
| **Accessibility support** | Cheap for UI labels, expensive for canvas gameplay | No `Semantics(` usage exists anywhere in `lib/` (grep found none); Flutter screens get default control semantics, but the Flame canvas is one opaque surface — VoiceOver playability needs custom a11y actions/haptics and is a design project, not a label pass. Text-scale handling already exists in overlays via `FittedBox` plus post-frame measurement (`control_hint_overlay.dart:19–36`; `bank_prompt_overlay.dart:88–97`, `:140–167`), and the orientation/device constraints are locked (`main.dart:26–37`). The play surface itself is a single `GameWidget` (`game_screen.dart:145–146`); Talkback/VoiceOver for menus, records, and settings is cheap, the play surface is not. |
| **New environment or weather type** | Moderate, with a determinism rule | The world is one pure function of `(seed, distance)` and variety is already folded into the difficulty curve (`run_environment.dart:142–163`, `:623–740`); a new type means enum + draw + render (`environment_overlay.dart`) + physics modifier + simulator parity (the simulator reads the same `RunEnvironment`, `run_length_simulator.dart:200–207`). Rule: never rewrite existing draws or the daily hash (`endless_course.dart:208`, `daily_shift.dart:50–60`). |
| **Tuning iterations against the simulators** | Cheap — the strongest capability | Dedicated harnesses with pinned bands and a tuning table (`run_length_simulation_test.dart:30–113`; `economy_simulation_test.dart:8–31`); pure logic means a retune is a constant change plus a test run, no device needed. Caveat: the simulator deliberately omits fare detours, so it is optimistic (`run_length_simulator.dart:223–229`) and has no real-player ground truth yet (`difficulty_curve.dart:73–82`). |
| **In-app explanation surfaces** | Cheap | Overlay system is already a map of named builders (`game_screen.dart:154–186`); the first-run control hint is a full precedent (`control_hint_overlay.dart:8–46`); the ladder teaches by playing (10 levels); garage cards surface stat bars; diagnostics export/share exists (`settings_screen.dart:223–277`; `diagnostics.dart:121–132`). Any new surface must actually do what it says — "coming soon" UI is an explicit rejection trigger (`CLAUDE.md:312–315`). |

---

## Part 2 — Risk register

### 2.1 Hard constraints and their consequences

| Constraint | Where it is enforced / claimed | Consequence for the roadmap |
|---|---|---|
| **On-device only, `shared_preferences`** | `CLAUDE.md:327–330`; keys and bounded windows in `storage_service.dart:13–28`, `game_state_service.dart:22` (200-run window), `:28` (400 daily results), one ghost trace (`:24–28`) | No server leaderboard, no cross-device sync, no remote config/experiments, no server-side crash intake. "Social" is screenshots (`score_card_renderer.dart:9–16`). All roadmap features must be implementable as local pure logic plus a bounded prefs payload. |
| **No network calls at all** | Claimed in `PrivacyInfo.xcprivacy:5–22` and the privacy policy; the share channel is native-OS-mediated and states the zero-network design (`share_service.dart:5–11`) | Any network addition (even telemetry) forces privacy-policy + manifest + App Privacy answers (`CLAUDE.md:327–330`). Features that "need" a backend (true leaderboards, cloud saves, live-ops tuning) are effectively out of scope by product identity. |
| **No analytics; no crash reporting** | `run_stats.dart:6–12` (on-device stats are the only instrument); `diagnostics.dart:6–16` (local ring buffer, exported only by hand); #40's inability to identify a crash root cause | The tuning loop is simulators + whoever plays, not data. Device-only regressions surface as user reports, not events. Every "did it work" question needs a deliberate manual artifact path (TestFlight crash reports, diagnostics export, screenshots per #40). |
| **Portrait, iPhone-only, iOS 15+** | Orientation lock `main.dart:26–37`; `Info.plist:57–61`; fixed 400×800 game resolution `taxi_game.dart:70`; CI asserts `UIDeviceFamily [1]` and min OS (`flutter-builds.yml:74–81`); 6.9″ 1320×2868 screenshots (`CLAUDE.md:44–48`) | No iPad, no landscape, no Mac/desktop surface. UI work is laid out against one narrow canvas with hand-measured overlays (`control_hint_overlay.dart:13–36`, #139/#177/#182 in comments) — every new overlay is a layout-risk surface. Supporting older devices means performance work is aimed at the hardware floor, not just the newest phone. |
| **No account** | Daily is date-keyed, device-local (`daily_shift.dart:3–10`); ghost is per-device (`ghost_trace.dart:3–12`) | Identity-linked features (profiles, friends, cloud records) are out. Crash/QA evidence must be collected by hand — which is exactly the #40 blocker. App Review communication is the only "channel" to players. |

### 2.2 Known risks and current evidence

**Issue #40 — device-only crash and vanishing player cab (open, `gameplay`, `up-next`).**
- Evidence: user report 2026-09-28; does not reproduce headlessly. Five launch-lifecycle probes pass (`test/launch_lifecycle_probe_test.dart`, kept as permanent guards); dependency drift and asset wiring eliminated; audio memory trivial (1.1 MB); every pre-`runApp` await is fenced. Remaining hypotheses: (A) a **hang** in a pre-`runApp` audio platform call (already mitigated by moving `runApp` first and initializing audio concurrently — `main.dart:111–135`), (B) device-side sprite/texture decode or eviction (the `sprite_probe_entry.dart` tool exists to bisect this), (C) an audio-native crash in the release build that CI compiles but never runs.
- What blocks: no coder may be dispatched until an artifact identifies a mechanism (issue text: "Do NOT dispatch a coder"); the crash makes "tests are green" untrustworthy for ship decisions and directly attacks retention if a player sees no cab.
- Needed: TestFlight crash report text, or ASC issuer ID to pull crash logs, or screenshot + crash timing + build number for bisection. dSYMs are retained 14 days per release run (`ios-release.yml:537–547`), so a fresh crash is symbolizable.

**Issue #94 — release submit gate misfire (open).**
- Evidence: iOS Release run 36755106555 (2026-09-30): the gate printed `NONE` (no 1.0.0 version record) so submit ran; fastlane deliver found/mutated the version and Apple refused the build attach for a version already `WAITING_FOR_REVIEW`. The maintainer's later read-only ASC queries showed exactly one version record — `1.0.0`, `WAITING_FOR_REVIEW` since ~5½ h before the run — so the gate's `NONE` was a **false negative**, and the open question is why the CI invocation got a list without 1.0.0 (different key/role behind the `ASC_*` secrets vs the local `.env` key, or an empty `data`).
- Current mitigation: the submit step runs with `continue-on-error: true` (`ios-release.yml:493–501`) so TestFlight deploys stay green; the dSYM/IPA artifacts still upload. The workflow header documents the full fail-closed policy (`ios-release.yml:11–31`), and the script now reads two sources and treats empty/truncated/unparseable answers as run-failures (`tools/asc_version_state.rb:40–49`).
- What it blocks: a green pipeline no longer proves a submission happened; a false `NONE` still decides `submit=true`, and the interim `continue-on-error` can hide a lost submission. Until diagnosed, "did 1.0.x actually get submitted" is unanswerable from CI alone.

**Frame hygiene batch #250–#257 (seven open `tech-debt` issues, all `assigned`, in flight).**
- All seven are **static findings** from a 2026-10-09 review cycle, explicitly "no profiling was possible on this machine — structural evidence only":
  - #250 road chunks re-sample geometry and rebuild Paths/Paints every frame (`road_segment.dart:86–94`, `:200–222`);
  - #251 background rebuilds a gradient Shader and Paints per frame (`background.dart:32–41`);
  - #252 `TrafficSpawner` rebuilds the whole traffic profile per frame to read one scalar (`traffic_spawner.dart:86–94`, `:114`);
  - #253 fare controller rebuilds a full fare every frame for the horizon test (`endless_fare_controller.dart:187–189`, `:200`);
  - #254 the headway pass materialises the traffic list and is O(n²), plus the player rescans all children (`traffic_spawner.dart:154`, `:162–169`; `player_vehicle.dart:247`);
  - #255 weather overlay opens up to two full-viewport `saveLayer`s per frame (`environment_overlay.dart:138–140`);
  - #256 marker/cone renderers allocate Paints and rebuild glyph Paths per frame (`pickup_zone.dart:106–118`, `fare_glyph.dart:90`, `road_obstacle.dart:47–72`);
  - #257 per-entity allocations (headlight blur-mask Paint per car per night frame, `vehicleSize` Vector2 per read, shake/weather scratch) (`traffic_vehicle.dart:196–202`, `:270`, `:283–284`, `:429–435`; `player_vehicle.dart:68`; `taxi_game.dart:1977–1984`, `:2039–2043`).
- What they block: performance headroom for denser scenes (any traffic-density or FX increase multiplies per-frame allocation cost — #254 says the cost "grows with any density change"), and certainty about the frame budget on older iPhones. There is no evidence of a measured frame-rate failure yet; the risk is that nobody can measure on this machine (`no profiling was possible`), so fixes and regressions are equally unverifiable until someone profiles on device.

**Issue #212 — 4.3(a) rejection, App Store Connect side (open, `needs-human`).**
- Evidence: Apple rejected 1.0.0 (1068) on 2026-10-08 under Guideline 4.3(a) (Design – Spam), submission `a20af53a-8b80-4f7a-8f2e-4ccd11d6e244`, for a review that had no notes to read. The pipeline half has landed: `fastlane/review_notes.txt` is written onto every submitted version (`Fastfile:318–362`) and a run that would submit fails red before the build without it (`ios-release.yml:295–305`); a paste-ready Resolution Center reply and listing checklist exist (`docs/app-review/2026-10-08-4.3a-response.md`); listing copy is prepared (`docs/app-review/listing-copy.md`); release runs 108/109 stayed TestFlight-only with `REVIEW_STUCK`, exactly as designed (#102). The checklist — reply, review listing, clear/replace the rejected submission, resubmit — needs the App Store Connect account and nothing else has moved since.
- What it blocks: all public distribution. The product currently ships to TestFlight only; every roadmap item that assumes App Store availability (reviews, screenshots driving conversion, organic installs) is gated on a human resolving the rejection. Until the submission is cleared, the gate answers `REVIEW_STUCK` and neither a version bump nor a manual dispatch submits.

### 2.3 Top five risks to the "best vertical scroller taxi game in the world" ambition

1. **The app cannot reach the App Store, and the release gate that should fix that has its own defect — severity: critical.** 4.3(a) is unresolved (#212) and the gate has a documented false-negative history (#94, #93, #89). Evidence: TestFlight-only runs 108/109; `REVIEW_STUCK` design; `continue-on-error` mitigation in `ios-release.yml:493–501`; the false `NONE` of run 36755106555. A world-class game that only testers can install cannot compete.
2. **A device-only crash with no crash intake — severity: critical.** #40 shows the app can fail on a real phone (crash and cab not rendering) while nine hundred headless tests pass. With no analytics and no crash reporting, the only detection path is a human noticing and hand-delivering artifacts (TestFlight crash report / issuer ID / screenshot + build). Every feature shipped on top of an unlocalized crash inherits the uncertainty.
3. **The evidence vacuum makes "best in class" tuning unverifiable — severity: high.** The game is designed offline (`run_stats.dart:6–12`, `diagnostics.dart:6–16`), so difficulty, economy, and feel are tuned against a simulator that explicitly omits fares and is "optimistic" (`run_length_simulator.dart:223–229`), with no real-player ground truth yet (`difficulty_curve.dart:73–82`). On-device history is a bounded, per-device window (200 shifts / 400 dailies). Data-driven improvements (retention, difficulty curve, economy, difficulty of distant-run phases) will keep being guesses until the project accepts some deliberate, privacy-consistent way to see aggregate player behavior — or consciously chooses not to and funds more human playtesting instead.
4. **Performance headroom is unmeasured and the per-frame cost grows with any density increase — severity: medium-high.** #250–#257 document per-frame Path/Paint/Shader/allocation churn in the hot render path, including two full-viewport `saveLayer`s in foul weather (#255) and per-car blur-mask Paints at night (#257), with no profiling possible on the current machine. The ambition ("the most exciting vertical taxi game") pushes exactly the levers that multiply these costs — more traffic, more weather, more FX. Without a device profiling loop, this is a latent frame-budget cliff on the iOS 15 hardware floor.
5. **Release-pipeline complexity is itself a delivery risk — severity: medium-high.** Five generations of gate fixes (#89, #93, #94, #102, #119, #137, #199, #204, #211) have turned the workflow into a bespoke, fail-closed state machine where each new rule exists because a run silently lost something (a submission, a build number, a release note). It is well documented and well tested (`release_submit_gate_test.dart`; `workflow_guards.dart`), but it still (a) auto-uploads a TestFlight build on every push to main, (b) burns a permanent build number on failed uploads (#137), and (c) requires a human in App Store Connect for anything a rejection touches. Every roadmap item that ships is subject to this pipeline; a single misconfiguration (as in #94) makes shipping status unknowable while the run stays green.

---

## Unverified

- **Actual device performance numbers.** No profiling was possible (per #250–#257 and by instruction not to run the app); all frame-hygiene claims are the issues' static structure, not measurements.
- **Real-player run length / economy.** The 2–4 km median and coin table are simulator priors, not device data (`run_length_simulation_test.dart:26–29`; `economy_simulation_test.dart:22–31`).
- **Issue #40 root cause.** The three remaining hypotheses (audio hang, texture decode/eviction, release-only native crash) are unresolved from a Windows box; the issue itself says the mechanism is unidentified.
- **Why the CI gate saw an empty/incorrect version list in #94.** The maintainer's comment identifies the contradiction but not the cause (possible key/role difference behind CI secrets vs local `.env`; the script logged nothing on the `NONE` path at the time).
- **Whether 4.3(a) will clear on resubmission.** The response package and review notes are prepared; the outcome is unknowable until Apple re-reviews.
- **TestFlight crash-report availability.** Depends on an ASC issuer ID or a manual crash report that the operator has not yet supplied (#40's "needed to close" list).
- **Scope of UI I did not read line-by-line.** `garage_screen.dart`, `records_screen.dart`, `stats_screen.dart`, `daily_screen.dart`, `main_menu_screen.dart` were scanned (structure, providers, buttons) but not audited line by line; counts of tests and files are measured, but individual test coverage claims beyond those cited are not audited.
- **Nothing in this report was verified by running code** (read-only slice; no `flutter` commands per instructions).
