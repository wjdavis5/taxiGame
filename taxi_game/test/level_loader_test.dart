import 'dart:convert';
import 'dart:typed_data';

import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/levels/level.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The loader's honesty about failure (issue #229): a level the bundle
/// declares but cannot hand over must fail loudly — never substitute the
/// test level and drive a real save through it, and the Endless handoff
/// must come from the save's own state, never from a failed probe.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Serves exactly [files] (asset path → contents) to the asset bundle;
  /// anything else is missing.
  void serveAssets(Map<String, String> files) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List(
        message.offsetInBytes,
        message.lengthInBytes,
      ));
      final body = files[key];
      if (body == null) return null;
      return ByteData.sublistView(
        Uint8List.fromList(utf8.encode(body)),
      );
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('loadLevel', () {
    test('a declared level that fails to parse throws instead of becoming '
        'the Test Level', () async {
      serveAssets({'assets/levels/level_001.json': '{ this is not json'});

      // The old contract returned GameLevel.createTestLevel() here, so a
      // save at level 1 was driven through a stand-in and still unlocked
      // level 2 when it completed.
      await expectLater(
        LevelLoaderService().loadLevel(1),
        throwsA(isA<LevelLoadException>()),
      );
    });

    test('a missing level asset throws instead of masquerading as level 1',
        () async {
      serveAssets({});

      await expectLater(
        LevelLoaderService().loadLevel(7),
        throwsA(isA<LevelLoadException>()),
      );
    });

    test('a healthy level still loads and caches', () async {
      serveAssets({
        'assets/levels/level_002.json': jsonEncode(
          GameLevel.createTestLevel().toJson()
            ..['levelNumber'] = 2
            ..['name'] = 'Level Two',
        ),
      });
      final loader = LevelLoaderService();

      final level = await loader.loadLevel(2);
      expect(level.levelNumber, 2);
      expect(level.name, 'Level Two');
      // The second load answers from the cache, so removing the asset
      // changes nothing.
      serveAssets({});
      expect((await loader.loadLevel(2)).name, 'Level Two');
    });
  });

  group('the Endless handoff (issue #229)', () {
    /// A loader whose asset manifest is broken (every probe says the level
    /// is missing) and whose loads throw — the two failure modes of the
    /// issue, together.
    TaxiGame gameWithBrokenLoader(GameStateService gameState) =>
        TaxiGame(levelLoader: _ManifestBlindLevelLoader(), gameState: gameState);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('a level that is declared to the save but unreadable fails the '
        'load, never silently opens Endless', () async {
      final storage = StorageService();
      await storage.init();
      final gameState = GameStateService(storage);
      await gameState.loadSaveData();
      expect(gameState.currentLevel, 1);
      expect(gameState.tutorialComplete, isFalse);

      final game = gameWithBrokenLoader(gameState);
      game.onGameResize(Vector2(400, 800));

      // The probe says "missing", but a save inside the ladder is a level
      // run: the loader's typed failure must surface, and the game must
      // not have opened an endless shift behind it.
      await expectLater(game.onLoad(), throwsA(isA<LevelLoadException>()));
      expect(game.isEndless, isFalse);
    });

    test('a save past the ladder opens Endless from its own state, even if '
        'the probe claims a level exists', () async {
      final data = SaveData.createDefault()
        ..currentLevel = GameLevel.ladderLength + 1;
      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey: jsonEncode(data.toJson()),
      });
      final storage = StorageService();
      await storage.init();
      final gameState = GameStateService(storage);
      await gameState.loadSaveData();
      expect(gameState.tutorialComplete, isTrue);

      final game = TaxiGame(
        levelLoader: _AlwaysExistsBrokenLoader(),
        gameState: gameState,
      );
      game.onGameResize(Vector2(400, 800));

      // The old branch read the probe: a true `levelExists(11)` sent it
      // into loadLevel(11), and the thrown load was the only thing between
      // a finished save and its next shift.
      await game.onLoad();
      expect(game.isEndless, isTrue);
      expect(game.isGameActive, isTrue);
    });
  });
}

/// Every level probe answers false, as a manifest failure does; every load
/// throws, as an unreadable declared level does.
class _ManifestBlindLevelLoader extends LevelLoaderService {
  @override
  Future<bool> levelExists(int levelNumber) async => false;

  @override
  Future<GameLevel> loadLevel(int levelNumber) async {
    throw LevelLoadException(levelNumber, 'assets/levels/level_$levelNumber',
        StateError('unreadable'));
  }
}

/// Every level probe claims the level ships; every load throws.
class _AlwaysExistsBrokenLoader extends LevelLoaderService {
  @override
  Future<bool> levelExists(int levelNumber) async => true;

  @override
  Future<GameLevel> loadLevel(int levelNumber) async {
    throw LevelLoadException(levelNumber, 'assets/levels/level_$levelNumber',
        StateError('unreadable'));
  }
}
