# W5 — Uniqueness & Submission review: Cab Hustle 1.0.0

Worker slice: W5, uniqueness and submission lens. Read-only review of
`C:\git\repos\taxiGame-pm` at `c514609` (main). Prepared package read first:
`docs/app-review/2026-10-08-4.3a-response.md` (the paste-ready Resolution
Center reply and listing checklist), `docs/app-review/listing-copy.md`, and
`gh issue view 212 --repo wjdavis5/taxiGame`. No edits, no flutter commands.

**Verdict in one line:** bank-or-push and the Daily Shift are genuinely
visible in the shipped experience; the near-miss economy is essentially
invisible outside the moment it happens; and the submission package's
"original art" claim contradicts the repo's own license inventory — the
single most dangerous sentence in the 4.3(a) reply.

---

## 1. What the shipped UI actually says, per differentiating mechanic

### 1.1 Daily Shift with ghost — visible and explained, ghost only after day one

What a player sees, in order:

- Menu entry: `main_menu_screen.dart:339` —
  `label: result == null ? 'DAILY SHIFT' : "TODAY'S RESULT"`.
- The shared-course claim is on the menu, under the button:
  `main_menu_screen.dart:379-381` —
  `'$dayKey · ONE SHIFT, SAME FOR EVERYONE'` and
  `'${result.score} PTS · DONE FOR TODAY'`.
- Daily screen explains the mode:
  `daily_screen.dart:267-268` — `'One shift a day, and every player in the
  world gets the same course. How far can you take it?'`; the unplayed card
  says `'No shift yet today.'` (`:255`).
- The attempt is framed once-a-day: `daily_screen.dart:266` — `'Done for
  today — a new course arrives tomorrow.'`; empty history at `:477`.
- The ghost has real surfaces, but only after a daily run has settled:
  `daily_screen.dart:363` — `'RACE YOUR GHOST'`; the ghost race also appears
  on the run summary: `run_summary_panel.dart:364`. On the road it is a
  translucent car — `ghost_car.dart:50` — `static const double ghostOpacity
  = 0.35;` — with a live gap readout, `hud_overlay.dart:617` —
  `'GHOST ${gap == 0 ? '' : gap > 0 ? '+' : '-'}${gap.abs()} m'`.
- The social artifact sells the mode harder than any screen:
  `score_card.dart:149-150` — `footer => isDailyShift ? 'ONE COURSE ·
  EVERY PLAYER · TODAY ONLY' : 'CAB HUSTLE'`.

Assessment: **visible and explained.** The one gap is that the word "ghost"
never appears on the menu and there is no ghost to race on a first-ever
daily until the player finishes one; the first sighting of the mechanic is
the post-run `RACE YOUR GHOST` button. Acceptable, but the menu sells the
shared course without the payoff.

### 1.2 Bank-or-push / Endless Shift — the best-sold mechanic in the app

- Menu: `main_menu_screen.dart:278` — `'ENDLESS SHIFT'`, with a best-score
  line when one exists (`:293-294`, `'BEST ${gameState.endlessBestScore}'`).
  For a first-run save the button is deliberately non-primary; the ladder
  leads (`:117-141`, `'START DRIVING'` at `:250`).
- The decision is a named, priced question over live traffic:
  `bank_prompt_overlay.dart:242` — `'BANK OR PUSH?'`; `:257` —
  `'AT RISK ${chain.score}'`; the stake sentence at `:280-281` — `'Bank ends
  the shift and keeps it — a crash loses it.'`; buttons `'BANK
  ${chain.score}'` (`:336`) and `'PUSH ON ×$nextMultiplier'` (`:359`).
- First-ever offer gets a calm introduction: the world freezes —
  `taxi_game.dart:1092-1103` — `'the first offer a save ever sees stops the
  world'`, `_bankPrimerActive = true; paused = true;`.
- Three strikes is dramatized in the HUD: hearts at `hud_overlay.dart:562-569`
  driven by `lives.dart:13` — `static const int maxLives = 3;` — and the
  at-risk score label at `hud_overlay.dart:449-450` — `'AT RISK
  ${chain.score}'`.
