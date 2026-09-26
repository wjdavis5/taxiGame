import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/environment_overlay.dart';
import 'package:taxi_game/game/components/road_obstacle.dart';
import 'package:taxi_game/game/components/road_segment.dart';
import 'package:taxi_game/game/systems/collision_rules.dart';
import 'package:taxi_game/game/systems/run_environment.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The living road in the running game (issue #24): the environment is
/// built from the run seed, the world reads its weather and time of day,
/// the taxi steers by its grip and is clamped by its kerbs, and its work
/// zones are real obstacles on the street.
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

  /// Mounts [game] headlessly (the pattern flame_test uses, plus the
  /// internal mount GameWidget performs) so component `onLoad` hooks run.
  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  TaxiGame endlessGame(int seed) => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: seed,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());

  Future<void> drain() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.value();
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// One tick plus the mounts it queued, then a second tick so the queue
  /// is applied.
  Future<void> tickAndSettle(TaxiGame game) async {
    game.update(1 / 60);
    await drain();
    game.update(1 / 60);
    await drain();
  }

  /// First distance at or after [from] where [predicate] holds, scanning
  /// in [step] px up to [to]. Deterministic per seed, so tests can
  /// legitimately depend on what they find — null means this seed never
  /// draws it, which its own group treats as a failure.
  double? findDistance(
    RunEnvironment env,
    bool Function(double distance) predicate, {
    double from = RunEnvironment.calmOpenDistance,
    double to = 250000,
    double step = 50,
  }) {
    for (var d = from; d <= to; d += step) {
      if (predicate(d)) return d;
    }
    return null;
  }

  group('an endless run has a living world', () {
    test('the environment is built from the run seed and reproducible',
        () async {
      final game = await mountGame(endlessGame(2026));

      expect(game.environment, isNotNull);
      expect(game.environment!.seed, 2026);

      final other = await mountGame(endlessGame(2026));
      for (var d = 0.0; d <= 100000; d += 10000) {
        expect(other.environment!.roadAt(d).width,
            game.environment!.roadAt(d).width, reason: 'road at $d');
        expect(other.environment!.darknessAt(d),
            game.environment!.darknessAt(d), reason: 'sky at $d');
      }
    });

    test('time of day becomes world state as the run drives on', () async {
      final game = await mountGame(endlessGame(42));

      // Departure: broad daylight everywhere.
      await tickAndSettle(game);
      expect(game.darkness, 0.0);
      final overlay =
          game.camera.viewport.children.whereType<EnvironmentOverlay>().first;
      expect(overlay.darkness, 0.0);

      // Drive past dusk into the night plateau (dayLength/2 = midnight).
      game.player.position = Vector2(200, -RunEnvironment.dayLength / 2);
      game.update(1 / 60);
      expect(game.darkness, closeTo(RunEnvironment.nightDarkness, 0.001));
      expect(overlay.darkness, closeTo(RunEnvironment.nightDarkness, 0.001));

      // And the sim's own difficulty read moves with it: the environment
      // modifier at midnight is material, and it folds into the traffic
      // profile the spawner is consuming.
      final env = game.environment!;
      const d = RunEnvironment.dayLength / 2;
      expect(env.difficultyModifierAt(d),
          greaterThan(RunEnvironment.nightPressure * 0.8));
    });

    test('rain reaches the steering: full lock loses its bite', () async {
      final game = await mountGame(endlessGame(42));
      final env = game.environment!;

      final rainDistance = findDistance(
        env,
        (d) => env.rainIntensityAt(d) > 0.9,
      );
      expect(rainDistance, isNotNull, reason: 'seed 42 meets heavy rain');

      // Park the taxi mid-road in the downpour and hold full lock.
      game.player.position = Vector2(200, -rainDistance!);
      game.update(1 / 60);
      game.player.setSteering(1);
      game.update(1 / 60);

      final expectedGrip = env.gripAt(rainDistance);
      expect(expectedGrip, lessThan(0.75),
          reason: 'the scan found a real downpour');
      expect(game.gripMultiplier, closeTo(expectedGrip, 0.001));
      expect(game.player.velocity.x,
          closeTo(game.player.steeringSpeed * expectedGrip, 0.001));
      expect(game.player.velocity.x, lessThan(game.player.steeringSpeed),
          reason: 'wet steering is slower steering');
    });

    test('the road clamp follows the narrow streets', () async {
      final game = await mountGame(endlessGame(42));
      final env = game.environment!;

      final narrowDistance = findDistance(
        env,
        (d) =>
            env.roadAt(d).profile == RoadProfile.narrow &&
            env.roadAt(d).width == RoadProfile.narrow.width,
      );
      expect(narrowDistance, isNotNull, reason: 'seed 42 has narrow streets');

      final road = env.roadAt(narrowDistance!);
      final player = game.player;
      final halfWidth = player.vehicleSize.x / 2;

      // Push the taxi into the left kerb: the clamp holds it at the edge
      // the narrow street actually has, not the classic 200 px road's.
      player.position = Vector2(road.leftX - 10, -narrowDistance);
      game.update(1 / 60);
      expect(player.position.x,
          greaterThanOrEqualTo(road.leftX + halfWidth - 0.01));

      player.position = Vector2(road.rightX + 10, -narrowDistance);
      game.update(1 / 60);
      expect(player.position.x,
          lessThanOrEqualTo(road.rightX - halfWidth + 0.01));
    });

    test('work zones put real cones on the street, and cones are soft',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final env = game.environment!;

      final worksDistance = findDistance(
        env,
        (d) => env.constructionAt(d) != null,
      );
      expect(worksDistance, isNotNull, reason: 'seed 42 has roadworks');

      // Bring the chunk under the taxi to life, then find its cones. The
      // taxi parks toward the kerb, off the cone line, so no touch is
      // spent before the test makes its own.
      game.player.position =
          Vector2(env.roadAt(worksDistance!).leftX + 20, -worksDistance);
      // A few drive ticks: the chunk under the taxi is created ahead of
      // the camera, mounted on the next tick, and its cones mount with
      // it — the real loop never stands still, the harness must walk the
      // same beats.
      for (var i = 0; i < 4; i++) {
        game.update(1 / 60);
        await drain();
      }
      final cones = game.world.children
          .whereType<RoadSegment>()
          .expand((chunk) => chunk.children.whereType<RoadObstacle>())
          .toList();
      expect(cones, isNotEmpty, reason: 'the zone renders its cone line');

      // Drive into the line at speed: the taxi sheds speed — a scrape —
      // and keeps all three lives. The speed is set directly so the
      // ruling and its effect are all that is under test.
      final player = game.player;

      // World-space centre of the first cone, via the chunk's own
      // transform (its local origin sits at the road box's top-left).
      final cone = cones.first;
      final chunk = cone.parent as RoadSegment;
      final coneWorld = chunk.positionOf(cone.position);
      player.position = coneWorld.clone();
      player.velocity = Vector2(0, -120);
      game.update(1 / 60);
      await drain();
      game.update(1 / 60);

      expect(game.lives.remaining, 3,
          reason: 'a cone never costs a life');
      expect(game.lastImpact, isNotNull);
      expect(game.lastImpact!.vehicleKind, 'traffic cone');
      expect(game.lastImpact!.severity.name, 'scrape');
      expect(-player.velocity.y,
          lessThan(120 * CollisionRules.scrapeSpeedKeep + 10),
          reason: 'the cone shed the taxi\'s speed');
    });
  });

  group('level mode keeps the classic street', () {
    test('no environment, dry grip, bright sky', () async {
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      );
      await mountGame(game);

      expect(game.environment, isNull);
      expect(game.gripMultiplier, 1.0);
      expect(game.darkness, 0.0);

      // Full lock steers at full stats: no weather to fight.
      final player = game.player;
      player.setSteering(1);
      game.update(1 / 60);
      expect(player.velocity.x, player.steeringSpeed);
    });
  });
}
