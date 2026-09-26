import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/lives.dart';
import 'package:taxi_game/game/systems/run_summary.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
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
      MaterialApp(
        home: Scaffold(
          body: RunSummaryPanel(game: game, summary: summary),
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
}