- The forfeit is named at the end: `run_summary_panel.dart:138` —
  `'Three crashes — the shift is over.'`; `:152` — `'Forfeited:
  ${summary.score} coins'`; recovery lesson at `:164` — `'Tip: banking at a
  dropoff keeps your coins safe.'`; `'SHIFT BANKED'`/`'SHIFT OVER'` at `:60`.
- Quit paths keep naming the stake: `game_screen.dart:298` — `'$atRisk
  coins at risk'`; `:335` — `'BANK $atRisk & QUIT'`; `:363` —
  `'QUIT — $atRisk LOST'`.
- The ladder teaches it before Endless does: level 9 is literally named
  "Bank It" and level 10 "Graduation Shift", both `"bankPrompt": true`
  (`assets/levels/level_009.json`, `level_010.json`), and completion names
  the rung on screen (`game_screen.dart:496-499`, `'Level
  ${game.currentLevelNumber} — ${game.currentLevelName}'`).

Assessment: **visible from the first Endless run, explained in words, and
dramatized in three separate ways (primer freeze, prompt, forfeit panel).**

### 1.3 Near-miss economy — explained only by its own gameplay, and only if it happens

The entire in-app footprint:

- A world-space pop when a pass rules in: `close_call_pop.dart:17` —
  `text: 'CLOSE CALL +$points'` (cyan, rises, 0.8 s).
- One row on the just-ended run summary: `run_summary_panel.dart:279` —
  `_statRow('Close calls', '${summary.nearMisses}')`.

Nothing else. Checked and absent:

- No tutorial level mentions it: level names are First Ride, Cross Town, Two
  Fares, Picking Up, Against the Clock, Rush Hour Meter, Chain Reaction,
  Keep the Chain, Bank It, Graduation Shift (level JSON `name` fields), and
  a text search of `assets/levels/*.json` for near/close/shave finds nothing.
- No achievement: the 15-entry catalog (`achievements.dart:227-243`) covers
  chain, distance, banking, cars, and daily streaks only; the word
  near-miss/close-call never appears in it.
- No lifetime stat: `run_stats.dart` has no missing near-miss field (grep
  for `nearMiss|closeCall` is empty), and the Shift stats screen's sections
  are Totals / Typical shift / Run lengths / Bank or push / Crashes
  (`stats_screen.dart:154-262`) — no close-call section. The per-shift
  `RunRecord` does store `nearMisses` (`run_record.dart:44-49`), but no
  screen ever shows a stored value.
- No menu, Daily, Garage, Records, Settings, or help copy names it.

The rules are real and tuned — `near_miss.dart:48` (`gapThreshold = 14.0`),
`:61` (`minPassSpeed = 95.0`), scoring through the chain at
`fare_chain.dart:104` (`nearMissScore = 15`) and `:265-270` — but a player
who never happens to shave a car never learns the economy exists, and a
player who does learns it only from a pop-up. This is the design's most
distinctive scoring idea and it is the least surfaced.

Assessment: **invisible as a designed economy; explained only by its own
gameplay.**

### 1.4 Handling-different vehicles — partly visible, under-sold by copy

- Menu entry `'GARAGE'` (`main_menu_screen.dart:165`), and the catalog is
  built so no car dominates: `vehicle_catalog.dart:10-14` — `'no car is best
  at everything... a strictly-dominating car would turn the garage into an
  upgrade treadmill'`; stats at `:107-187`.
- Every card draws four fleet-relative bars: `garage_screen.dart:488-496` —
  `SPEED`, `ACCEL`, `STEER`, `SIZE` — with the intent documented at `:133-135`
  (`'four fleet-normalized bars... so bar lengths compare across cards'`).
- Status lines are state only: `garage_screen.dart:272-275` — `'For sale'`,
  `'Ready to drive'`, `'Owned'`.

Assessment: **visible if opened, but no sentence anywhere in the app says
the bars change how the car drives.** A player has to connect bars to feel
themselves; a reviewer flipping through screens sees a shop with stat bars,
which is a common mobile-game shape, not an obviously different one.

### 1.5 Bonus mechanic worth noting: fare kinds with a decline

