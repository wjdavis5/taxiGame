# W2 — First-session and moment-to-moment feel audit

**Slice:** cold start → first gameplay, control feel, juice inventory, friction.
**Repo:** `C:\git\repos\taxiGame-pm` at `c514609` (verified via `git log -1`). Read-only pass; no `flutter` commands run.
**Evidence rule:** every claim cites a file and line with a short quote. Paths are relative to the worktree root; most game code lives under `taxi_game/lib/`. Feel judgements name the code fact they rest on. Things I could not evidence in code are in **Unverified** at the end.

---

## 1. Cold start → first gameplay

### 1.1 Boot sequence before any UI

| # | Step | Where | Quote | Player-visible effect |
|---|------|-------|-------|----------------------|
| 1 | Diagnostics tail load | `taxi_game/lib/main.dart:47` | `await Diagnostics.instance.load();` | blocks first frame on a prefs read (`services/diagnostics.dart:54-55`: `await SharedPreferences.getInstance();`) |
| 2 | Orientation lock | `main.dart:70-74` | `await lockOrientation();` (failure logged, startup carries on) | second platform round-trip |
| 3 | Storage init + save load | `main.dart:83-87` | `await storageService.init();` … `await gameStateService.loadSaveData();` | third round-trip; failure swaps in `StartupFailureApp` (`main.dart:92-95`, retry UI `230-268`) |
| 4 | First Flutter frame | `main.dart:150-161` | `runApp(MultiProvider(… child: const TaxiGameApp()))` | appears after 1–3 |
| 5 | Audio init (unawaited) | `main.dart:117-135` | `unawaited(audioService.initialize().then(…))` | music starts a few frames later; never blocks first frame |
| 6 | Menu mounts | `main.dart:191` | `home: const MainMenuScreen()` | |

Judgement: three sequential platform round-trips gate the first Flutter frame; only the native launch storyboard covers them. There is no Flutter-side splash/loading screen. This is launch latency, not confusion — nothing on this path can dialog or trap the player.

### 1.2 Main menu for a brand-new save

- **No dialogs, no first-run onboarding screens.** The only `showDialog` in `lib/` is the Settings reset-confirm (`ui/screens/settings_screen.dart:399-401`), off this path.
- What the new player sees: title `CAB HUSTLE` (`ui/screens/main_menu_screen.dart:55-74`), then `Level 1` and `0 Coins` (`84-99`), then the play modes ordered for first-run:
  - `_buildLadderButton(context, primary: true)` (`120-126`) → `_MenuButton(buttonKey: Key('play_button'), label: primary ? 'START DRIVING' : 'PLAY')` (`243-251`) → `Navigator.push(… GameScreen())` (`252-258`).
  - `ENDLESS SHIFT` and `DAILY SHIFT` step back in white (`128-141`).
  - `GARAGE`, `RECORDS`, `SETTINGS`, `CREDITS` below (`162-228`).
- **Time to actual gameplay = one tap**, on the biggest, yellow, centred control in the app. The menu scrolls when it must (`37-42`, `SingleChildScrollView`), but the primary button sits around the vertical middle and is on-screen on small phones.
- Every menu press clicks and ticks: `audioOf(context)?.playButtonSound(); hapticsOf(context)?.buttonPress();` (`466-470`).

### 1.3 GameScreen mount and the load window

- `GameScreen.initState` reads the hint flag and builds the game; the game's `onLoad` then loads level 1 or starts the endless run:
  - `ui/screens/game_screen.dart:69-72`: `showControlHint = !context.read<GameStateService>().controlHintDismissed; game = _createGame();`
  - `lib/game/taxi_game.dart:580-599`: `if (endlessSeed != null) { await startEndlessRun(…)} … await loadLevel(gameState.currentLevel);`
