import 'dart:ui' as ui;

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

    test('a cone scrape shoves the cab away from the cone, in world space '
        '(issue #136)', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final env = game.environment!;

      final worksDistance = findDistance(
        env,
        (d) => env.constructionAt(d) != null,
      );
      expect(worksDistance, isNotNull, reason: 'seed 42 has roadworks');

      // Same warm-up as the softness test above: park the taxi near the
      // zone off the cone line and walk the real loop's beats so the
      // chunk and its cones mount. The fold (issue #30) the teleport
      // across ~worksDistance px provokes settles in these ticks —
      // before the ruling under test reads or writes any position.
      game.player.position =
          Vector2(env.roadAt(worksDistance!).leftX + 20, -worksDistance);
      for (var i = 0; i < 4; i++) {
        game.update(1 / 60);
        await drain();
      }
      final cone = game.world.children
          .whereType<RoadSegment>()
          .expand((chunk) => chunk.children.whereType<RoadObstacle>())
          .first;

      /// The cone's world centre via the chunk's own transform — the same
      /// ground truth the softness test uses, and deliberately not the
      /// absoluteCentre the fix reads, so these assertions judge the fix
      /// instead of mirroring it.
      Vector2 coneWorld() =>
          (cone.parent as RoadSegment).positionOf(cone.position);

      // Drive up-screen into the cone from below: the cab's centre
      // starts 12 px under the cone's (the boxes already overlap), at
      // scrape speed. "Away" is down-screen — back the way it came.
      final player = game.player;
      player.position = coneWorld() + Vector2(0, 12);
      player.velocity = Vector2(0, -120);
      game.update(1 / 60);
      await drain();
      game.update(1 / 60);

      // Where the cab ended, relative to the cone, in the world frame
      // both share. One approach tick (−2 px), the ruling's pushback
      // (+3 px along the true axis), one shed-speed tick (−0.7 px):
      // shoved away, the offset holds above ~11 px of its 12 px start;
      // shoved forward — the chunk-local bug, whose axis was dominated
      // by the thousands-of-px y mismatch between world and chunk
      // frames — it loses the pushback instead and lands near 6 px.
      // (The road clamp may nudge x, never y, so only y is asserted.)
      final offset = player.position.y - coneWorld().y;
      expect(offset, greaterThan(8.5),
          reason: 'the scrape must push the cab back off the cone, not '
              'forward into it');
      expect(offset, lessThan(20),
          reason: 'sanity: the pushback is 3 px, not a teleport');

      // The ruling's telemetry must be world-space too: the report used
      // to carry the cone's chunk-local position as its traffic
      // position — a point thousands of px from the road the contact
      // happened on, and far from the playerPosition printed beside it.
      expect(game.lastImpact, isNotNull);
      expect(game.lastImpact!.trafficPosition.distanceTo(coneWorld()),
          lessThan(1.5),
          reason: 'the report must name the cone where it actually stands');
      // The contact point guards the empty-intersection fallback, whose
      // midpoint used to average world and chunk-local centres; real
      // intersection points are world-space either way, so this pins
      // only that the recorded point sits on the actual touch.
      expect(game.lastImpact!.contactPoint.distanceTo(coneWorld()),
          lessThan(45),
          reason: 'the contact point belongs on the touch, not halfway to '
              'the chunk-local origin');
    });
  });

  group('the light pools are soft, not cut with a cookie (issue #142)',
      () {
    /// Rasterises the windshield layer alone into the 400x800 virtual
    /// resolution it draws in, then samples the alpha of its tint along
    /// the horizontal row through the cab. The overlay renders straight
    /// into the recorder exactly as GameWidget's canvas would — the
    /// world under it is irrelevant, only the tint and its cut-outs are
    /// under test.
    Future<ui.Image> rasteriseOverlay(EnvironmentOverlay overlay) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      overlay.render(canvas);
      return recorder.endRecording().toImage(400, 800);
    }

    test('the headlight pool fades from centre to rim, not a step',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      final overlay =
          game.camera.viewport.children.whereType<EnvironmentOverlay>().first;
      expect(overlay.isMounted, isTrue,
          reason: 'precondition: the overlay sized itself to the viewport');

      // Deepest night and nothing else over it: the tint under test is
      // 0.62 × 255 ≈ 158 alpha, with no fog card or rain streaks in the
      // way. Set directly — the run's own environment would overwrite
      // it on the next update, and the renderer, not the driver, is
      // what this test judges.
      overlay.darkness = 1.0;
      overlay.fogIntensity = 0;
      overlay.rainIntensity = 0;

      final image = await rasteriseOverlay(overlay);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final data = bytes!.buffer.asUint8List();

      // The cab's screen position, projected the same way the overlay's
      // own _playerScreenPos does, so the probes straddle its pool
      // whatever the camera settled at.
      final viewfinder = game.camera.viewfinder.position;
      final cx =
          (game.player.position.x - (viewfinder.x - 200)).round().clamp(0, 399);
      final cy =
          (game.player.position.y - (viewfinder.y - 400)).round().clamp(0, 799);

      int alphaAt(int x, int y) => data[(y * 400 + x) * 4 + 3];

      // The warm additive glow sits 117 px above the cab with a 60 px
      // radius, so this row never touches it: every alpha below is the
      // tint and its cuts alone.
      final centre = alphaAt(cx, cy);
      final at65 = alphaAt(cx + 65, cy);
      final at120 = alphaAt(cx + 120, cy);
      final outside = alphaAt(cx + 185, cy);

      // 185 px out clears both cut ovals (the 130 px ambient circle and
      // the headlight ellipse's 110 px half-width): the untouched tint.
      expect(outside, closeTo(158, 4),
          reason: 'beyond the beams the night tint stands at full '
              '0.62 alpha');

      // The gradient's falloff, not a step: strictly more tint at every
      // probe out from the centre, and the centre keeps a breath of it.
      // With the old BlendMode.clear the first three probes all read 0
      // — every covered pixel fully cleared, the gradient ignored — and
      // the tint jumped 0 → 158 in one pixel at the oval's rim.
      expect(centre, greaterThan(0),
          reason: 'the erase is graduated: even the pool centre keeps '
              'some tint instead of being zeroed');
      expect(centre, lessThan(30),
          reason: 'the pool centre is mostly clear');
      expect(centre, lessThan(at65),
          reason: 'the erase weakens away from the cab');
      expect(at65, lessThan(at120),
          reason: 'the falloff keeps climbing toward the rim');
      expect(at120, lessThan(outside),
          reason: 'the rim hands over to the full tint, not a cliff');
    });

    test('the fog bubble fades the same way (issue #142)', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      final overlay =
          game.camera.viewport.children.whereType<EnvironmentOverlay>().first;
      overlay.darkness = 0;
      overlay.fogIntensity = 1.0;
      overlay.rainIntensity = 0;

      final image = await rasteriseOverlay(overlay);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final data = bytes!.buffer.asUint8List();

      final viewfinder = game.camera.viewfinder.position;
      final cx =
          (game.player.position.x - (viewfinder.x - 200)).round().clamp(0, 399);
      final cy =
          (game.player.position.y - (viewfinder.y - 400)).round().clamp(0, 799);

      int alphaAt(int x, int y) => data[(y * 400 + x) * 4 + 3];

      // Fog's card is 0.55 × 255 ≈ 140; its bubble reaches a little
      // further than the night pool (149.5 px) with a longer throw.
      final centre = alphaAt(cx, cy);
      final at65 = alphaAt(cx + 65, cy);
      final at120 = alphaAt(cx + 120, cy);
      final outside = alphaAt(cx + 185, cy);

      expect(outside, closeTo(140, 4),
          reason: 'beyond the bubble the fog card stands at full '
              '0.55 alpha');
      expect(centre, greaterThan(0),
          reason: 'the bubble centre keeps some fog instead of being '
              'zeroed');
      expect(centre, lessThan(30), reason: 'the bubble centre is mostly clear');
      expect(centre, lessThan(at65), reason: 'the fog thins toward the cab');
      expect(at65, lessThan(at120), reason: 'and thickens back out again');
      expect(at120, lessThan(outside), reason: 'the rim hands over to the fog');
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
