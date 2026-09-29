import 'dart:convert';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/road_segment.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The street must paint UNDER everything that drives on it (issue #40).
///
/// Device report 2026-09-28: "the cab no longer shows up at all" — and the
/// on-device probe run confirmed it is every Flame-world sprite (player
/// AND traffic), while the Flutter-widget surfaces (garage previews) kept
/// rendering. The mechanism: Flame paints siblings in priority order and
/// keeps equal priorities in add order, and nothing in the game used to
/// set a priority. The endless street is recycled *during* the run
/// (issue #11) — [RoadChunkManager.sync] adds every chunk from inside a
/// tick — so each chunk mounted after the setup-added taxi and painted
/// its opaque asphalt straight over it. Level mode escaped only because
/// its one [RoadSegment] happens to be added before the player. These
/// tests pin the layering itself: every road segment must sort before the
/// player and before any traffic, whatever order the pieces were added in.
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

  TaxiGame endlessGame(int seed) => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: seed,
      )
        ..overlays.addEntry('levelComplete', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('pauseMenu', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink());

  TaxiGame ladderGame() => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      )
        ..overlays.addEntry('levelComplete', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());

  /// Mounts [game] headlessly so component `onLoad` hooks run, then
  /// returns it. [Game.mount] is what GameWidget calls in production;
  /// with it, mid-update adds are queued and applied at the next tick
  /// start — the production behaviour this regression rides on.
  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  /// Lets pending component mounts finish before the next simulated tick.
  Future<void> drain() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.value();
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// One simulated tick plus the drains for everything it queued to
  /// mount, then a second tick so the queue is applied.
  Future<void> tickAndSettle(TaxiGame game) async {
    game.update(1 / 60);
    await drain();
    game.update(1 / 60);
    await drain();
  }

  /// The order Flame paints the world's children in: the children set is
  /// kept sorted by priority, ties in add order (flame 1.34.0,
  /// component.dart — "The smaller the priority, the sooner your component
  /// will be updated/rendered").
  List<Component> paintOrder(TaxiGame game) => game.world.children.toList();

  int lastRoadIndex(List<Component> order) =>
      order.lastIndexWhere((c) => c is RoadSegment);

  test('endless run: every recycled chunk paints under the taxi', () async {
    final game = await mountGame(endlessGame(42));
    await tickAndSettle(game);

    expect(game.roadChunks!.hasChunk(0), isTrue,
        reason: 'the chunk sync must have run for this probe to mean anything');

    final order = paintOrder(game);
    final playerIndex = order.indexOf(game.player);
    expect(playerIndex, greaterThanOrEqualTo(0),
        reason: 'the cab must be a direct world child');
    expect(lastRoadIndex(order), lessThan(playerIndex),
        reason: 'every road chunk must paint before the cab — the endless '
            'chunks are added mid-run, so without an explicit road layer '
            'they mount after the cab and paint over it (issue #40)');
  });

  test('endless run: chunks stay under the cab and traffic while driving',
      () async {
    final game = await mountGame(endlessGame(42));
    await tickAndSettle(game);

    // Drive the shift for real: chunks now recycle continuously ahead of
    // the moving camera, and the distance curve spawns traffic — all of
    // it added mid-run, all of it at the mercy of paint order.
    game.player.startAccelerating();
    for (var i = 0; i < 480; i++) {
      game.player.setSteering(math.sin(i * 0.037));
      game.update(1 / 30);
      if (i % 30 == 29) await drain();
    }
    await tickAndSettle(game);

    final order = paintOrder(game);
    final roadEnd = lastRoadIndex(order);
    final playerIndex = order.indexOf(game.player);

    expect(order.whereType<RoadSegment>(), isNotEmpty,
        reason: 'chunks must still be live after the drive');
    expect(roadEnd, lessThan(playerIndex),
        reason: 'chunks mounted while driving must still paint under the cab');

    final firstTrafficIndex =
        order.indexWhere((c) => c is TrafficVehicle, roadEnd + 1);
    expect(firstTrafficIndex, greaterThan(roadEnd),
        reason: 'traffic mounts mid-run too; every car must paint above the '
            'street (issue #40: the traffic vanished with the cab)');
  });

  test('level mode: the street paints under the cab it always did', () async {
    // A save at the first ladder rung, so onLoad takes the level path —
    // the mode whose add order (street first, cab second) always rendered
    // correctly. Pinned here so the road layer cannot regress it.
    final data = SaveData.createDefault()..currentLevel = 1;
    SharedPreferences.setMockInitialValues({
      StorageService.saveDataKey: jsonEncode(data.toJson()),
    });
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();

    final game = await mountGame(ladderGame());
    await tickAndSettle(game);

    final order = paintOrder(game);
    expect(order.whereType<RoadSegment>(), hasLength(1),
        reason: 'a level street is one finite segment');
    expect(lastRoadIndex(order), lessThan(order.indexOf(game.player)),
        reason: 'the level street must keep painting under the cab');
  });
}