The four fare types are on the HUD offer bar in words —
`fare_type.dart:95-100` — `'VIP · N c · TIGHT CLOCK'`, `'LONG HAUL · N c ·
+3 CHAIN'`, `'FAR SIDE · N c'` — with a real SKIP control
(`hud_overlay.dart:835`). This is another genuine differentiator that is
present but never explained beyond the bar itself.

### 1.6 The first-session inventory (what a reviewer sees before touching anything)

For a fresh save, `main_menu_screen.dart:120-141` renders, in order:
`START DRIVING` (yellow primary), `ENDLESS SHIFT`, `DAILY SHIFT` plus
`'$dayKey · ONE SHIFT, SAME FOR EVERYONE'` and a DAILY HISTORY link, then
GARAGE, RECORDS, SETTINGS, CREDITS (`:162-228`). The screen has no
descriptor lines under ENDLESS, GARAGE, or RECORDS, and the daily status
line is the only mode explanation on the whole menu. The visual identity is
the stock Material surface: a blue gradient (`main_menu_screen.dart:25-32`,
repeated in daily/garage/records/stats/settings) with Material icons and
white/yellow `ElevatedButton`s. The distinctive work is real but lives one
or two taps deeper.

---

## 2. Top five product / listing changes (concrete, on-device-only)

### 2.1 Fix the "original art" claim before a human sends the reply — highest risk

The paste-ready reply says (`2026-10-08-4.3a-response.md:20-22`), `'Its
code, its top-down sprite art, and its audio are original to this project'`,
and `fastlane/review_notes.txt:3-5` says `'the top-down sprite art drawn for
this game'`. The repo's own record contradicts both:

- `assets/licenses/LICENSES.txt:52-55` — `'### Vehicle sprites (Kenney.nl —
  Racing Pack) ... Source: Racing Pack'`; modifications listed at `:78-99`
  (five recolored bodies, an elongated bus, transparent padding).
- `credits.dart:31-35` — the in-app CREDITS screen says `'Vehicle sprites
  and interface icons by Kenney'` (one tap from the menu for the reviewer).
- `tool/make_vehicle_sprites.py:177` — the default player cab
  `'player/taxi_yellow.png', 'PNG/Cars/car_yellow_1.png'`, i.e. stock pack
  art with padding only.

Rewrite the reply/notes to claim only what is verifiably this project's own
— the code, the ten level layouts, the date-seeded course algorithm, the
living road renderer, the generated app icon (`tools/make_app_icon.swift`),
and the synthesized audio (`LICENSES.txt:37-46`) — and describe the vehicle
art accurately as CC0 pack art integrated, recolored, and re-proportioned
in-repo. A reviewer who opens Credits can see the contradiction today; under
4.3(a), shared pack assets are exactly what the guideline investigates, so
the reply should get ahead of it rather than deny it.

### 2.2 Make the two flagship screenshots actually capturable

`listing-copy.md:57-60` says `'The first two frames should show the Daily
Shift (ghost race) and a bank-or-push moment'` and points at
`tool/screenshot_entry.dart`. That tool cannot produce either frame:
`homeForShot` (`screenshot_entry.dart:111-117`) supports only
`game|garage|credits|settings|menu`, and the game shot is
`const GameScreen()` — the tutorial ladder's level 1, with no seed, no
daily flag, no ghost, and no live bank prompt. The file also references
`tool/capture_screenshots.sh` (`:12`) which does not exist in the repo.
Build the missing states: add `daily` / `ghost` / `bank` shot targets, seed
a save with a played day and a stored `GhostTrace` (ghost race with the
`GHOST +N m` badge visible) and with an endless run parked in the bank
prompt window (`BANK OR PUSH?` legible, `AT RISK` score nonzero), then
capture with the documented 1320×2868 / alpha-strip pipeline
(`CLAUDE.md:54-82`). Without this, the listing checklist item cannot be
executed as written.

### 2.3 Give the near-miss economy a lesson, a name, and a reward

Three small, on-device changes that together make the mechanic visible:

1. **A tutorial rung that teaches it.** Insert a lesson between "Keep the
   Chain" (8) and "Bank It" (9) — or retitle level 6 — whose completion
   requires e.g. 3 close calls. The level format already supports authored
   objectives; the pop (`close_call_pop.dart:17`) already names points.
