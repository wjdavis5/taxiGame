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

import 'helpers/fake_audio_platform.dart';

/// The three bare-pop exits must be re-entry safe (issue #242).
///
/// The transitions' IgnorePointer only closes the double-tap window after
/// the first frame, so two taps inside that frame both reached the
/// handler: the first pop removed the GameScreen, and the second landed
/// on the route beneath — the menu, or the Daily screen that owns the
/// unspent attempt. Each handler carries the #220 route-current guard
/// now; only the current route's exits act. (The summary panels' own
/// `popUntil(isFirst)` exits are already idempotent and untouched.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const markerKey = ValueKey('beneath_pop_guard');

  late GameStateService gameState;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() async {
    installFakeAudioPlatform();
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
    navigatorKey = GlobalKey<NavigatorState>();
  });

  /// The menu-equivalent page under every pushed route: if a doubled pop
  /// takes it down too, the app has no route left and this marker is the
  /// observable casualty.
  Widget app() => MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          Provider<AudioService>.value(value: AudioService()),
          Provider<HapticsService>.value(value: HapticsService()),
          Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(
            key: markerKey,
            body: SizedBox.expand(),
          ),
        ),
      );

  /// Pushes [overlay] as a real route over the marker — a bare pop needs
  /// a route to leave and a route to land on.
  Future<void> pushOverlay(WidgetTester tester, Widget overlay) async {
    await tester.pumpWidget(app());
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => Scaffold(body: overlay)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// A mounted ladder game at the fresh save's level: the lazy fields the
  /// completion panel reads ([TaxiGame.currentLevel] among them) only
  /// exist after a real load. Real sprite I/O runs inside the binding's
  /// real-async window, the tutorial harness's pattern.
  Future<TaxiGame> mountLadderGame(WidgetTester tester) async {
    return (await tester.runAsync<TaxiGame>(() async {
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      )
        ..overlays.addEntry('levelComplete', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());
      game.onGameResize(Vector2(400, 800));
      await game.onLoad();
      // ignore: invalid_use_of_internal_member
      game.mount();
      await game.ready();
      return game;
    }))!;
  }

  /// Pumps the two post-pop frames plus the reverse transition, never
  /// pumpAndSettle over a live game (the HUD polls on a timer).
  Future<void> settlePop(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a doubled at-risk QUIT pops one route, not the menu under it '
      '(issue #242)', (tester) async {
    await tester.pumpWidget(app());
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const GameScreen(endlessSeed: 42),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final game = tester
        .widget<GameWidget<TaxiGame>>(find.byType(GameWidget<TaxiGame>))
        .game!;
    await tester.runAsync(() async {
      for (var i = 0;
          i < 300 && !(game.isGameActive && game.player.isLoaded);
          i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.isGameActive, isTrue,
        reason: 'the shift must be live before the menu opens');

    // A score at risk puts the bare-pop QUIT on the menu (the scoreless
    // exit is the idempotent popUntil).
    game.fareChain.awardNearMiss();
    game.pauseGame();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    final quit = tester.widget<TextButton>(
      find.byKey(const ValueKey('pause_quit_button')),
    );
    quit.onPressed!();
    quit.onPressed!();
    await settlePop(tester);

    expect(find.byType(GameScreen), findsNothing,
        reason: 'the first pop still quits the shift');
    expect(find.byKey(markerKey), findsOneWidget,
        reason: 'the refused second invocation must not pop the menu '
            'route beneath the game');
  });

  testWidgets(
      'a doubled level-complete MAIN MENU pops one route (issue #242)',
      (tester) async {
    final game = await mountLadderGame(tester);
    await pushOverlay(tester, LevelCompleteOverlay(game: game));

    final menu = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'MAIN MENU'),
    );
    menu.onPressed!();
    menu.onPressed!();
    await settlePop(tester);

    expect(find.text('MAIN MENU'), findsNothing,
        reason: 'the first pop still leaves the completion');
    expect(find.byKey(markerKey), findsOneWidget,
        reason: 'the refused second invocation must not pop the route '
            'beneath the completion');
  });

  testWidgets(
      'a doubled level-failed MAIN MENU pops one route (issue #242)',
      (tester) async {
    final game = await mountLadderGame(tester);
    await pushOverlay(tester, LevelFailedOverlay(game: game));

    final menu = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'MAIN MENU'),
    );
    menu.onPressed!();
    menu.onPressed!();
    await settlePop(tester);

    expect(find.text('MAIN MENU'), findsNothing,
        reason: 'the first pop still leaves the failure');
    expect(find.byKey(markerKey), findsOneWidget,
        reason: 'the refused second invocation must not pop the route '
            'beneath the failure');
  });
}
