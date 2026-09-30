import 'dart:math' as math;

import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/burst_particles.dart';
import 'package:taxi_game/game/components/scrape_marker.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/systems/collision_rules.dart';
import 'package:taxi_game/game/systems/impact_fx.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
import 'package:taxi_game/game/vehicle_sprites.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';

/// Mounts [game] headlessly (the pattern flame_test uses) so component
/// `onLoad` hooks run, then returns it.

/// Advances game time by [seconds], in clamped frames (issue #36): no
/// single frame may consume more than [TaxiGame.maxUpdateDelta], so
/// fast-forwarding a shift means many small frames, never one giant
/// one — exactly the invariant the live game now runs under.
void advanceGameTime(TaxiGame game, double seconds) {
  var remaining = seconds;
  while (remaining > 0) {
    final step = math.min(remaining, TaxiGame.maxUpdateDelta);
    game.update(step);
    remaining -= step;
  }
}

Future<TaxiGame> mountGame(TaxiGame game) async {
  game.onGameResize(Vector2(400, 800));
  await game.onLoad();
  await game.ready();
  return game;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;

  /// The GameWidget tests below pump real frames, and the taxi and the bus
  /// register their hitboxes only from `onLoad` — which awaits the sprite
  /// PNG through the global `Flame.images` cache. A cold cache means real
  /// asset I/O, and fake-async pump time never completes real I/O: a test
  /// run on its own (no earlier test having warmed the cache) used to see
  /// `isGameActive` flip — the game sets it before the deferred mount —
  /// and then probe a taxi whose hitbox never registered (issue #62).
  /// Preloading the two sprites every GameWidget test drives turns each
  /// later `loadSprite` into a cache hit, a future already complete that
  /// any pump drains as a microtask — exactly the warm state the file
  /// already ran under when the whole file passed together.
  setUpAll(() async {
    await Flame.images.loadAll([
      VehicleSprites.playerSpritePath(VehicleSprites.defaultVehicleId),
      VehicleSprites.trafficSpritePath(TrafficVehicleType.bus),
      VehicleSprites.trafficSpritePath(TrafficVehicleType.sedan),
    ]);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  /// Headless games have no overlay builder map — the production one comes
  /// from [GameScreen]'s `GameWidget`. Register a stand-in so the crash
  /// path can add its overlay without tripping Flame's unknown-overlay
  /// assertion.
  TaxiGame freshGame() => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink());

  /// A bus standing still at [position] (zero speed, so tests control the
  /// closing geometry exactly).
  TrafficVehicle parkedBus(Vector2 position) => TrafficVehicle(
        position: position.clone(),
        vehicleType: TrafficVehicleType.bus,
        baseSpeed: 0,
        path: [position.clone(), Vector2(position.x, position.y - 3000)],
      );

  /// An oncoming bus driving down-screen at exactly [speed] px/s. The path
  /// starts well below the spawn point so its velocity is established in
  /// `onLoad`, before any test drives a tick.
  TrafficVehicle oncomingBus(Vector2 position, double speed) => TrafficVehicle(
        position: position.clone(),
        vehicleType: TrafficVehicleType.bus,
        baseSpeed: speed / 0.6, // undo the bus type's speed multiplier
        path: [
          Vector2(position.x, position.y + 3000),
          Vector2(position.x, position.y + 3001),
        ],
      );

  /// An oncoming sportsCar driving down-screen at exactly [speed] px/s —
  /// the striker of issue #58's report (its 147.5 px/s is a 1.3×-multiplied
  /// speed draw).
  TrafficVehicle oncomingSportsCar(Vector2 position, double speed) =>
      TrafficVehicle(
        position: position.clone(),
        vehicleType: TrafficVehicleType.sportsCar,
        baseSpeed: speed / 1.3, // undo the sportsCar type's multiplier
        path: [
          Vector2(position.x, position.y + 3000),
          Vector2(position.x, position.y + 3001),
        ],
      );

  /// Same-direction traffic driving up-screen at exactly [speed] px/s (the
  /// sedan's multiplier is 1.0) — the rear-end case: it closes on a slower
  /// cab from behind.
  TrafficVehicle follower(Vector2 position, double speed) => TrafficVehicle(
        position: position.clone(),
        vehicleType: TrafficVehicleType.sedan,
        baseSpeed: speed,
        path: [
          Vector2(position.x, position.y - 3000),
          Vector2(position.x, position.y - 3001),
        ],
      );

  group('ruling on contact', () {
    test('a low-speed brush is a scrape: run continues, taxi is slowed',
        () async {
      final game = await mountGame(freshGame());
      final player = game.player;

      // Slow taxi just under a parked bus: 40 px/s along the impact axis.
      player.position = Vector2(200, 100);
      player.velocity = Vector2(0, -40);
      final bus = parkedBus(Vector2(200, 80));
      game.world.add(bus);
      await game.ready();

      player.onCollisionStart({Vector2(200, 90)}, bus);

      // Still driving: a brush never ends the run.
      expect(game.isGameActive, isTrue);
      expect(game.overlays.activeOverlays, isNot(contains('levelFailed')));

      // The ruling is recorded as a scrape naming the vehicle.
      expect(game.lastImpact, isNotNull);
      expect(game.lastImpact!.severity, ContactSeverity.scrape);
      expect(game.lastImpact!.vehicleKind, 'bus');

      // Slowdown: the taxi keeps 35% of its speed...
      expect(player.velocity.y, closeTo(-40 * CollisionRules.scrapeSpeedKeep,
          1e-9));
      // ...and is pushed out of the overlap, away from the bus (down-screen).
      expect(player.position.y, closeTo(103, 1e-9));

      // Feedback names what was hit.
      expect(game.world.children.whereType<ScrapeMarker>().length, 1);
      expect(
        game.world.children.whereType<ScrapeMarker>().single.text,
        'Scraped a bus!',
      );
    });

    test('scrape feedback is rate-limited while grinding', () async {
      final game = await mountGame(freshGame());
      final player = game.player;
      player.position = Vector2(200, 100);
      player.velocity = Vector2(0, -40);
      final bus = parkedBus(Vector2(200, 80));
      game.world.add(bus);
      await game.ready();

      player.onCollisionStart({Vector2(200, 90)}, bus);
      player.onCollisionStart({Vector2(200, 90)}, bus);

      expect(game.world.children.whereType<ScrapeMarker>().length, 1);
    });

    test('a second contact from the same vehicle rules nothing (issue #42)',
        () async {
      final game = await mountGame(freshGame());
      final player = game.player;
      player.position = Vector2(200, 100);
      player.velocity = Vector2(0, -40);
      final bus = parkedBus(Vector2(200, 80));
      game.world.add(bus);
      await game.ready();

      player.onCollisionStart({Vector2(200, 90)}, bus);
      final yAfter = player.position.y;
      final vAfter = player.velocity.y;

      // The pushback separated the bodies, and a closing vehicle re-
      // establishes the overlap a frame or two later — a new episode as
      // far as collision detection knows. The vehicle already had its
      // one ruling, so this touch is nothing at all: no further pushback
      // (the loop that bulldozed a stopped cab backwards), no further
      // slowdown. Traffic drives on through.
      player.onCollisionStart({Vector2(200, 92)}, bus);

      expect(player.position.y, yAfter);
      expect(player.velocity.y, vAfter);
    });

    test('a re-contact at crash speed on an already-scraped vehicle rules '
        'a crash (issue #60)', () async {
      final game = await mountGame(freshGame());
      final player = game.player;

      // First touch: a gentle 40 px/s brush scrapes and marks the bus —
      // from then on it can never pay a second scrape response (#42).
      player.position = Vector2(200, 100);
      player.velocity = Vector2(0, -40);
      final bus = parkedBus(Vector2(200, 80));
      game.world.add(bus);
      await game.ready();

      player.onCollisionStart({Vector2(200, 90)}, bus);
      expect(game.lastImpact!.severity, ContactSeverity.scrape);

      // Second touch, same vehicle, now flat out: 150 px/s into the bus.
      // Before issue #60 a touched vehicle was a ghost — the re-contact
      // was dropped on the floor and the taxi drove straight through at
      // crash speed. The re-contact is still judged, and it rules.
      player.velocity = Vector2(0, -150);
      player.onCollisionStart({Vector2(200, 90)}, bus);

      expect(game.isGameActive, isFalse);
      expect(game.lastImpact!.severity, ContactSeverity.crash);
      expect(game.lastImpact!.vehicleKind, 'bus');
    });

    test('a grinding volley fires one feedback burst, but every scrape is '
        'recorded', () async {
      final game = await mountGame(freshGame());

      CrashReport scrapeReport() => CollisionRules.buildReport(
            severity: ContactSeverity.scrape,
            vehicleKind: 'bus',
            playerVelocity: Vector2(0, -40),
            playerPosition: Vector2(200, 100),
            trafficVelocity: Vector2.zero(),
            trafficPosition: Vector2(200, 80),
            contactPoint: Vector2(200, 90),
          );

      game.onScrape(scrapeReport());
      game.onScrape(scrapeReport());

      // One volley of everything (issue #42): particles and marker — and
      // the shake and sound they ride — not two of each at frame rate.
      expect(game.world.children.whereType<BurstParticles>().length, 1);
      expect(game.world.children.whereType<ScrapeMarker>().length, 1);

      // The record of what was hit always updates, cooldown or not.
      final latest = scrapeReport();
      game.onScrape(latest);
      expect(game.lastImpact, same(latest));
    });

    test('the scrape marker clears itself', () async {
      final game = await mountGame(freshGame());
      final player = game.player;
      player.velocity = Vector2(0, -40);
      final bus = parkedBus(Vector2(200, 80));
      game.world.add(bus);
      await game.ready();

      player.onCollisionStart({Vector2(200, 90)}, bus);
      final marker = game.world.children.whereType<ScrapeMarker>().single;

      // Once its lifetime elapses the marker removes itself.
      marker.update(ScrapeMarker.lifetime + 0.01);
      expect(game.world.children.whereType<ScrapeMarker>(), isEmpty);
    });

    test('a high-speed hit is a crash: run ends with a full report',
        () async {
      final game = await mountGame(freshGame());
      final player = game.player;

      // Taxi flat out (150) into an oncoming bus (60): 210 px/s closing.
      player.position = Vector2(200, 100);
      player.velocity = Vector2(0, -150);
      final bus = oncomingBus(Vector2(200, 40), 60);
      game.world.add(bus);
      await game.ready();

      player.onCollisionStart({Vector2(200, 70)}, bus);

      expect(game.isGameActive, isFalse);
      // The failure overlay waits out the crash hit-stop (issue #7).
      expect(game.hitStop.isActive, isTrue);
      expect(game.overlays.activeOverlays, isNot(contains('levelFailed')));
      advanceGameTime(game, ImpactFx.crashHitStopDuration + 0.01);
      expect(game.overlays.activeOverlays, contains('levelFailed'));
      expect(player.isAccelerating, isFalse);
      expect(player.steeringInput, 0);

      final report = game.lastImpact!;
      expect(report.severity, ContactSeverity.crash);
      expect(report.vehicleKind, 'bus');
      expect(report.playerSpeed, 150);
      expect(report.trafficSpeed, 60);
      expect(report.closingSpeedAlongImpact, 210);
      expect(report.explanation, contains('bus'));
      expect(report.explanation, contains('210.0'));
    });

    test('a stationary cab struck at speed is a scrape, not a crash '
        '(issue #58)', () async {
      final game = await mountGame(freshGame());
      final player = game.player;

      // The issue's exact scenario: hands off the stick, parked in the
      // centre lane, and an oncoming sportsCar collects the cab at
      // 147.5 px/s — over the 110 crash threshold, none of it the taxi's
      // doing. Before the fault gate this failed the tutorial level
      // without the player ever touching the controls.
      player.position = Vector2(200, 100);
      player.velocity = Vector2.zero();
      final car = oncomingSportsCar(Vector2(200, 40), 147.5);
      game.world.add(car);
      await game.ready();

      player.onCollisionStart({Vector2(185, 70)}, car);

      // Still a live run, no failure overlay.
      expect(game.isGameActive, isTrue);
      expect(game.overlays.activeOverlays, isNot(contains('levelFailed')));

      final report = game.lastImpact!;
      expect(report.severity, ContactSeverity.scrape);
      expect(report.closingSpeedAlongImpact, closeTo(147.5, 1e-9));
      expect(report.playerContribution, 0);
      // Neither the panel's wording nor the log's blames the player.
      expect(report.headline, 'A sportsCar ran into you — nothing lost.');
      expect(report.explanation, contains('not ruled against the taxi'));
    });

    test('a slower cab rear-ended by same-direction traffic is a scrape '
        '(issue #58)', () async {
      final game = await mountGame(freshGame());
      final player = game.player;

      // The literal rear-end: the cab crawls up-screen at 40 px/s and a
      // sedan it had overtaken closes from behind at 190 — 150 px/s of
      // closing, but the player's own velocity points away from the
      // striker, so none of it is the player's fault.
      player.position = Vector2(200, 100);
      player.velocity = Vector2(0, -40);
      final car = follower(Vector2(200, 200), 190);
      game.world.add(car);
      await game.ready();

      player.onCollisionStart({Vector2(200, 130)}, car);

      expect(game.isGameActive, isTrue);
      expect(game.overlays.activeOverlays, isNot(contains('levelFailed')));

      final report = game.lastImpact!;
      expect(report.severity, ContactSeverity.scrape);
      expect(report.closingSpeedAlongImpact, closeTo(150, 1e-9));
      expect(report.playerContribution, closeTo(-40, 1e-9));
      expect(report.headline, 'A sedan ran into you — nothing lost.');
    });

    test('no ruling is made once the level is over', () async {
      final game = await mountGame(freshGame());
      final player = game.player;
      player.velocity = Vector2(0, -150);
      final bus = parkedBus(Vector2(200, 80));
      game.world.add(bus);
      await game.ready();

      player.onCollisionStart({Vector2(200, 70)}, bus); // crash
      final recorded = game.lastImpact;
      player.onCollisionStart({Vector2(200, 90)}, bus); // later touch

      expect(game.lastImpact, same(recorded));
    });

    testWidgets(
        'real overlap through the collision pipeline ends the run',
        (tester) async {
      // The headless mount used elsewhere in this file never registers
      // hitboxes with the game's collision detection, so this test runs
      // the game through a real GameWidget and pumps actual frames.
      final game = freshGame();
      await tester.pumpWidget(GameWidget(game: game));
      // Level/sprite loading is real async I/O, which does not progress
      // under fake-async time; runAsync lets it finish. Wait for the
      // taxi's onLoad to have run — the hitbox this test's crash needs
      // registers there — not merely for the run to be live: isGameActive
      // flips before the deferred load, and a cold sprite fetch started
      // under fake-async time never completes at all (issue #62).
      await tester.runAsync(() async {
        for (var i = 0;
            i < 300 && !(game.isGameActive && game.player.isLoaded);
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      // Mounting rides a real game tick, which a zero-duration pump does
      // not deliver — one timed frame mounts the now-loaded taxi and its
      // hitbox with it.
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.isGameActive, isTrue);
      expect(game.player.isMounted, isTrue);

      final player = game.player;
      player.position = Vector2(200, 100);
      player.startAccelerating();
      player.velocity = Vector2(0, -150);
      final bus = oncomingBus(Vector2(200, 60), 60);
      game.world.add(bus);

      // A frame to mount the bus, then frames for the collision detection
      // to spot the (already overlapping) hitboxes and raise the crash,
      // and for the crash hit-stop to elapse so the failure overlay
      // appears (issue #7).
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (game.overlays.activeOverlays.contains('levelFailed')) break;
      }

      expect(game.isGameActive, isFalse);
      expect(game.overlays.activeOverlays, contains('levelFailed'));
      expect(game.lastImpact!.severity, ContactSeverity.crash);
      expect(game.lastImpact!.vehicleKind, 'bus');
    });

    testWidgets(
        'an oncoming bus cannot bulldoze a stopped cab off the start '
        '(issue #42)', (tester) async {
      // The report's scenario, on a real endless shift: the cab has
      // driven 14 m, the stick is released, and an oncoming bus collects
      // it. Before the fix, every re-contact scraped again — the bus
      // carried the cab backwards until the distance chip read 0 m and
      // the cab sat in empty sky below the start of the road.
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: 7,
      );
      await tester.pumpWidget(GameWidget(game: game));
      // As above (issue #62): wait for the taxi's onLoad, not just the
      // run going live — the bulldozing scenario needs the player's
      // hitbox registered before the first contact ruling, and the
      // sprite fetch behind it is real I/O fake-async time cannot run.
      await tester.runAsync(() async {
        for (var i = 0;
            i < 300 && !(game.isGameActive && game.player.isLoaded);
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      // One timed frame to mount the loaded taxi (see above).
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.isGameActive, isTrue);
      expect(game.player.isMounted, isTrue);

      // Kill the shift's own spawner so the only traffic is the bus.
      game.trafficSpawner.clear();
      final player = game.player;
      player.position = Vector2(200, -140); // 14 m up the course
      player.velocity = Vector2.zero(); // stopped, hands off
      final bus = oncomingBus(Vector2(200, -400), 50);
      game.world.add(bus);

      // About ten seconds of frames, as the report watched.
      for (var i = 0; i < 625; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!game.isGameActive) break;
      }

      // Still a live run: 50 px/s closing is scrape territory, never a
      // crash — and the scrape happened exactly once.
      expect(game.isGameActive, isTrue);
      expect(game.lastImpact!.severity, ContactSeverity.scrape);
      // The whole backwards motion is the one 3 px pushback; the bus
      // drove on through instead of riding the cab down the road.
      expect(
        player.position.y,
        closeTo(-140 + CollisionRules.scrapePushback, 0.5),
        reason: 'one nudge, not a ride',
      );
      // The start held: true distance never dipped below zero.
      expect(game.runDistance, greaterThan(0));
      expect(player.position.y, lessThanOrEqualTo(game.worldShift));
    });

    testWidgets(
        'a throttle-held taxi that scrapes a same-lane car never passes '
        'it (issue #60)',
        (tester) async {
      // The report's scenario: the taxi closes on slower same-lane
      // traffic, scrapes it once, and — throttle still held — used to
      // accelerate straight through the now-ghosted car at full speed.
      // The pace cap must hold the cab behind the car's bumper for as
      // long as their hitboxes overlap; steering around stays the
      // escape, and the stick is never touched here so the only way
      // forward is through the car.
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: 7,
      );
      await tester.pumpWidget(GameWidget(game: game));
      // As above (issue #62): wait for the taxi's onLoad, not just the
      // run going live — the sprite fetch behind it is real I/O
      // fake-async time cannot run.
      await tester.runAsync(() async {
        for (var i = 0;
            i < 300 && !(game.isGameActive && game.player.isLoaded);
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      // One timed frame to mount the loaded taxi (see above).
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.isGameActive, isTrue);
      expect(game.player.isMounted, isTrue);

      // Kill the shift's own spawner so the only traffic is the car.
      game.trafficSpawner.clear();
      final player = game.player;
      player.position = Vector2(200, -140);
      player.velocity = Vector2.zero();
      player.startAccelerating();

      // A sedan in the taxi's lane, 160 px up the road, driving away at
      // 60 px/s. The taxi tops out at 150, so it closes at up to 90 px/s
      // — scrape territory, never a crash — and the scrape leaves it at
      // 35% speed, from which it re-accelerates straight at the car.
      final car = follower(Vector2(200, -300), 60);
      game.world.add(car);

      // About twelve seconds of frames: without the cap the cab re-
      // reaches full speed within half a second of the scrape and pours
      // through the car well inside the first three.
      var taxiEverAhead = false;
      for (var i = 0; i < 750; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (player.position.y <= car.position.y) taxiEverAhead = true;
        if (!game.isGameActive) break;
      }

      // 90 px/s of closing is a scrape, so the run is still live...
      expect(game.isGameActive, isTrue);
      // ...and the cab never drew level with the car, let alone passed
      // it: it paced the sedan instead of driving through the ghost.
      expect(taxiEverAhead, isFalse,
          reason: 'the taxi must pace a scraped car, not pass through it');
    });

    testWidgets(
        'a rear-ended taxi is not pinned to the follower\'s speed '
        '(issue #66)',
        (tester) async {
      // The report's mirror of #60: a same-direction car ran into the
      // taxi's rear, and from then on full throttle could not pull
      // away. The pace cap fired on the overlap alone, with no
      // ahead/behind test, so the car stuck in the cab's rear clamped
      // the cab to that car's pace — a slow rear-ender became a rolling
      // anchor only steering could shake off. The cap must pace a car
      // the taxi rides BEHIND; traffic behind may never hold it back.
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: 7,
      );
      await tester.pumpWidget(GameWidget(game: game));
      // As above (issue #62): wait for the taxi's onLoad, not just the
      // run going live — the sprite fetch behind it is real I/O
      // fake-async time cannot run.
      await tester.runAsync(() async {
        for (var i = 0;
            i < 300 && !(game.isGameActive && game.player.isLoaded);
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      // One timed frame to mount the loaded taxi (see above).
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.isGameActive, isTrue);
      expect(game.player.isMounted, isTrue);

      // Kill the shift's own spawner so the only traffic is the car.
      game.trafficSpawner.clear();
      final player = game.player;
      player.position = Vector2(200, -140);
      // Already rolling at 60 px/s: the follower is faster, so it still
      // catches and touches the cab, but the cab clears the follower's
      // 120 within a couple of tenths — before the follower can travel
      // the half-car-length of overlap and become a car *ahead*. The
      // pin this test polices is a car stuck in the cab's rear.
      player.velocity = Vector2(0, -60);
      player.startAccelerating();

      // A sedan in the taxi's lane, its centre 47 px behind the taxi's
      // — a hair outside the boxes — driving up at 120 px/s. The cab is
      // accelerating away, so every bit of the closing is the
      // follower's own doing: the ruling is a scrape whatever the
      // closing (#58), and the run must stay live.
      final car = follower(Vector2(200, -93), 120);
      game.world.add(car);

      // About five seconds of frames: enough to touch, and — with the
      // ahead-only cap — pull clean away at full speed. Watch the
      // speed the whole way through, frame by frame after the clamp
      // has had its say in each.
      var maxSpeedReached = 0.0;
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        maxSpeedReached = math.max(maxSpeedReached, -player.velocity.y);
        if (!game.isGameActive) break;
      }

      // The rear-end is the follower's fault, not the taxi's.
      expect(game.isGameActive, isTrue);
      // Full throttle beats the follower's 120 once the touch is behind
      // it: the cab is never again clamped to a car in its own rear.
      expect(maxSpeedReached, greaterThan(120),
          reason: 'the cab must outrun a rear-ender at full throttle, '
              'not pace it');
      // And it actually pulled clear: the gap opens past the touch
      // instead of freezing on the follower's bumper.
      expect(car.position.y - player.position.y, greaterThan(100),
          reason: 'the follower must fall behind, not ride the cab');
    });

    testWidgets(
        'a rear-ended taxi that waits before accelerating is still not '
        'pinned (issue #74)',
        (tester) async {
      // The leak #66's centre comparison left open: "ahead" was
      // re-derived from live positions every frame, and a centre is a
      // moving target. A stopped cab rear-ended at 60 px/s sits still
      // while the follower drives through it; ~1 s later the
      // follower's centre has crossed the cab's, and the very car that
      // hit from behind now reads "ahead" — so the moment the throttle
      // finally comes in, the cap clamps the cab to the rear-ender's
      // own 60 px/s and holds it there. The ahead/behind ruling must
      // be frozen at the first touch, where the geometry says who ran
      // into whom.
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: 7,
      );
      await tester.pumpWidget(GameWidget(game: game));
      // As above (issue #62): wait for the taxi's onLoad, not just the
      // run going live — the rear-end scenario needs the player's
      // hitbox registered before the first contact ruling, and the
      // sprite fetch behind it is real I/O fake-async time cannot run.
      await tester.runAsync(() async {
        for (var i = 0;
            i < 300 && !(game.isGameActive && game.player.isLoaded);
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      // One timed frame to mount the loaded taxi (see above).
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.isGameActive, isTrue);
      expect(game.player.isMounted, isTrue);

      // Kill the shift's own spawner so the only traffic is the car.
      game.trafficSpawner.clear();
      final player = game.player;
      player.position = Vector2(200, -140);
      player.velocity = Vector2.zero(); // stopped, hands off the stick

      // A sedan in the taxi's lane, its centre 47 px behind the taxi's
      // — a hair outside the boxes — driving up at 60 px/s. Every bit
      // of the closing is the follower's own doing, so the touch is a
      // scrape whatever the closing (#58) and the run must stay live.
      final car = follower(Vector2(200, -93), 60);
      game.world.add(car);

      // ~1 s of frames still stopped: the touch lands in the first few
      // (60 px/s closes the hair between the boxes almost at once),
      // and over the full second the follower drives on through the
      // stationary body until its centre sits past the cab's — the
      // exact window where a per-frame centre comparison flips its
      // answer.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Only now does the driver answer the bump with the throttle.
      player.startAccelerating();

      // About seven seconds of frames, watching the speed the whole
      // way through, frame by frame after the clamp has had its say.
      var maxSpeedReached = 0.0;
      for (var i = 0; i < 400; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        maxSpeedReached = math.max(maxSpeedReached, -player.velocity.y);
        if (!game.isGameActive) break;
      }

      // The rear-end is the follower's fault, not the taxi's.
      expect(game.isGameActive, isTrue);
      // Pinned, the cab could never exceed the follower's 60; free, it
      // runs away to its 150 top speed.
      expect(maxSpeedReached, greaterThan(120),
          reason: 'a rear-ender the cab waited out must never pace the '
              'cab — the ruling is frozen at the first touch, not '
              're-derived from centres every frame');
      // And it actually pulled clear: the gap opens past the grind
      // instead of freezing on the follower's bumper.
      expect(car.position.y - player.position.y, greaterThan(100),
          reason: 'the follower must fall behind, not ride the cab');
    });

    test('the endless start clamps: no driving backwards past distance zero',
        () async {
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: 7,
      );
      // The endless-run mount (level_road_end's pattern): the road chunk
      // manager only arms its world in onMount, so a bare mountGame —
      // which never mounts the game — would leave the road unmanaged.
      game.onGameResize(Vector2(400, 800));
      await game.onLoad();
      // ignore: invalid_use_of_internal_member
      game.mount();
      await game.ready();
      final player = game.player;
      expect(game.isEndless, isTrue);
      expect(game.worldShift, 0);

      // Parked past the start line (true distance zero) — where a
      // bulldozing scrape series used to leave the cab in empty sky. The
      // clamp stops it exactly at the line, the mirror of the level
      // course's end clamp (#31).
      player.position = Vector2(200, 47);
      game.update(1 / 60);

      expect(player.position.y, 0.0);
      expect(game.runDistance, greaterThanOrEqualTo(0));
    });
  });

  group('danger telegraph', () {
    test('an oncoming car about to be hit shows its warning', () async {
      final game = await mountGame(freshGame());
      final player = game.player;
      player.position = Vector2(200, 100);
      player.startAccelerating();
      player.velocity = Vector2(0, -150);

      final bus = oncomingBus(Vector2(200, -80), 60);
      game.world.add(bus);
      await game.ready();

      expect(bus.isTelegraphing, isFalse);

      game.update(1 / 60);

      expect(bus.isTelegraphing, isTrue);
      expect(bus.dangerTimeToImpact, lessThan(1.1));
      expect(bus.dangerIndicator.isVisible, isTrue);
    });

    test('a car far up the road is not yet telegraphing', () async {
      final game = await mountGame(freshGame());
      final player = game.player;
      player.position = Vector2(200, 100);
      player.startAccelerating();
      player.velocity = Vector2(0, -150);

      final bus = oncomingBus(Vector2(200, -400), 60);
      game.world.add(bus);
      await game.ready();

      game.update(1 / 60);

      expect(bus.isTelegraphing, isFalse);
      expect(bus.dangerIndicator.isVisible, isFalse);
    });

    test('the warning hides once the level is over', () async {
      final game = await mountGame(freshGame());
      final player = game.player;
      player.position = Vector2(200, 100);
      player.velocity = Vector2(0, -150);

      final bus = oncomingBus(Vector2(200, -80), 60);
      game.world.add(bus);
      await game.ready();
      game.update(1 / 60);
      expect(bus.isTelegraphing, isTrue);

      player.onCollisionStart({Vector2(200, 70)}, bus); // crash
      // The crash hit-stop holds the world still first (issue #7); once
      // it ends, the resumed tick re-runs the telegraph check and hides.
      advanceGameTime(game, ImpactFx.crashHitStopDuration + 0.01);
      game.update(1 / 60);

      expect(bus.isTelegraphing, isFalse);
      expect(bus.dangerIndicator.isVisible, isFalse);
    });
  });

  group('failure overlay legibility', () {
    CrashReport busCrash() => CollisionRules.buildReport(
          severity: ContactSeverity.crash,
          vehicleKind: 'bus',
          playerVelocity: Vector2(0, -150),
          playerPosition: Vector2(200, 100),
          trafficVelocity: Vector2(0, 60),
          trafficPosition: Vector2(200, 40),
          contactPoint: Vector2(199.5, 70),
        );

    testWidgets('names the vehicle and the speed in words a player reads',
        (tester) async {
      final game = freshGame()..lastImpact = busCrash();

      await tester.pumpWidget(
        MaterialApp(home: LevelFailedOverlay(game: game)),
      );

      expect(find.text('CRASH!'), findsOneWidget);
      // The headline names what was hit and how hard, in words: the
      // telemetry belongs to the debug log, not the CRASH! panel.
      expect(find.text('You hit the bus flat out.'), findsOneWidget);
      expect(find.textContaining('px/s'), findsNothing,
          reason: 'no debug vocabulary on a player-facing panel');
    });

    testWidgets('without telemetry it still states the collision plainly',
        (tester) async {
      final game = freshGame();

      await tester.pumpWidget(
        MaterialApp(home: LevelFailedOverlay(game: game)),
      );

      expect(find.text('You collided with traffic.'), findsOneWidget);
    });
  });
}