- **There is no loading state.** `GameWidget` is built without a `loadingBuilder` (`game_screen.dart:145-153`). Flame's fallback while the game load future is pending is `widget.loadingBuilder?.call(context) ?? const SizedBox.expand()` over a `ColoredBox(color: currentGame.backgroundColor())` (flame-1.34.0 `lib/src/game/game_widget/game_widget.dart:411-412`, `374-375`). Result: the tap on START DRIVING collapses the menu into a plain dark-grey `#1A1A1A` screen (`taxi_game.dart:554`: `Color backgroundColor() => const Color(0xFF1A1A1A);`) until the level/endless build completes.
- HUD and hint overlays are only registered once the game is loaded (`initialActiveOverlays: ['hud', if (showControlHint) 'controlHint']`, `game_screen.dart:189-192`), so the blank window shows no badges either.
- In level mode the only await on that path is the asset read + JSON parse: `level_loader_service.dart:62-65` (`await rootBundle.loadString(path); … GameLevel.fromJson(jsonData)`), so the blank window is short on device — but it exists and says nothing.
- **Possible carless frames:** the taxi sprite is added from inside `PlayerVehicle.onLoad` after `await game.loadSprite(...)` (`components/player_vehicle.dart:117-124`). The road/world can therefore render in a frame where the cab's PNG decode has not landed. (Visual consequence in Unverified.)

### 1.4 The first seconds on the road

- The cab starts stationary and does not creep: `throttle = throttleInput != 0 ? throttleInput : (isAccelerating ? 1.0 : 0.0)` (`player_vehicle.dart:289-290`), and nothing sets `isAccelerating` on touch. Until the thumb lands low, nothing moves.
- The one-time hint is the entire tutorial: `game_screen.dart:69-70` decides it; the line is `control_hint_overlay.dart:56-57`: *"Touch and hold the lower half — drag up for speed, sideways to steer."* It is dismissed by the first lower-half landing and written to the save for good: `taxi_game.dart:548-551` (`overlays.remove('controlHint'); gameState.dismissControlHint();`), `models/save_data.dart:34-38` and `111-112` (missing key reads as dismissed).
- **Level 1 geometry fact.** "First Ride" is one pickup at `[315, 400]` and one dropoff at `[315, -300]` (`taxi_game/assets/levels/level_001.json:5-10`). The road spans x 100..300 (`taxi_game.dart:491-493`) and the cab is clamped to centre x 120..280 for its 40 px body (`player_vehicle.dart:157-162`). The pickup's 40 px detection circle plus the 30 px-wide hitbox (40 × `playerHitboxScale` 0.75, `collision_rules.dart:176`) only intersects when the cab centre is at x ≥ 260 — the outer 20 px of reachable road. A centre-line first drive sails past; `_checkForMissedFares` then fails the level 80 px later (`taxi_game.dart:1565-1579`; panel `1587-1600`). So the first lesson silently requires hugging the right kerb.

---

## 2. Control feel (code audit)

### 2.1 The stick and its constants

`components/virtual_stick.dart`:

| Constant | Value | Line | Meaning |
|---|---|---|---|
| `stickRadius` | 72 canvas px | `43` | glide from origin to rim |
| `deadZoneFraction` | 0.10 | `47` | input below 7.2 px does nothing |
| `fullLockFraction` | 0.5 | `52` | steering saturates at half a radius (36 px) |
| `fadeSpeed` | 8 opacity/s | `55` | ring fade |
| `ringRadius` / `knobRadius` | 34 / 15 | `58-59` | drawn sizes |

The viewport is fixed 400×800 (`taxi_game.dart:69-71`), so on a 375 pt-wide iPhone one canvas px ≈ 0.94 pt: **full steering lock lives in a ~34 pt (~9 mm) thumb glide, the dead zone in ~7 pt.** The response curve is `resolve()` (`virtual_stick.dart:107-131`): dead zone → radial amplification ramping from 0 at the zone edge to 1 at the rim → per-axis shaping, clamp at both stages.

### 2.2 Findings

1. **Steering is a direct velocity assignment — no ramp, no inertia.**
   `player_vehicle.dart:321-323`: `final grip = …; velocity.x = steeringInput * steeringSpeed * grip;`
   Starter cab: `steeringSpeed: 300` (`data/vehicle_catalog.dart:108-114`). The frame the stick crosses half-radius, lateral speed steps straight to ±300 px/s; the frame it returns inside, back to 0. Every correction is a step function. *Judgement:* this reads crisp but binary — there is no wheel weight to learn, and no finer gear than "full hold" once past the short lock throw. Cross-check: steering saturates at `fullLockFraction` (`virtual_stick.dart:49-52`) and a diagonal drag past ~45 % of a radius already clamps to ±1 (`122-125`).
