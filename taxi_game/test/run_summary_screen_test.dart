import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/systems/lives.dart';
import 'package:taxi_game/game/systems/run_summary.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';
import 'package:taxi_game/ui/widgets/run_summary_panel.dart';

/// The end-of-shift run summary panel (issue #15): the six numbers every
/// shift ends with, the personal-best callout, and a DRIVE AGAIN path
/// that restarts the shift in place.
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

  /// An unmounted endless game is enough: the panel reads only the
  /// settled summary (and the last impact explanation), and the retry
  /// button drives [TaxiGame.retryShift] — the HUD tests use the same
  /// unmounted-game pattern.
  TaxiGame endlessGame() => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: 9,
      );

  const bankedSummary = RunSummary(
    outcome: ShiftOutcome.banked,
    score: 240,
    bestChain: 4,
    faresDelivered: 12,
    distancePx: 12340,
    coinsEarned: 195,
    isPersonalBest: true,
    previousBest: 180,
  );

  const wreckedSummary = RunSummary(
    outcome: ShiftOutcome.wrecked,
    score: 90,
    bestChain: 3,
    faresDelivered: 5,
    distancePx: 620,
    coinsEarned: 40,
    isPersonalBest: false,
    previousBest: 180,
  );

  Future<void> showPanel(
    WidgetTester tester,
    TaxiGame game,
    RunSummary summary,
  ) async {
    await tester.pumpWidget(
      // The production panel lives inside the app's provider scope; the
      // ghost-race button it gained (issue #20) pushes a [GameScreen],
      // which reads the same services.
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: RunSummaryPanel(game: game, summary: summary),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a banked shift celebrates the payout over the full run '
      'record', (tester) async {
    final game = endlessGame();
    await showPanel(tester, game, bankedSummary);

    expect(find.text('SHIFT BANKED'), findsOneWidget);
    expect(find.text('+240 Coins'), findsOneWidget,
        reason: 'the banked payout is the headline');
    expect(find.text('Score'), findsOneWidget);
    expect(find.text('240'), findsOneWidget);
    expect(find.text('Best chain'), findsOneWidget);
    expect(find.text('\u00d74'), findsOneWidget);
    expect(find.text('Fares delivered'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('1.2 km'), findsOneWidget);
    expect(find.text('Coins earned'), findsOneWidget);
    expect(find.text('195'), findsOneWidget);
    expect(find.text('Forfeited: 240 coins'), findsNothing,
        reason: 'nothing was forfeited at a bank');
  });

  testWidgets('a wrecked shift names the forfeit over the same record',
      (tester) async {
    final game = endlessGame();
    await showPanel(tester, game, wreckedSummary);

    expect(find.text('SHIFT OVER'), findsOneWidget);
    expect(find.text('Three crashes — the shift is over.'),
        findsOneWidget, reason: 'the crash is explained, not swallowed');
    expect(find.text('Forfeited: 90 coins'), findsOneWidget);
    expect(find.text('62 m'), findsOneWidget);
    expect(find.text('Coins earned'), findsOneWidget);
    expect(find.text('40'), findsOneWidget,
        reason: 'only fare-base coins were ever paid');
    expect(find.text('+90 Coins'), findsNothing,
        reason: 'nothing was paid out at a wreck');
  });

  testWidgets('a beaten best gets the banner', (tester) async {
    final game = endlessGame();
    await showPanel(tester, game, bankedSummary);

    expect(find.byKey(const ValueKey('pb_banner')), findsOneWidget);
    expect(find.text('NEW PERSONAL BEST'), findsOneWidget);
    expect(find.text('Best: 180'), findsNothing);
  });

  testWidgets('an unbeaten run shows the best it failed to beat',
      (tester) async {
    final game = endlessGame();
    await showPanel(tester, game, wreckedSummary);

    expect(find.byKey(const ValueKey('pb_banner')), findsNothing);
    expect(find.text('Best: 180'), findsOneWidget);
  });

  testWidgets('DRIVE AGAIN restarts the shift in place — no menu stop',
      (tester) async {
    final game = endlessGame();
    await showPanel(tester, game, wreckedSummary);

    await tester.tap(find.byKey(const ValueKey('retry_button')));
    await tester.pump();

    expect(game.overlays.activeOverlays, isEmpty,
        reason: 'the summary panel stood down with the tap');
    expect(game.isGameActive, isTrue,
        reason: 'the player is driving again immediately');
    expect(game.lives.remaining, LivesTracker.maxLives,
        reason: 'the fresh shift has its full budget');
    expect(game.fareChain.score, 0, reason: 'a fresh shift, fresh chain');
    expect(game.lastRunSummary, isNull,
        reason: 'the settled shift is cleared');
  });

  group('a daily shift summary (issue #19)', () {
    TaxiGame dailyGame() => TaxiGame(
          levelLoader: LevelLoaderService(),
          gameState: gameState,
          endlessSeed: 9,
          isDailyShift: true,
        );

    testWidgets('says the day is settled and names what the retry starts',
        (tester) async {
      final game = dailyGame();
      await showPanel(tester, game, bankedSummary);

      expect(find.byKey(const ValueKey('daily_result_banner')), findsOneWidget);
      expect(find.text("TODAY'S DAILY IS IN"), findsOneWidget);
      expect(find.text('A new course arrives tomorrow.'), findsOneWidget);
      expect(find.text('ENDLESS SHIFT'), findsOneWidget,
          reason: 'the button names free play, not a daily replay');
      expect(find.text('DRIVE AGAIN'), findsNothing);
    });

    testWidgets('an ordinary shift shows neither the banner nor the '
        'free-play label', (tester) async {
      final game = endlessGame();
      await showPanel(tester, game, bankedSummary);

      expect(find.byKey(const ValueKey('daily_result_banner')), findsNothing);
      expect(find.text("TODAY'S DAILY IS IN"), findsNothing);
      expect(find.text('DRIVE AGAIN'), findsOneWidget);
    });

    testWidgets('the retry after a daily demotes the game to free play',
        (tester) async {
      final game = dailyGame();
      await showPanel(tester, game, wreckedSummary);

      await tester.tap(find.byKey(const ValueKey('retry_button')));
      await tester.pump();

      expect(game.isDailyShift, isFalse,
          reason: "the day's attempt is spent; the drive on is free play");
      expect(game.isGameActive, isTrue);
    });
  });

  group('the ghost race entry (issue #20)', () {
    Future<void> plantGhostForToday() async {
      await gameState.recordDailyGhostRun(
        dateKey: DailyShift.todayKey,
        score: 500,
        banked: true,
        vehicleId: 'taxi_yellow',
        samples: const [200, 0, 200, -100, 200, -200],
      );
    }

    TaxiGame dailyGame() => TaxiGame(
          levelLoader: LevelLoaderService(),
          gameState: gameState,
          endlessSeed: 9,
          isDailyShift: true,
        );

    TaxiGame ghostRaceGame() => TaxiGame(
          levelLoader: LevelLoaderService(),
          gameState: gameState,
          endlessSeed: 9,
          isGhostRace: true,
        );

    testWidgets('a settled daily with a stored ghost offers the race',
        (tester) async {
      await plantGhostForToday();
      await showPanel(tester, dailyGame(), bankedSummary);

      expect(find.byKey(const ValueKey('race_ghost_button')), findsOneWidget);
      expect(find.text('RACE YOUR GHOST'), findsOneWidget);
    });

    testWidgets('a ghost race summary offers the race again',
        (tester) async {
      await plantGhostForToday();
      await showPanel(tester, ghostRaceGame(), bankedSummary);

      expect(find.byKey(const ValueKey('race_ghost_button')), findsOneWidget);
    });

    testWidgets('free play never offers it, ghost or no ghost',
        (tester) async {
      await plantGhostForToday();
      await showPanel(tester, endlessGame(), bankedSummary);

      expect(find.byKey(const ValueKey('race_ghost_button')), findsNothing,
          reason: 'a ghost only ever attaches to the daily course');
    });

    testWidgets('a daily with no stored ghost has nothing to race',
        (tester) async {
      await showPanel(tester, dailyGame(), bankedSummary);

      expect(find.byKey(const ValueKey('race_ghost_button')), findsNothing);
    });

    testWidgets('tapping the button opens a ghost race of today\'s course',
        (tester) async {
      await plantGhostForToday();
      await showPanel(tester, dailyGame(), bankedSummary);

      await tester.tap(find.byKey(const ValueKey('race_ghost_button')));
      // Two pumps: start the push transition, then run it out — the
      // panel must never pumpAndSettle over a live game.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(GameScreen), findsOneWidget);
    });
  });
}
