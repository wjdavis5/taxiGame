import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter/material.dart' show SizedBox;
import 'package:flutter/scheduler.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/models/save_data.dart';

/// PM diagnostic probe (device report 2026-09-28: "app is crashing, the
/// cab no longer shows up at all"). iOS delivers lifecycle events during
/// launch — apps mount inactive and flip to active at first frame — and
/// transient inactives arrive during world rebuilds. These probes fire
/// the real sequences against the real game to find the one that breaks.
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

  Future<TaxiGame> mountGame() async {
    final game = TaxiGame(
      levelLoader: LevelLoaderService(),
      gameState: gameState,
      endlessSeed: 42,
    )
      ..overlays.addEntry('levelComplete', (_, __) => const SizedBox.shrink())
      ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
      ..overlays.addEntry('pauseMenu', (_, __) => const SizedBox.shrink())
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

  test('probe: iOS launch sequence inactive-then-resumed around mount', () async {
    final game = TaxiGame(
      levelLoader: LevelLoaderService(),
      gameState: gameState,
      endlessSeed: 42,
    );
    game.onGameResize(Vector2(400, 800));
    // The app is inactive while the first frame is still being produced:
    // fire the event before onLoad has completed.
    game.lifecycleStateChange(AppLifecycleState.inactive);
    game.lifecycleStateChange(AppLifecycleState.resumed);
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    game.update(1 / 60);
    expect(game.isMounted, isTrue);
    expect(game.world.children, isNotEmpty);
  });

  test('probe: transient inactive during an active run then resumed', () async {
    final game = await mountGame();
    game.update(1 / 60);
    expect(game.isGameActive, isTrue, reason: 'endless run should be live');

    game.lifecycleStateChange(AppLifecycleState.inactive);
    game.lifecycleStateChange(AppLifecycleState.resumed);

    // The player walks back in through the pause menu.
    expect(game.overlays.activeOverlays, contains('pauseMenu'));
    game.resumeGame();
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60);
    }
    expect(game.isGameActive, isTrue);
  });

  test('probe: hidden arrives mid-restart (world swap window)', () async {
    final game = await mountGame();
    game.update(1 / 60);
    // Begin a fresh shift without letting its async steps drain, then
    // background the app inside that window.
    final restart = game.startEndlessRun(seed: 7);
    game.lifecycleStateChange(AppLifecycleState.hidden);
    await restart;
    game.lifecycleStateChange(AppLifecycleState.resumed);
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60);
    }
    expect(game.isGameActive, isTrue);
    expect(game.world.children, isNotEmpty);
  });

  test('probe: detached then resumed (worst case)', () async {
    final game = await mountGame();
    game.update(1 / 60);
    game.lifecycleStateChange(AppLifecycleState.detached);
    game.lifecycleStateChange(AppLifecycleState.resumed);
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60);
    }
    expect(game.isMounted, isTrue);
  });

  test('probe: fresh save, first game start on a level (tutorial path)', () async {
    final data = SaveData.createDefault();
    SharedPreferences.setMockInitialValues({
      StorageService.saveDataKey: jsonEncode(data.toJson()),
    });
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
    final game = await mountGame();
    game.update(1 / 60);
    expect(game.isGameActive, isTrue);
    expect(game.player.isMounted, isTrue, reason: 'the cab must exist');
  });
}
