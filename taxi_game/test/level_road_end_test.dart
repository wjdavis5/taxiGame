import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/road_segment.dart';
import 'package:taxi_game/game/components/traffic_spawner.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The level course's end (issue #31): a level's road is finite, and
/// since #16 gave levels a score worth chasing, players race up it until
/// the drawn road stops — and with no reverse and no bound on y, the
/// taxi ends up stranded on the grass with no way back. The contract
/// now: the street runs a named margin past the topmost zone, the taxi
/// noses against that end instead of leaving it, the end is painted
/// (barrier, stop line, crossing) so it reads before the taxi arrives,
/// and traffic never spawns or drives past it. Endless mode owns its own
/// coordinate space (issue #30) and is untouched.
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

  /// A game whose save sits at level 8 — the level the TestFlight report
  /// shows — mounted headlessly (the pattern flame_test uses) so
  /// component `onLoad` hooks run. [Game.mount] is what GameWidget calls
  /// in production; with it, mid-update adds are queued like the shipped
  /// game's.
  Future<TaxiGame> mountLevel8Game() async {
    final data = SaveData.createDefault()..currentLevel = 8;
    SharedPreferences.setMockInitialValues({
      StorageService.saveDataKey: jsonEncode(data.toJson()),
    });
    final storage = StorageService();
    await storage.init();
    final state = GameStateService(storage);
    await state.loadSaveData();
    final game = TaxiGame(
      levelLoader: LevelLoaderService(),
      gameState: state,
    )
      ..overlays.addEntry('levelComplete', (_, __) => const SizedBox.shrink())
      ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
      ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
      ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink())
      ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink());
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  /// Same, but built for an endless run: the mode whose road is infinite
  /// and whose behaviour must not change.
  Future<TaxiGame> mountEndlessGame(int seed) async {
    final game = TaxiGame(
      levelLoader: LevelLoaderService(),
      gameState: gameState,
      endlessSeed: seed,
    )
      ..overlays.addEntry('levelComplete', (_, __) => const SizedBox.shrink())
      ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
      ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
      ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink())
      ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink());
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  /// A pattern whose every lane spawns on every wave, for deterministic
  /// spawner coverage (the shipped level patterns roll probabilities).
  const floodPattern = TrafficPattern(
    name: 'test_flood',
    spawnInterval: 0.1,
    lanes: [
      TrafficLaneConfig(
        laneX: 150,
        speedRange: SpeedRange(min: 80, max: 80),
        spawnProbability: 1.0,
        oncoming: false,
      ),
      TrafficLaneConfig(
        laneX: 250,
        speedRange: SpeedRange(min: 80, max: 80),
        spawnProbability: 1.0,
        oncoming: false,
      ),
    ],
  );

  group('level mode: the extended course end', () {
    test('the road runs a named margin past the topmost zone', () async {
      final game = await mountLevel8Game();

      final topmostZoneY = [
        ...game.currentLevel.pickupPoints,
        ...game.currentLevel.dropoffPoints,
      ].map((p) => p.y).reduce(math.min);
      // Level 8's topmost zone, from the shipped asset — the report's
      // level really is the one mounted.
      expect(topmostZoneY, -800);

      // One named constant, generous but fixed (the ask: 600-800 px).
      expect(TaxiGame.levelRoadEndMargin, inInclusiveRange(600, 800));
      expect(game.levelRoadTopY,
          closeTo(topmostZoneY - TaxiGame.levelRoadEndMargin, 0.01));

      // The road's geometry starts exactly at that end — and still runs
      // well past the taxi's start, covering the whole course. The
      // bottom margin below the start is unchanged by this issue.
      final road = game.world.children.whereType<RoadSegment>().single;
      final roadRect = road.toAbsoluteRect();
      expect(roadRect.top, closeTo(game.levelRoadTopY!, 0.01));
      expect(roadRect.bottom,
          closeTo(game.player.position.y + 500, 0.01));
    });

    test('full throttle past the topmost zone noses against the street end',
        () async {
      final game = await mountLevel8Game();
      // Geometry under test, not traffic: clear the spawner so no crash
      // can end the level mid-drive.
      game.trafficSpawner.clear();
      final player = game.player;

      player.startAccelerating();
      var minY = player.position.y;
      for (var i = 0; i < 1800; i++) {
        // 30 simulated seconds: more than enough to cross the whole
        // level at the starter cab's top speed.
        game.update(1 / 60);
        minY = math.min(minY, player.position.y);
      }

      // (a) The taxi never left the extended road, however long the
      // throttle stayed down.
      final roadTop = game.levelRoadTopY!;
      expect(minY, greaterThanOrEqualTo(roadTop));

      // Its centre stops a car length inside the end (y grows downward,
      // so "short of the end" is road top + length): the nose presses
      // against the street's finish, fully on the road.
      expect(player.position.y, closeTo(roadTop + player.vehicleSize.y, 0.01));

      // (b) The road component's geometry still covers the taxi — every
      // corner of its body, not just its centre point.
      final roadRect =
          game.world.children.whereType<RoadSegment>().single.toAbsoluteRect();
      final half = player.vehicleSize / 2;
      final corners = [
        player.position - half,
        player.position + half,
        Vector2(player.position.x - half.x, player.position.y + half.y),
        Vector2(player.position.x + half.x, player.position.y - half.y),
      ];
      for (final corner in corners) {
        expect(
          roadRect.contains(corner.toOffset()),
          isTrue,
          reason: 'taxi corner $corner left the road rect $roadRect',
        );
      }

      // The end is a wall, not a trap: steering still answers there.
      final xBefore = player.position.x;
      player.setSteering(1);
      game.update(1 / 60);
      expect(player.position.x, isNot(xBefore));
    });

    test('the course end is painted — barrier, stop line, and crossing',
        () async {
      // Render a standalone level-mode segment and read the pixels back:
      // the top of the segment is the course end, and it must not be
      // bare asphalt fading into the grass.
      const length = 400.0;
      final segment = RoadSegment(position: Vector2(200, 40), length: length);
      await segment.onLoad();

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.translate(100, 40);
      segment.render(canvas);
      final image = await recorder.endRecording().toImage(400, 480);
      final bytes =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final data = bytes!.buffer.asUint8List();

      // Local segment coords (lx, ly) land at pixel (100 + lx, 40 + ly).
      // Raw RGBA bytes, so no colour-object channel getters.
      void expectRgb(double lx, double ly, int r, int g, int b, String what) {
        final o = ((40 + ly).round() * 400 + (100 + lx).round()) * 4;
        expect(data[o], closeTo(r, 3), reason: what);
        expect(data[o + 1], closeTo(g, 3), reason: what);
        expect(data[o + 2], closeTo(b, 3), reason: what);
      }

      // Hazard barrier right at the end: alternating red and white.
      expectRgb(12.5, 7, 0xD3, 0x2F, 0x2F, 'barrier red block');
      expectRgb(37.5, 7, 255, 255, 255, 'barrier white block');
      // A stop line below it.
      expectRgb(50, 24, 255, 255, 255, 'stop line');
      // Then the zebra crossing: white bars over asphalt.
      expectRgb(130, 37, 226, 226, 226, 'crossing bar');
      // And the treatment is an end, not a repaint: ordinary asphalt
      // resumes below it, clear of the centre line's dashes.
      expectRgb(130, 75, 0x40, 0x40, 0x40, 'asphalt below');
      expectRgb(130, 120, 0x40, 0x40, 0x40, 'asphalt further down');
    });
  });

  // The flood-spawner tests here simulate 30 s of traffic in 1800 frames
  // with hundreds of interleaved drains — roughly 1-2 s locally, but a
  // loaded CI runner can blow past dart's default 30 s per-test timeout,
  // which is exactly what blocked the ios-release.yml pipeline twice
  // (2026-09-27). The simulated window stays as long as it needs to be;
  // only the wall-clock budget grows.
  group('level mode: traffic and the course end', () {
    /// Lets pending component mounts finish before the next simulated
    /// tick (the endless-run test pattern): a mid-test `world.add` is
    /// queued, not live.
    Future<void> drain() async {
      for (var i = 0; i < 8; i++) {
        await Future<void>.value();
        await Future<void>.delayed(Duration.zero);
      }
    }

    Future<TrafficSpawner> installFloodSpawner(TaxiGame game, int seed) async {
      game.trafficSpawner.clear();
      final spawner =
          TrafficSpawner(pattern: floodPattern, random: math.Random(seed));
      game.trafficSpawner = spawner;
      game.world.add(spawner);
      await drain();
      return spawner;
    }

    test('nothing spawns past the course end', () async {
      final game = await mountLevel8Game();
      final spawner = await installFloodSpawner(game, 7);

      // Park the taxi against the street end; the camera follows it
      // there, so every spawn point now sits beyond the last asphalt.
      final roadTop = game.levelRoadTopY!;
      game.player.position = Vector2(
        TaxiGame.roadCenterX,
        roadTop + game.player.vehicleSize.y,
      );
      game.update(1 / 60);
      expect(game.camera.viewfinder.position.y,
          closeTo(roadTop + game.player.vehicleSize.y, 0.01));

      // Every wave rolls a guaranteed spawn; the end turns them all
      // away, so no vehicle ever materialises off the road.
      for (var i = 0; i < 1200; i++) {
        game.update(1 / 60);
      }
      expect(spawner.activeVehicleCount, 0);
      expect(game.world.children.whereType<TrafficVehicle>(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('same-direction traffic despawns at the end, never past it',
        () async {
      final game = await mountLevel8Game();
      final spawner = await installFloodSpawner(game, 11);

      // Park the taxi mid-street: waves spawn ahead of it and drive up
      // toward the course end.
      game.player.position = Vector2(TaxiGame.roadCenterX, 0);
      game.update(1 / 60);

      final roadTop = game.levelRoadTopY!;
      var sawSpawns = false;
      var minY = double.infinity;
      for (var i = 0; i < 1800; i++) {
        // 30 simulated seconds: traffic reaching the end at its slowest
        // legal speed arrives and despawns inside this window. Drain
        // once per spawn interval so each wave's queued mounts go live
        // before the next one (the tickAndSettle pattern).
        game.update(1 / 60);
        if (i % 6 == 5) await drain();
        final vehicles = game.world.children.whereType<TrafficVehicle>();
        if (vehicles.isNotEmpty) sawSpawns = true;
        for (final vehicle in vehicles) {
          minY = math.min(minY, vehicle.position.y);
          expect(
            vehicle.path.every((waypoint) => waypoint.y >= roadTop),
            isTrue,
            reason: 'a traffic path pointed past the street end',
          );
        }
      }

      expect(sawSpawns, isTrue, reason: 'the flood pattern must have spawned');
      // Traffic was still on the street at the end of the window, and no
      // vehicle ever drove beyond the end of it.
      expect(spawner.activeVehicleCount, greaterThan(0));
      expect(minY, greaterThanOrEqualTo(roadTop));
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('endless mode is untouched', () {
    test('no course end exists and the taxi drives past any level road end',
        () async {
      final game = await mountEndlessGame(42);
      game.trafficSpawner.clear(); // drive undisturbed, as above
      expect(game.isEndless, isTrue);
      // The level clamp does not exist in endless mode.
      expect(game.levelRoadTopY, isNull);

      final player = game.player;
      player.startAccelerating();
      for (var i = 0; i < 1500; i++) {
        game.update(1 / 60);
      }

      // Deeper than any level road would allow, still moving, still on
      // the run's own road.
      expect(player.position.y, lessThan(-2500));
      expect(player.velocity.y, lessThan(0));
      expect(game.runDistance, greaterThan(2500));
      expect(game.levelRoadTopY, isNull);
    });
  });
}
