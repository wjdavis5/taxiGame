import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/collision_rules.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The game's audio wiring (issue #4): a mounted game carrying a real
/// [AudioService] must actually reach for the right sounds at the right
/// gameplay moments. The service's playback itself is proven in
/// audio_service_test.dart — here it is the *routing* under test, observed
/// through `attemptedPlays` (nothing audible plays under flutter test).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;
  late StorageService storage;
  late AudioService audio;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    audio = AudioService();
  });

  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // Internal on purpose — the same call GameWidget makes (see
    // endless_run_test.dart for the full explanation).
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  TaxiGame endlessGame() => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        audio: audio,
        endlessSeed: 42,
      )
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink());

  CrashReport busCrash() => CollisionRules.buildReport(
        severity: ContactSeverity.crash,
        vehicleKind: 'bus',
        playerVelocity: Vector2(0, -150),
        playerPosition: Vector2(200, 100),
        trafficVelocity: Vector2(0, 60),
        trafficPosition: Vector2(200, 40),
        contactPoint: Vector2(199.5, 70),
      );

  CrashReport coneScrape() => CollisionRules.buildReport(
        severity: ContactSeverity.scrape,
        vehicleKind: 'traffic cone',
        playerVelocity: Vector2(0, -40),
        playerPosition: Vector2(200, 100),
        trafficVelocity: Vector2.zero(),
        trafficPosition: Vector2(210, 100),
        contactPoint: Vector2(200, 100),
      );

  test('an endless crash plays the crash sound once', () async {
    final game = await mountGame(endlessGame());

    game.onCrash(busCrash());

    expect(audio.attemptedPlays['crash'], 1,
        reason: 'the crash sound rides the same beat as the hit-stop');
  });

  test('a scrape plays the scrape sound', () async {
    final game = await mountGame(endlessGame());

    game.onScrape(coneScrape());

    expect(audio.attemptedPlays['scrape'], 1);
  });

  test('a grind plays the scrape sound once per cooldown, not per frame',
      () async {
    final game = await mountGame(endlessGame());

    // A grind reports a scrape on every contact frame (issue #49).
    for (var i = 0; i < 30; i++) {
      game.onScrape(coneScrape());
    }

    expect(audio.attemptedPlays['scrape'], 1,
        reason: 'one sound per frame flooded the audio platform channel; '
            'the sound rides the scrape marker cooldown (0.4 s)');
  });

  test('a muted service routes nothing, loudly or quietly', () async {
    audio.setSoundEnabled(false);
    final game = await mountGame(endlessGame());

    game.onCrash(busCrash());
    game.onScrape(coneScrape());

    expect(audio.attemptedPlays, isEmpty,
        reason: 'the save sound setting gates the game wiring too');
  });
}
