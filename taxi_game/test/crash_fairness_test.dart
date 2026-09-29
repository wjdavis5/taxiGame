import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/scrape_marker.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/systems/collision_rules.dart';
import 'package:taxi_game/game/systems/impact_fx.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
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
      // under fake-async time; runAsync lets it finish.
      await tester.runAsync(() async {
        for (var i = 0; i < 300 && !game.isGameActive; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump();
      expect(game.isGameActive, isTrue);

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