2. **Longitudinal control is stop/start, not coasting.**
   Release: `braking = deceleration * (1.0 - throttle)` with `deceleration = 600` (`player_vehicle.dart:21`, `304-309`) → 150→0 px/s in 0.25 s. Full drag-down: ×(1−(−1)) = 1200 px/s² → 0.125 s. Acceleration 400 px/s² (`302-303`) → 0→150 in 0.375 s at full throttle; the code comment at `300-301` says "~0.5 s from stop to full speed", so the actual tuning is snappier than its own spec text. *Judgement:* the cab stops faster than it starts and barely coasts — the pedal reads as on/off.
3. **The top half of the screen is dead, silently.**
   `virtual_stick.dart:180-181`: `if (local.y <= game.camera.viewport.virtualSize.y / 2) return;`
   A thumb landing high gets no input and no cue that it was ignored; the only teacher is the one-time hint, removed after a single low touch. *Judgement:* the most likely first-30-seconds confusion for anyone who holds the phone high.
4. **Dead zone is small (10 %, 7.2 px).** Below it "jitters under the gate input nothing at all" (`virtual_stick.dart:45-47`); above it input ramps from zero. A resting thumb that drifts ~8 px off its landing point starts feeding throttle/steer.
5. **Latency is one frame, event-driven — the problem is shaping, not delay.**
   `virtual_stick.dart:326-330` (`game.player.setSteering(input.steering); game.player.setThrottle(input.throttle);`) → `PlayerVehicle.update` (`player_vehicle.dart:128-131`). No polling, no smoothing; responsiveness is as good as a frame.
6. **Near miss is a precision rule, invisible by accident.**
   `systems/near_miss.dart:48-61`, `80-87`: award when edge-to-edge gap ∈ (−9, 14] px and forward speed ≥ 95 px/s; lanes sit 100 px apart with 40 px bodies (`:41-47` comments). Riding a lane centre scores nothing — the economy only pays if the player deliberately rides lane edges at speed.

---

## 3. Juice inventory

All refs below are `taxi_game/lib/game/taxi_game.dart` unless another path is given. "No feedback" rows are marked explicitly.