2. **An achievement.** Add e.g. `close_shave` — `'Shave 25 close calls'` —
   to the catalog (`achievements.dart:227-243`) so the economy appears on
   the Records screen and in the unlock banners
   (`run_summary_panel.dart:223-274`).
3. **A lifetime row + a first-time hint.** Add a "Close calls" total to the
   Shift stats Totals card (`stats_screen.dart:154-170`; the per-shift
   `RunRecord` already carries the data, `run_record.dart:44-49`) and make
   the first close call say what it is, e.g. `'CLOSE CALL +15 — shaving
   pays'`, so the mechanic explains itself in the moment instead of only
   paying out.

This turns the hardest-to-copy idea in the game from an emergent accident
into a stated rule — for players and for a reviewer.

### 2.4 Put one descriptor line under the menu's mode buttons

The menu spends a status line on the Daily (`ONE SHIFT, SAME FOR EVERYONE`,
`main_menu_screen.dart:379-381`) but nothing on Endless beyond its label,
and never mentions the ghost. Add the same scale-down line idiom
(`:375-389`) under ENDLESS SHIFT for first-run saves — e.g.
`'3 crashes end it — bank or push at every dropoff'` — and extend the
Daily's played state to name the ghost, e.g. `'$date · RACE YOUR GHOST'`
when a trace exists. The menu is the reviewer's first screen; this is the
cheapest way to make the two modes read as designed rules instead of
labels. (`ENDLESS SHIFT` at `:278`, `BEST n` at `:293-294` are the only
current copy.)

### 2.5 Use What's New and the Credits screen to corroborate the identity

The resubmission's What's New (`fastlane/whats_new.txt:1-8`) currently
reads only stick/layout fixes and `'General stability and polish.'` — the
version page a reviewer reads says nothing about the game. Rewrite it to
name the modes and the resubmission's own work (e.g. `'Daily Shift with a
ghost of your best run', 'bank-or-push at every dropoff'`). Separately, the
Credits screen (`credits.dart:29-55`) is already honest and one tap away;
add the project's own line there too — date-seeded shared course, level
layouts, generated icon, synthesized audio made for this game — so the
screen a reviewer visits to check the originality claim affirms it rather
than only listing third-party packs.

---

## 3. Clone-read risks (what I checked)

1. **Pack art is the strongest remaining 4.3(a) signal.** Fifteen vehicle
   sprites come from Kenney's Racing Pack (CC0) — `LICENSES.txt:52-83`,
   `make_vehicle_sprites.py:175-199`. Only recolors, an elongation, and
   canvas padding distinguish them; the default player cab is stock pack
   art (`SPEC` line 177). A CC0 license answers the legal question but not
   the "is this the developer's own work" question a 4.3(a) reviewer asks;
   the Credits screen itself names Kenney. This is not fixable in the
   resubmission beyond honest framing (2.1) — the product-level fix is new,
   visibly original art for the default cab/first vehicles, which is real
   art work, not a code change.
2. **Default Flutter/Material look.** Every screen shares the same
   `Colors.blue.shade300 → shade600` gradient with white/yellow Material
   buttons (`main_menu_screen.dart:25-32` and its siblings in
   daily/garage/records/stats/settings) and stock Material icons
   (`Icons.local_taxi`, `Icons.play_arrow`, etc.). Checked all seven screens
   and `lib/main.dart`; nothing uses a custom font, wordmark, or shape
   language beyond the title text. It reads as a built-with-Flutter app
   before it reads as Cab Hustle.
3. **Name collision.** A web check for "Cab Hustle" finds an existing
   Commodore 64 game of the same name — a Space Taxi / Thrust style taxi
   game (`retrogamernation.com` "Cab Hustle (C64)", launchbox results
   listing it as inspired by Space Taxi, TurboRaketti, and Crazy Taxi). It
   is a different platform and genre, so it is not a store conflict, but
   the name is not unique in the taxi-game space and searching the name
   surfaces another taxi game. The listed subtitle (`listing-copy.md:17`,
   `'Daily & Endless Taxi Shifts'`) is the disambiguator and should stay.
