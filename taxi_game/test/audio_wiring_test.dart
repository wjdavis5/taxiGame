import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/collision_rules.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';

import 'helpers/fake_audio_platform.dart';

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

  // Issue #54: leaving a game screen silenced the menu for good. Flame's
  // GameWidget disposal fires a synthetic lifecycle pause, the game
  // suspended the whole audio service for it, and nothing on the menu
  // ever un-suspended — so the music died after every shift, and the
  // Settings toggle could not revive it while suspended.
  group('leaving a game hands the audio back to the menu (issue #54)', () {
    testWidgets('popping the game screen keeps the music alive and the '
        'toggle working', (tester) async {
      installFakeAudioPlatform();
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final gameState = GameStateService(storage);
      await gameState.loadSaveData();
      final menuAudio = AudioService();

      // The menu is playing music, the way main.dart starts it. runAsync:
      // FlameAudio's asset load is real async file I/O, which fake-async
      // time cannot run (audio_service_test.dart covers these calls in
      // plain test() bodies; a widget test has to hand them out).
      await tester.runAsync(() => menuAudio.playMusic());
      expect(menuAudio.isMusicWanted, isTrue);

      // Into a game — a live GameScreen carrying the same service.
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GameStateService>.value(value: gameState),
            Provider<AudioService>.value(value: menuAudio),
            Provider<HapticsService>.value(value: HapticsService()),
            Provider<LevelLoaderService>.value(value: LevelLoaderService()),
          ],
          child: const MaterialApp(home: GameScreen(endlessSeed: 42)),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(menuAudio.isMusicWanted, isTrue,
          reason: 'music runs in the shift too, not just on the menu');

      // Leave the game the way MAIN MENU does: the screen unmounts and
      // GameWidget's dispose fires the synthetic backgrounding.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pump();

      // The whole bug, in one expectation: leaving a game is not
      // backgrounding the app, so the service must not stay suspended.
      expect(menuAudio.isMusicWanted, isTrue,
          reason: 'the menu is still the foreground; the music survives '
              'the pop');

      // And the Settings toggle still does something the player can hear.
      await tester.runAsync(() => menuAudio.setMusicEnabled(false));
      expect(menuAudio.isMusicWanted, isFalse);
      await tester.runAsync(() => menuAudio.setMusicEnabled(true));
      expect(menuAudio.isMusicWanted, isTrue,
          reason: 'off/on must bring the music back (issue #4\'s toggle '
              'contract)');

      // The BGM player's position ticker outlives the tree — dispose the
      // service (its documented test/hot-restart purpose) so the test
      // ends with no live animation.
      await tester.runAsync(() => menuAudio.dispose());
    });
  });
}