| Event | Particles | Pop / text | Shake / hit-stop | Sound | Haptic | Notes |
|---|---|---|---|---|---|---|
| **Fare pickup** | green burst, 14 | — | — | `playPickupSound()` `:959` | medium `haptics.pickup()` `:960` | zone just disappears (`pickup_zone.dart:166-177`); nearest equivalent to a "score" is the fare-timer badge appearing |
| **Fare dropoff — level** | blue/gold burst `:992-995` | 3 `CoinPop` at the kerb `:999-1004` | — | `playDropoffSound()` `:1008` | medium `:1009` | coin counter does **not** move: coins are credited only at completion (`:1438-1444` → `game_state_service.dart:365-366`) |
| **Fare dropoff — endless** | same burst `:1045-1049` | 3 `CoinPop` `:1052-1057` | — | `:1063` | medium `:1064` | `addCoins` immediately `:1058` → HUD chip pulses (`hud_overlay.dart:150-156`) |
| **Bank — endless** | — | summary panel | — | `playBankedJingle()` `:1244` | **none** | bank button itself silent (`bank_prompt_overlay.dart:326-327`) |
| **Bank — ladder level** | — | 6 `CoinPop` from the cab (`_completeLevel` `:1415-1420`) | — | coin ring `:1423` + completion jingle `:1425` | light `coinAward` `:1424` | buttons click (`game_screen.dart:572-573`) |
| **Chain break (timer expiry)** | **none** | **none of its own** | — | **none** | **none** | `fare_chain.dart:296-303` `multiplier = 1` silently; only HUD badge re-keys to `×1` white (`hud_overlay.dart:638-649`) and the fare badge flips to `LATE` (`:700-703`) |
| **Late delivery** | same as on-time | same | — | same | same | settlement discarded: `fareChain.completeFare(…)` at `:989` and `:1043` ignore the returned `FareSettlement` |
| **Push bonus (button or timeout)** | **none** | multiplier badge changes | — | **none** | **none** | `_applyPushBonus` `:1199-1202`; timeout path `:1965-1967`; PUSH button silent (`bank_prompt_overlay.dart:349-350`) |
| **Crash (judged)** | 18 spark burst at contact `:1700-1706`, ticked through the freeze `_playCrashFxThroughFreeze` `:1742-1748` | failure/summary panel after hit-stop `:1539-1543`, `:1688-1692` | shake scaled 0→13 px `:1715-1718` (`impact_fx.dart:15-18,48-51`), hit-stop 0.10 s `:1719` (`impact_fx.dart:32`) | `playCrashSound()` `:1722` | heavy `haptics.crash()` `:1723` | level fail also `playLevelFailedSound()` `:1545`; third endless crash adds wreck sting `:1694` |
| **Life lost (endless, survivable)** | same crash FX | `LifeLostPop '-1 LIFE · N LEFT'` `:1636-1639` | 1.2 s stall `:1653` (`:222`) | crash SFX | heavy crash buzz | HUD lives pulse on spend (`hud_overlay.dart:552-558`) |
| **Near miss** | cyan burst, 10 `:1816-1823` | `CLOSE CALL +N` `:1824` (`close_call_pop.dart:17-24`) | **none** | OS system click only `:1831` (`near_miss.dart:105-116` — no bundled whoosh) | medium `:1830` | no shake, no hit-stop, no speed-line kick |
| **Scrape (traffic or cone)** | 6 sparks `:1766-1772` | `ScrapeMarker` naming the vehicle `:1779-1782` | 3 px shake / 0.18 s `:1773-1776` | `playScrapeSound()` `:1778` | **none** | one volley per 0.4 s `:1761-1762` |
| **Level complete** | 6 `CoinPop` `:1415-1420` | green panel + payout/score `game_screen.dart:523-543` | — | coin ring `:1423` + completion jingle `:1425` | light `coinAward` `:1424` | NEXT LEVEL clicks + ticks `game_screen.dart:430-431` |
| **Daily result** | — | `TODAY'S DAILY IS IN` banner `run_summary_panel.dart:72-114`; Daily screen card `daily_screen.dart:152+` | — | **none of its own** | **none of its own** | recorded at shift end `:1282-1288`; banked/wrecked sting is the only cover |
| **Danger telegraph (pre-crash)** | red outline + throbbing `!` within 1.1 s of impact `traffic_vehicle.dart:424-445`, `danger_indicator.dart:62-74` | — | — | **none** | **none** | |
| **Brake** | — | — | — | squeal on falling edge ≥ 120 px/s `player_vehicle.dart:313-315` | **none** | re-arms on any throttle `:317-319` |
| **Engine + speed lines** | — | — | — | engine loop live/speed-driven `taxi_game.dart:1856-1861` (`audio_service.dart:590-614`) | — | speed lines 95→150 px/s `:1970-1976` (`impact_fx.dart:34-42`); zeroed on endings `:2113` |
| **Pause** | — | menu `game_screen.dart:266-390` | — | **none on the button** | **none on the button** | `hud_overlay.dart:318-330` calls `game.pauseGame()` directly; menu buttons do click `game_screen.dart:309-310, 324-325, 344-345` |
| **Summary actions** | — | — | — | **none** | **none** | DRIVE AGAIN / RACE YOUR GHOST / MAIN MENU `run_summary_panel.dart:285-292, 340-350, 375-387`; `retryShift` `taxi_game.dart:1340-1346` has no sound either |

### Events with no feedback at all (or none of their own)

- **Chain break by timer expiry** — no sound, haptic, pop, shake, or message anywhere (`fare_chain.dart:296-303`; only the HUD re-key at `hud_overlay.dart:644`).
- **Push bonus** (chosen or timed out) — no confirmation; the PUSH button itself is silent (`bank_prompt_overlay.dart:349-350`, `taxi_game.dart:1199-1202`).
- **Late delivery vs on-time** — identical feedback; settlement return ignored (`taxi_game.dart:989`, `:1043`).
- **Endless bank** — jingle + panel only; no vibration, no coin pops (`taxi_game.dart:1241-1246`).
- **Daily result** — no sting/haptic of its own beyond the shift ending.
- **Scrape** — no haptic at all (`taxi_game.dart:1753-1783`).
- **Bank/push buttons, pause button, summary buttons** — the only interactive controls in the game with no click/haptic (refs above; contrast `main_menu_screen.dart:466-470`).
- **In-level fare pickup/dropoff** — the +coins never move the HUD counter until the level completes (`taxi_game.dart:1438-1444`).