4. **Prior-identity history is contained but recent.** The project began as
   a "Pick Me Up 3D" clone exercise; `specification.md`, notes, and READMEs
   named the reference game and were cleaned on 2026-10-08 (`087918d`,
   issue #214), and the guard test now denies competitor names in shipped
   surfaces (`original_identity_test.dart:19-32`, including
   `'pick me up'`, `'crazy taxi'`, `'traffic rider'`, `'smashy road'`,
   `'crossy road'`). I verified the shipped trees named in that test carry
   none of them (the test's own scope is `lib/`, `ios/`, `assets/`,
   `fastlane/`, `pubspec.yaml`). This is good news for re-review; it does
   not erase the fact that the reviewer already saw version 1.0.0.
5. **Copy and structure check.** Level names, fare names, and rank titles
   are generic but not imitative ("HOT STREAK", "TRAFFIC MENACE",
   `score_card.dart:83-86`; "First Ride" through "Graduation Shift"). No
   competitor name, character, or catchphrase appears in any string I read.
   App icon and world rendering are original code (`make_app_icon.swift`,
   `road_segment.dart`), which is the strongest artifact-level counter to
   the clone read.

---

## 4. What the prepared package already covers, and what it leaves

**Covered by the package:**

- A paste-ready Resolution Center reply naming all four differentiators,
  the on-device-only facts, and the request for reconsideration
  (`2026-10-08-4.3a-response.md:15-45`).
- Review notes written onto every submitted version by the submit lane,
  with a hard gate that refuses a submission without the file
  (`fastlane/review_notes.txt`; `Fastfile:288-330`, `set_review_notes`).
- Paste-ready listing copy for every ASC field, leading with the modes and
  avoiding generic `'3D taxi simulator'` phrasing
  (`listing-copy.md:13-53`; the anti-phrasing rule at
  `2026-10-08-4.3a-response.md:53-55`).
- A screenshot plan (first two frames = Daily ghost race and bank-or-push)
  and the 6.9-inch / no-alpha technical requirements (`listing-copy.md:55-60`,
  `CLAUDE.md:44-82`).
- Repo hygiene from issue #214: template scaffolding and competitor names
  removed from shipped surfaces, with `original_identity_test.dart` pinning
  it.
- Operational awareness that replying and resubmitting are human acts while
  the rejected submission holds App Store Connect (`issue #212`; `CLAUDE.md`
  release-gate section).

**Left for product work:**

- Correcting the art-originality claim (2.1) — the package must not ship a
  claim its own bundle disproves.
- Screenshot tooling/state seeding so the planned frames exist (2.2).
- In-app visibility of the near-miss economy (2.3) and first-run mode
  descriptors (2.4).
- What's New identity text (2.5).
- New original art for the most-seen sprites if the team wants the 4.3(a)
  answer to rest on more than copy (3.1).
- Applying and verifying the ASC listing by hand — `skip_metadata`
  (`listing-copy.md:7-9`) means no pipeline will do it; issue #212's
  checklist is still open and unchecked.

---

## Unverified

- **The live App Store Connect listing** (name, subtitle, description,
  keywords, screenshots actually attached to 1.0.0): the repo states the
  listing is maintained by hand and never overwritten
  (`listing-copy.md:7-9`); I cannot read ASC from here. The checklist in
  issue #212 shows the listing review as not yet done.
- **Whether the rejected build 1068 carried the review notes.** The notes
  file and lane guard were added 2026-10-08, the day of the rejection
  (commit `361977d`), and the Fastfile's own comment describes "a
  submission that never told the reviewer what is original about this game"
  (`Fastfile:291-294`) — consistent with the notes being new, but the
  within-day sequence is not provable from the repo.
- **Whether "Cab Hustle" is claimed on the App Store.** I checked the web
  for the name (found the C64 game) but did not and cannot query App Store
  Connect or the App Store search API from this slice.
- **The on-device first-session feel.** Everything above is judged from
  code, comments, and the prepared docs; running the app (flutter commands)
  was out of scope for this review.
- **Apple's exact reasoning beyond the quoted line.** The only quoted
  rejection text I found is in the Fastfile comment
  (`Fastfile:291-293`): "the app shares a similar binary, metadata, and/or
  concept as apps submitted to the App Store by other developers." The
  Resolution Center thread itself is in ASC, not the repo.
