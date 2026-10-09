import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/levels/level.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';

import 'helpers/fake_audio_platform.dart';

/// A level load that throws must not surface as flame's raw error box
/// (issue #241): the PLAY path used to land on the framework's red
/// screen, with a PopScope vetoing back and no route out. GameWidget's
/// `errorBuilder` now answers with a recovery panel — MAIN MENU always,
/// RETRY when the load is the kind that can simply run again.
///
/// The fake loader replaces the asset read: the throw needs no bundle,
/// and the later stand-in success (the #229 test-only factory) proves
/// RETRY really re-runs the load without pulling real rung content into
/// the widget test.
class _FlakyLevelLoader extends LevelLoaderService {
  _FlakyLevelLoader({this.alwaysFail = false});

  /// The first load throws [LevelLoadException], later ones succeed.
  int _failures = 1;

  /// When true, every load throws — the corrupt-rung case a retry
  /// cannot save.
  final bool alwaysFail;

  @override
  Future<GameLevel> loadLevel(int levelNumber) async {
    if (alwaysFail || _failures > 0) {
      if (!alwaysFail) _failures--;
      throw LevelLoadException(
        levelNumber,
        'assets/levels/level_${levelNumber.toString().padLeft(3, '0')}.json',
        StateError('unreadable'),
      );
    }
    return GameLevel.createTestLevel();
  }
}

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

  /// Pushes a real [GameScreen] over a marker page, the back-swipe
  /// harness's shape: the screen must be a pushed route so MAIN MENU can
  /// be seen to land, and the game's own load fails from [loader].
  Future<void> pushFailedGame(
    WidgetTester tester,
    LevelLoaderService loader,
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          Provider<AudioService>.value(value: AudioService()),
          Provider<HapticsService>.value(value: HapticsService()),
          Provider<LevelLoaderService>.value(value: loader),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(
            key: ValueKey('beneath_failed_game'),
            body: SizedBox.expand(),
          ),
        ),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const GameScreen()),
    );
    // The loader's throw resolves on a microtask turn; two frames land
    // the loading -> error transition on the FutureBuilder.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a failed start shows the recovery panel, and MAIN MENU exits '
      '(issue #241)', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await pushFailedGame(
        tester, _FlakyLevelLoader(alwaysFail: true), navigatorKey);

    // The recovery surface, not flame's raw error box: the framework
    // would otherwise throw the load error into an ErrorWidget.
    expect(tester.takeException(), isNull,
        reason: 'the errorBuilder answers the throw instead of the '
            'framework printing its raw box');
    expect(find.byKey(const ValueKey('game_load_retry_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('game_load_menu_button')), findsOneWidget);
    expect(find.text('Level 1 could not be loaded.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('game_load_menu_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GameScreen), findsNothing,
        reason: 'MAIN MENU leaves the failed route');
    expect(find.byKey(const ValueKey('beneath_failed_game')), findsOneWidget,
        reason: 'the page under the game is uncovered again');
  });

  testWidgets('RETRY re-runs the load and brings the run live (issue #241)',
      (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    // One failure, then the stand-in loads: the retry's success is what
    // is under test, not the asset bundle.
    await pushFailedGame(
        tester, _FlakyLevelLoader(), navigatorKey);
    expect(find.byKey(const ValueKey('game_load_retry_button')), findsOneWidget,
        reason: 'precondition: the first load failed');

    await tester.tap(find.byKey(const ValueKey('game_load_retry_button')));

    // The retried game builds and loads on real futures (sprite I/O
    // included), so alternate real event-loop time with fake-clock
    // frames until the run is live — the control_hint assertion idiom.
    // The panel is answered only by the new future completing (flame's
    // FutureBuilder holds the old error snapshot through the retry), so
    // the wait is for both facts: the run live and the panel gone.
    final retryFinder = find.byKey(const ValueKey('game_load_retry_button'));
    TaxiGame? live;
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
      final finder = find.byType(GameWidget<TaxiGame>);
      if (finder.evaluate().isNotEmpty) {
        final game = tester.widget<GameWidget<TaxiGame>>(finder).game;
        if (game != null && game.isGameActive) live = game;
      }
      if (live != null && retryFinder.evaluate().isEmpty) break;
    }

    expect(live, isNotNull,
        reason: 'RETRY must re-run the load and bring the shift live');
    expect(retryFinder, findsNothing,
        reason: 'the recovery panel is gone once the reload landed');
  });
}
