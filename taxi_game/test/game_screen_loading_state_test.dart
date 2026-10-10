import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';
import 'package:taxi_game/ui/widgets/hud_overlay.dart';

import 'helpers/fake_audio_platform.dart';

/// The authored transition into a run (issue #265): tapping START DRIVING
/// used to land on a blank #1A1A1A rectangle while the level loaded.
/// `GameWidget`'s `loadingBuilder` now holds an on-brand frame — the
/// menu's blue field and CAB HUSTLE wordmark — until the road, the cab,
/// and the HUD are ready, and the game's load future covers the cab's
/// sprite, so the first live frame cannot show a carless road.
///
/// The HUD polls the game on a repeating timer, so the drives below pump
/// fixed durations — never pumpAndSettle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;

  setUp(() async {
    installFakeAudioPlatform();
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  /// The loading state's key, as [_RunLoadingState] mounts it.
  final loadingFinder = find.byKey(const ValueKey('game_loading_state'));

  /// Pumps a real [GameScreen] on a fresh save — an endless shift, the
  /// shortest live path — and returns the game it drives.
  Future<TaxiGame> pumpGameScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          Provider<AudioService>.value(value: AudioService()),
          Provider<HapticsService>.value(value: HapticsService()),
          Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        ],
        child: const MaterialApp(
          home: GameScreen(endlessSeed: 42),
        ),
      ),
    );
    final game = tester
        .widget<GameWidget<TaxiGame>>(find.byType(GameWidget<TaxiGame>))
        .game!;
    return game;
  }

  testWidgets('the loading state covers the blank window from navigation',
      (tester) async {
    await pumpGameScreen(tester);

    expect(loadingFinder, findsOneWidget,
        reason: 'the tap on START DRIVING must land on the authored '
            'transition, not a blank #1A1A1A rectangle');
    expect(find.text('CAB HUSTLE'), findsOneWidget,
        reason: 'the wordmark the menu taught the player carries into '
            'the loading state');
    expect(find.textContaining('STARTING THE ENGINE'), findsOneWidget,
        reason: 'the state says what it is waiting on');
  });

  testWidgets('the first live frame already carries the cab and the HUD',
      (tester) async {
    final game = await pumpGameScreen(tester);
    expect(loadingFinder, findsOneWidget,
        reason: 'precondition: the run is still loading');

    // Poll to the transition frame, alternating real event-loop time
    // (the load runs on real futures — level JSON and the cab's PNG)
    // with fake-clock frames. The cab is checked on the exact frame the
    // loading state retires: the first frame the road can be visible.
    var transitionSeen = false;
    for (var waitedMs = 0; waitedMs < 5000; waitedMs += 20) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
      if (loadingFinder.evaluate().isEmpty) {
        transitionSeen = true;
        expect(game.player.isMounted, isTrue,
            reason: 'the road opened without the cab mounted');
        expect(game.player.children.whereType<SpriteComponent>(), isNotEmpty,
            reason: 'the road opened with an unmounted cab sprite');
        expect(find.byType(HudOverlay), findsOneWidget,
            reason: 'the HUD rides the first live frame');
        break;
      }
    }
    expect(transitionSeen, isTrue,
        reason: 'the run never went live within the wait');
  });
}
