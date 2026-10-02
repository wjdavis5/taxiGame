import 'dart:convert';
import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/game/vehicle_sprites.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// Traffic keeps its headway (issue #146): no car drives through another.
/// Before the fix, every traffic car moved at its drawn speed and read no
/// other car, so a faster car passed straight through the slower one ahead
/// in its lane — the fleet spent 15-20 s of every 4-minute shift fused on
/// screen (measured on these very seeds: 1038/1235/1232 fused frames out
/// of 14,400 at seeds 42/7/20261001). The spawner now caps each car to the
/// traffic ahead of it before anything moves, and skips materialising a
/// car on top of one that already stands on the spawn line — including
/// one earlier in the same wave, which the children scan could never see
/// (issue #179).
///
/// These tests drive the real, mounted game — the live spawner, the live
/// vehicles, the live fold of the world — headlessly, as plain [test]s:
/// the drive loop needs real async hops between frames (sprite loads and
/// queued mounts settle in microtasks), and the widget test binding's
/// fake clock starves exactly those.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Mounts [game] headlessly (the mounting GameWidget performs) so every
  /// component's `onLoad` runs and mid-update adds take the queued path.
  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  late GameStateService gameState;

  /// Puts every vehicle sprite in the image cache so traffic `onLoad`s
  /// complete after a single microtask hop — no real-IO timing leaks into
  /// the drives.
  Future<void> preloadSprites(TaxiGame game) async {
    await game.images.load(
        VehicleSprites.playerSpritePath(gameState.selectedVehicle));
    for (final type in TrafficVehicleType.values) {
      await game.images.load(VehicleSprites.trafficSpritePath(type));
    }
  }

  TaxiGame endlessGame(int seed) => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: seed,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  test('a full-throttle shift never shows a fused pair (seeds 42/7/20261001)',
      () async {
    // A 4 px kiss in one axis is road paint and float; overlap deeper
    // than that in BOTH axes is two cars occupying one body.
    const tolerance = 4.0;
    // Floors that keep the pass honest: the drive must actually meet
    // traffic it could fuse with.
    var pairableFrames = 0;
    var worstOverlapX = 0.0;
    var worstOverlapY = 0.0;

    for (final seed in [42, 7, 20261001]) {
      final game = await mountGame(endlessGame(seed));
      await preloadSprites(game);

      // The cab is a ghost driver: hitbox inactive, full throttle,
      // mid-road. Its contacts (scrape pushbacks, pace caps, crash
      // stalls) would reshuffle the traffic this test is measuring, and
      // a stalled world would stop spawning it.
      game.player.children
          .whereType<RectangleHitbox>()
          .first
          .collisionType = CollisionType.inactive;
      game.player.setThrottle(1);

      for (var t = 0; t < 240 * 60; t++) {
        game.update(1 / 60);
        // One real-async hop per frame: exactly the breath the live
        // loop's frame boundary gives queued mounts and sprite loads.
        await Future<void>.delayed(Duration.zero);

        // In-view = centres inside the 400 px half-band plus a body's
        // overhang past either edge — the pairs a player can actually
        // see fuse.
        final camY = game.camera.viewfinder.position.y;
        final inView = game.world.children
            .whereType<TrafficVehicle>()
            .where((v) => (v.position.y - camY).abs() <= 460)
            .toList();
        if (inView.length >= 2) pairableFrames++;

        for (var i = 0; i < inView.length; i++) {
          for (var j = i + 1; j < inView.length; j++) {
            final a = inView[i];
            final b = inView[j];
            final overlapX = (a.vehicleSize.x + b.vehicleSize.x) / 2 -
                (a.position.x - b.position.x).abs();
            final overlapY = (a.vehicleSize.y + b.vehicleSize.y) / 2 -
                (a.position.y - b.position.y).abs();
            worstOverlapX = math.max(worstOverlapX, overlapX);
            worstOverlapY = math.max(worstOverlapY, overlapY);
            expect(
              overlapX <= tolerance || overlapY <= tolerance,
              isTrue,
              reason: 'seed $seed, t=${t ~/ 60}s: a ${a.vehicleType} and a '
                  '${b.vehicleType} share one body '
                  '(${overlapX.toStringAsFixed(1)}x'
                  '${overlapY.toStringAsFixed(1)} px overlap)',
            );
          }
        }
      }

      // The shift must still have been live — an ended run stops
      // spawning traffic and would pass vacuously.
      expect(game.isGameActive, isTrue,
          reason: 'seed $seed: the ghost cab never crashes; the shift must '
              'still be running after 240 s');
    }

    // And it must have judged real traffic, not an empty street.
    expect(pairableFrames, greaterThan(1000),
        reason: 'the drives must hold in-view pairs to judge '
            '(${(240 * 3 * 60)} frames driven)');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test("level 10's twin oncoming lanes never fuse one wave side by side",
      () async {
    // The tutorial-ladder defect (issue #179): a wave fires every lane on
    // one shared spawnY, and rung 10's pattern runs two oncoming lanes 40
    // px apart (x 160 and 200 — `oncoming` defaults to laneX <= 200). The
    // #146 gate scans world.children, but `add` only queues a component,
    // so the car the first oncoming lane accepted is still unmounted when
    // the second lane's gate runs — the gate is blind to its own wave.
    // Wide bodies overlap across those 40 px (a bus is 50 px across, and
    // (50+45)/2 beats 40 by 7.5), so roughly one wave in fifteen fused
    // two oncoming cars side by side and drove them down on the player
    // abreast. The spawner now keeps a per-wave ledger of accepted spawns
    // and gates each lane against it as well.
    //
    // A save parked on rung 10 ('Graduation Shift'), written through the
    // storage key the game state reads, so the mounted game boots
    // straight into the level whose pattern carries the twin lanes (the
    // tutorial ladder test's gameStateAtLevel pattern).
    final data = SaveData.createDefault()..currentLevel = 10;
    SharedPreferences.setMockInitialValues({
      StorageService.saveDataKey: jsonEncode(data.toJson()),
    });
    final storage = StorageService();
    await storage.init();
    final levelState = GameStateService(storage);
    await levelState.loadSaveData();

    final game = await mountGame(
      TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: levelState,
      )
        ..overlays.addEntry('levelComplete', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink()),
    );
    await preloadSprites(game);

    // The cab is a ghost and PARKED. Ghost, because its contacts would
    // reshuffle the traffic this test measures; parked, because a moving
    // cab would move the camera — and the fixed camera is exactly what
    // pins every wave to one spawnY, the shared line that makes two
    // lanes of one wave land on top of each other.
    game.player.children
        .whereType<RectangleHitbox>()
        .first
        .collisionType = CollisionType.inactive;

    // Same kiss allowance as the endless drive: 4 px in one axis is road
    // paint and float; deeper than that in BOTH axes is two cars in one
    // body.
    const tolerance = 4.0;
    var pairableFrames = 0;
    var oncomingPairFrames = 0;

    for (var t = 0; t < 240 * 60; t++) {
      game.update(1 / 60);
      await Future<void>.delayed(Duration.zero);

      final camY = game.camera.viewfinder.position.y;
      final inView = game.world.children
          .whereType<TrafficVehicle>()
          .where((v) => (v.position.y - camY).abs() <= 460)
          .toList();

      // Role as the sign of travel: oncoming drives down-screen. A car
      // standing at exactly zero — mounted this frame, its zero-offset
      // spawn waypoint not yet advanced — has no sign to read; pairs
      // touching one are skipped this frame, not judged, because a real
      // fusion persists for the seconds the headway rule needs to part
      // it and is scannable again within frames.
      final roles = <TrafficVehicle, int>{
        for (final v in inView)
          if (v.velocity.y != 0) v: v.velocity.y > 0 ? 1 : -1,
      };
      if (roles.length >= 2) pairableFrames++;

      for (var i = 0; i < inView.length; i++) {
        for (var j = i + 1; j < inView.length; j++) {
          final a = inView[i];
          final b = inView[j];
          final roleA = roles[a];
          final roleB = roles[b];
          if (roleA == null || roleB == null) continue;
          // Same role only (the gate's own scope): an oncoming car
          // abreast of same-direction traffic is two-way traffic passing
          // — exactly what a street is supposed to show — not a fusion.
          if (roleA != roleB) continue;
          if (roleA > 0) oncomingPairFrames++;
          final overlapX = (a.vehicleSize.x + b.vehicleSize.x) / 2 -
              (a.position.x - b.position.x).abs();
          final overlapY = (a.vehicleSize.y + b.vehicleSize.y) / 2 -
              (a.position.y - b.position.y).abs();
          expect(
            overlapX <= tolerance || overlapY <= tolerance,
            isTrue,
            reason: 't=${t ~/ 60}s: a ${a.vehicleType} and a '
                '${b.vehicleType} share one body '
                '(${overlapX.toStringAsFixed(1)}x'
                '${overlapY.toStringAsFixed(1)} px overlap)',
          );
        }
      }
    }

    // The drive must have stayed live — an ended level stops spawning and
    // would pass vacuously.
    expect(game.isGameActive, isTrue,
        reason: 'the ghost cab never crashes; level 10 must still be '
            'running after 240 s');
    // And it must have judged real traffic, with the twin oncoming lanes
    // actually meeting in view — the situation the ledger gate exists for.
    expect(pairableFrames, greaterThan(300),
        reason: 'the drive must hold in-view pairs to judge '
            '(${240 * 60} frames driven)');
    expect(oncomingPairFrames, greaterThan(100),
        reason: 'the twin oncoming lanes must actually have run abreast '
            'in view, or this measured nothing the gate gates');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a sports car behind a bus paces it instead of driving through it',
      () async {
    final game = await mountGame(endlessGame(42));
    await preloadSprites(game);
    // One tick so the endless machinery settles before the furniture
    // lands, and the drains so everything it queued is live.
    game.update(1 / 60);
    await Future<void>.delayed(Duration.zero);
    game.update(1 / 60);
    await Future<void>.delayed(Duration.zero);

    final laneX = game.environment!.roadAt(0).sameDirectionLaneX;
    List<Vector2> straightPath(double y) =>
        [Vector2(laneX, y), Vector2(laneX, y - 3000)];

    // The slow leader and the fast follower, one lane, well ahead of
    // the parked cab: the bus cruises at 40 · 0.6 = 24 px/s, the sports
    // car at 100 · 1.3 = 130 px/s. They start 140 px apart nose to
    // nose — a 62.5 px bumper gap, inside the sports car's
    // body-length-plus-margin engagement window, so the cap must hold
    // from the first tick.
    const busY = -300.0;
    final bus = TrafficVehicle(
      position: Vector2(laneX, busY),
      vehicleType: TrafficVehicleType.bus,
      baseSpeed: 40,
      path: straightPath(busY),
    )..game = game;
    const sportsY = busY + 140;
    final sports = TrafficVehicle(
      position: Vector2(laneX, sportsY),
      vehicleType: TrafficVehicleType.sportsCar,
      baseSpeed: 100,
      path: straightPath(sportsY),
    )..game = game;
    game.world.add(bus);
    game.world.add(sports);
    // Let both onLoads finish so they are fully in the world before the
    // first measured tick.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    var minBumperGap = double.infinity;
    var maxSportsSpeed = 0.0;
    for (var t = 0; t < 120; t++) {
      game.update(1 / 60);
      await Future<void>.delayed(Duration.zero);
      // The sports car rides behind the bus (larger y, toward the
      // camera), so the bumper gap grows with the y difference.
      final gap = (sports.position.y - bus.position.y) -
          (bus.vehicleSize.y + sports.vehicleSize.y) / 2;
      minBumperGap = math.min(minBumperGap, gap);
      maxSportsSpeed = math.max(maxSportsSpeed, sports.velocity.length);
    }

    // Uncapped (the bug), the sports car closes at 130 − 24 = 106 px/s
    // and is through the bus in well under a second. Paced, it may
    // never spend a frame faster than the bus's own cruise.
    expect(maxSportsSpeed, lessThan(30),
        reason: 'the follower must hold the bus\'s pace, not its own '
            '130 px/s — it closed at 106 px/s before issue #146');
    expect(minBumperGap, greaterThan(0),
        reason: 'bumper gap must never close: a negative gap is the '
            'fusion the issue names');
    // And the cap actually engaged — the pair is still together, the
    // sports car riding behind the bus at the gap it found.
    expect(minBumperGap, lessThan(90),
        reason: 'the pair must still be in each other\'s engagement '
            'window, or this measured two strangers passing');
    expect(sports.paceLimit, isNotNull,
        reason: 'the headway pass must still be pacing the follower');
  }, timeout: const Timeout(Duration(minutes: 1)));
}
