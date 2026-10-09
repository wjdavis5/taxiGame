# Cab Hustle

A portrait, one-thumb taxi game for iPhone, built with Flutter and the Flame
engine. Ships on the App Store as **Cab Hustle**; the repository and the
Flutter package keep their original `taxiGame` / `taxi_game` names.

Fully offline by design: no network calls, no analytics, no ads, no
in-app purchases. Progress is saved on-device; the only way a score leaves
the phone is the player handing it to the OS share sheet themselves.

## The game

You drive a cab up the street with one thumb: touch anywhere low on the
screen and drag — up for speed, down to brake, sideways to steer. Fares
appear ahead; pick up, deliver before the fare's countdown runs out, get
paid. A one-time hint names the control on the first start.

- **Endless Shift** — the main mode. The course is generated procedurally
  from a seed, so every shift is different. Delivering inside a fare's
  countdown pays `fare value × chain multiplier` and steps the multiplier
  up; a lapsed countdown breaks the chain. Every dropoff offers
  **bank or push**: end the shift and keep what the chain has earned, or
  ride on at a higher multiplier. Push is the default — banking is always
  deliberate — and a wreck forfeits everything unbanked. Three lives soften
  that gamble: the first two crashes cost a life and break the chain, the
  third ends the shift. Close calls on passed traffic, four fare types with
  different payouts and meters, and a road that changes width and profile
  with distance keep long runs varied.
- **Daily Shift** — one attempt a day on a course derived from the calendar
  date: the same course for every player, computed on-device, never
  fetched. Comparison is social — share the score card. Daily history is
  kept, and the recorded daily run can be raced again as a **ghost car**;
  the better of the two scores is the one that stands.
- **The ladder** — PLAY is the hand-made career ladder of ten levels; one
  crash fails a level and completion unlocks the next. Finishing it hands
  off to Endless.

## Beyond the shift

- **Garage** — eight vehicles, from the free Classic Cab up to The
  Executive. Each card shows the handling profile the physics actually
  reads (top speed, throttle, steering), and no car is best at everything:
  a purchase is a trade. Prices are sized against what an Endless Shift
  earns.
- **Records** — personal bests (best banked score, longest chain, furthest
  distance, most fares in one shift) and a fifteen-achievement set with
  visible progress. No leaderboards anywhere: there is no server.
- **Stats** — the last 200 shifts stored on-device: the instrument that
  stands in for the analytics the game does not have.
- **Share** — the end-of-run score card (score, best chain, distance, date,
  seed) is rendered to an image and handed to the OS share sheet through
  the app's own platform channel. Nothing is transmitted unless the player
  picks a destination.

## Feel

- **Audio** — a synthesized engine loop that tracks speed, brake squeal,
  impacts, fares, coins, jingles, and a music loop, behind the sound and
  music toggles in Settings. Effects and jingles are Kenney CC0 (converted
  to WAV); the engine, brake, and music loop are synthesized in-repo. Every
  bundled file is inventoried in `taxi_game/assets/licenses/LICENSES.txt`,
  and the test suite enforces that inventory.
- **Haptics** — crashes, fares, coins, and button presses are confirmed in
  the hand, behind the vibration toggle.

## Development

Requires Flutter 3.x (Dart 3). The Flutter project is the `taxi_game/`
subdirectory.

```bash
cd taxi_game
flutter pub get
flutter run          # on a simulator or device
flutter analyze      # must be clean before committing
flutter test         # full suite
```

CI runs `flutter analyze` and `flutter test` on every push and blocks the
release job on both.

## Releases

Pushing to `main` runs `.github/workflows/ios-release.yml`: analyze, test,
signed archive, upload to TestFlight. App Store review submission fires
only when `version:` in `taxi_game/pubspec.yaml` changes. The operating
manual for publishing, screenshots, and signing is [CLAUDE.md](CLAUDE.md).

## Repository layout

```
├── CLAUDE.md            # operating manual: identity, commands, publishing, conventions
├── specification.md     # the original game specification
├── docs/                # privacy policy and support pages, release plans
├── notes/               # early development notes (historical)
├── plans/               # early phase plans (historical)
├── tools/               # icon generation, PNG alpha stripping
└── taxi_game/           # the Flutter project
    ├── lib/game/        # Flame components and pure gameplay systems
    ├── lib/models/      # save data, records, achievements
    ├── lib/services/    # storage, audio, haptics, sharing
    ├── lib/ui/          # screens (menu, game, daily, garage, records,
    │                    #   stats, settings, credits) and widgets
    ├── assets/          # sprites, icons, audio, levels, licenses
    ├── tool/            # dev-only entry point, audio generation
    └── test/            # unit and widget tests
```

## Assets and licenses

Vehicle sprites, UI icons, sound effects, and jingles are Kenney work
released under CC0; the engine loop, brake squeal, and music loop are
synthesized in-repo and owned by the project. Nothing bundled requires
attribution; the per-file inventory lives in
`taxi_game/assets/licenses/LICENSES.txt` and the in-app Credits screen
carries the courtesy credit.

A learning project. Not affiliated with any other game or publisher.

Project repository: <https://github.com/wjdavis5/taxiGame>