---

## 4. Friction list (player → fun)

1. **Three sequential pre-frame platform reads at launch** — `main.dart:47`, `:71`, `:84-87`; nothing but the native storyboard covers them.
2. **No loading state when entering the game** — tap START DRIVING → plain `#1A1A1A` screen while the run builds: no `loadingBuilder` (`game_screen.dart:145-153`), Flame fallback blank (`game_widget.dart:411-412`), overlays only after load (`game_screen.dart:189-192`).
3. **Possible carless first frames** — taxi sprite added after `await game.loadSprite(...)` inside `PlayerVehicle.onLoad` (`player_vehicle.dart:117-124`).
4. **Silent dead upper half** — `virtual_stick.dart:180-181`; no response or cue when a thumb lands high.
5. **Twitchy steering cardinality** — direct `velocity.x` assignment (`player_vehicle.dart:321-323`) with full lock at ~34 pt (`virtual_stick.dart:49-52`; 400×800 viewport `taxi_game.dart:69-71`).
6. **Stop/start longitudinal feel** — 0.25 s release-to-stop, 0.125 s full brake (`player_vehicle.dart:21, 304-309`); no coasting.
7. **No reverse** — "forward is the only gear" (`player_vehicle.dart:196-207`); a missed kerb is unrecoverable, and levels fail 80 px later (`taxi_game.dart:1565-1579`).
8. **Level 1's only pickup sits at the far kerb, reachable in the outer 20 px of the clamp range** — `level_001.json:5-10`; `taxi_game.dart:491-493`; `player_vehicle.dart:157-162`; `pickup_zone.dart:31-32`; hitbox scale `collision_rules.dart:176`. A centre-line first drive ends in `FARE MISSED!`.
9. **Standing start with no creep** — no input = 0 speed (`player_vehicle.dart:289-290`); a player who taps and waits sees nothing happen.
10. **One crash fails a tutorial level, unannounced** — `taxi_game.dart:1503-1507`; only the failure panel (`game_screen.dart:615-618`) ever teaches it.
11. **Timer consequences are under-taught** — `LATE` and the multiplier drop arrive without words (`fare_chain.dart:293-304`; `hud_overlay.dart:664-687`), and a late delivery looks exactly like an on-time one (`taxi_game.dart:989`, `:1043`).
12. **In-level coins fly to a counter that does not move** — `taxi_game.dart:999-1004` vs `:1438-1444` (`game_state_service.dart:365-366`).
13. **Feedback holes on the most-used buttons** — bank/push (`bank_prompt_overlay.dart:326-327, 349-350`), pause (`hud_overlay.dart:318-330`), summary actions (`run_summary_panel.dart:285-292, 340-350, 375-387`) are silent and buzz-less while every menu button clicks (`main_menu_screen.dart:466-470`).
14. **Bank window shape** — 5 s live window (`bank_prompt.dart:35`) under a panel that must dodge the cab and the ghost badge (`bank_prompt_overlay.dart:84-109, 175-191`): legible but crowded, and the primer freeze (`taxi_game.dart:1096-1104`) is the only calm version of the game's core decision.
15. **Menu scrolls on short phones** — `main_menu_screen.dart:37-42`; the primary action is fine, the four lower buttons need a scroll.

---

## Unverified

- **Wall-clock timing** of the pre-frame reads (`Diagnostics.load`, storage init/save load) and of the blank load window on a real device. Code shows the ordering and the blank fallback; no stopwatch was run per the no-flutter constraint.
- **Whether the carless frames are perceptible.** The code fact is that the sprite is added after an await (`player_vehicle.dart:117-124`); whether PNG decode lands within the first visible frame was not observed.
- **Audio/haptic perceptibility on device.** All paths above are code calls; whether the OS click in `CloseCallFeedback` (`near_miss.dart:105-116`) reads at gameplay volume, and how the haptics feel, need a device session.
- **The first-60-seconds lived experience** (thumb ergonomics, letterbox proportions, muscle memory). Everything here is derived from constants, line quotes, and geometry; no live play session was run.
- **Endless first-dropoff primer timing**: whether a first-time player who skipped the ladder's banking lessons reaches the primer before `bankPromptSeen` is consumed by anything else was not traced through every level's `bankPromptEnabled`.
