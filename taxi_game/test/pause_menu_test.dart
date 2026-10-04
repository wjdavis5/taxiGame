import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';

import 'helpers/fake_audio_platform.dart';

/// The pause menu over a real game (issue #206).
///
/// No existing test pumps the real pause menu — the bank-or-push tests
/// stub the 'pauseMenu' overlay entry with a `SizedBox.shrink`
/// (bank_or_push_test.dart's mount helper) — so this file mounts the
/// whole [GameScreen] the way the menu pushes it and reads the menu the
/// game's own [TaxiGame.pauseGame] puts up.
///
/// The daily note under the buttons used to be one blanket line,
/// "Today's daily attempt is saved.", shown whenever the shift was the
/// daily — including right under BANK & QUIT, whose bank settles the
/// shift and records the day's result (`_finalizeRunSummary` →
/// `recordDailyResult`, first result per day wins): banking *ends* the
/// attempt. The note now branches on the at-risk score: both halves
/// when something can be banked, the plain reassurance only scoreless —
/// where quitting is the only exit on offer and the attempt really is
/// safe.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;

  setUp(() async {
    // The pause menu's buttons click; the fake keeps that harmless.
    installFakeAudioPlatform();
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  /// Pushes today's daily shift as a real route, the run-summary and
  /// back-swipe harnesses' shape: real sprite I/O only completes inside
  /// the test binding's real-async window, so the liveness wait runs in
  /// `runAsync` and the surrounding pumps are fixed durations — never
  /// `pumpAndSettle` over a live game.
  Future<TaxiGame> pushDailyShift(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          Provider<AudioService>.value(value: AudioService()),
          Provider<HapticsService>.value(value: HapticsService()),
          Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            key: ValueKey('beneath_daily'),
            body: SizedBox.expand(),
          ),
        ),
      ),
    );

    Navigator.push(
      tester.element(find.byKey(const ValueKey('beneath_daily'))),
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          endlessSeed: DailyShift.seedForDateKey(DailyShift.todayKey),
          isDailyShift: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

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
        reason: 'the daily shift must be live before the menu opens');
    expect(game.isDailyShift, isTrue,
        reason: 'precondition: the run is the day\'s one attempt');
    return game;
  }

  testWidgets('with a score at risk the daily note names banking as the '
      'attempt-ending exit (issue #206)', (tester) async {
    final game = await pushDailyShift(tester);

    // A score at risk through the same public seam the run-summary
    // harness settles shifts with: one near-miss is 15 points on the
    // chain, enough to put BANK & QUIT on the menu.
    game.fareChain.awardNearMiss();
    expect(game.score, greaterThan(0), reason: 'precondition: stake exists');

    game.pauseGame();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byKey(const ValueKey('pause_bank_button')), findsOneWidget,
        reason: 'precondition: the bank the note sits under is on offer');
    expect(
      find.textContaining("Quitting keeps today's daily attempt"),
      findsOneWidget,
      reason: 'the note must lead with the half that is still true',
    );
    expect(
      find.textContaining('Banking ends it'),
      findsOneWidget,
      reason: 'and say the half the old line contradicted: the button '
          'above it spends the attempt',
    );
    expect(find.text("Today's daily attempt is saved."), findsNothing,
        reason: 'the blanket line read as describing BANK & QUIT');
  });

  testWidgets('a scoreless daily keeps the plain reassurance (issue #206)',
      (tester) async {
    final game = await pushDailyShift(tester);

    expect(game.score, 0, reason: 'precondition: nothing at risk yet');

    game.pauseGame();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byKey(const ValueKey('pause_bank_button')), findsNothing,
        reason: 'no score, no bank on offer');
    expect(find.text("Today's daily attempt is saved."), findsOneWidget,
        reason: 'quitting is the only exit here, and the attempt '
            'genuinely survives it');
    expect(find.textContaining('Banking ends it'), findsNothing);
  });
}
