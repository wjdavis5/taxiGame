import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/models/daily_result.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/daily_screen.dart';
/// The Daily Shift screen (issue #19): today's result and the history
/// behind it — the two things a player checks before screenshotting their
/// score for the group chat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<GameStateService>.value(
        value: gameState,
        child: const MaterialApp(home: DailyScreen()),
      ),
    );
    await tester.pump();
  }

  DailyResult resultFor(String dateKey, {int score = 100, bool banked = true}) {
    return DailyResult(
      dateKey: dateKey,
      score: score,
      banked: banked,
      completedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  String daysAgoKey(int days) =>
      DailyShift.dateKeyFor(DateTime.now().subtract(Duration(days: days)));

  testWidgets('a fresh player sees the invitation and an empty history',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const Key('daily_screen')), findsOneWidget);
    expect(find.byKey(const Key('daily_today_unplayed')), findsOneWidget);
    expect(find.byKey(const Key('daily_empty_history')), findsOneWidget);
    expect(find.byKey(const Key('daily_today_score')), findsNothing);
  });

  testWidgets("today's completed shift shows its score and outcome",
      (tester) async {
    await gameState
        .recordDailyResult(resultFor(DailyShift.todayKey, score: 340));

    await pumpScreen(tester);

    expect(find.text('340'), findsOneWidget);
    expect(find.byKey(const Key('daily_outcome_banked')), findsOneWidget);
    expect(find.byKey(const Key('daily_today_unplayed')), findsNothing);
    // Today has its card; it is not repeated in the history list.
    expect(find.byKey(const Key('daily_empty_history')), findsOneWidget);
  });

  testWidgets('a wrecked daily names the forfeit, not the payout',
      (tester) async {
    await gameState.recordDailyResult(
        resultFor(DailyShift.todayKey, score: 90, banked: false));

    await pumpScreen(tester);

    expect(find.text('90'), findsOneWidget);
    expect(find.byKey(const Key('daily_outcome_wrecked')), findsOneWidget);
    expect(find.byKey(const Key('daily_outcome_banked')), findsNothing);
  });

  testWidgets('past shifts list newest first, with how each ended',
      (tester) async {
    await gameState.recordDailyResult(resultFor(daysAgoKey(3), score: 120));
    await gameState.recordDailyResult(
        resultFor(daysAgoKey(1), score: 480, banked: false));
    await gameState.recordDailyResult(resultFor(daysAgoKey(2), score: 260));

    await pumpScreen(tester);

    final dateKeys = find.byType(Text).evaluate()
        .map((element) => (element.widget as Text).data)
        .whereType<String>()
        .where((text) => RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text))
        .where((text) => text != DailyShift.todayKey)
        .toList();
    expect(dateKeys, [daysAgoKey(1), daysAgoKey(2), daysAgoKey(3)],
        reason: 'the newest completed day comes first');

    expect(find.text('480'), findsOneWidget);
    // The outcome chip belongs to the today card only; history rows carry
    // a bank/wreck icon instead.
    expect(find.byKey(const Key('daily_outcome_wrecked')), findsNothing);
  });

  testWidgets('the back button pops the screen', (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const Key('daily_back_button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('daily_back_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('daily_screen')), findsNothing);
  });

  group('the ghost race entry (issue #20)', () {
    /// Plants a stored ghost for [dateKey] (today unless given).
    Future<void> plantGhost({String? dateKey, int score = 500}) async {
      await gameState.recordDailyGhostRun(
        dateKey: dateKey ?? DailyShift.todayKey,
        score: score,
        banked: true,
        vehicleId: 'taxi_yellow',
        samples: const [200, 0, 200, -100, 200, -200],
      );
    }

    testWidgets('a played day with a ghost offers the race', (tester) async {
      await gameState
          .recordDailyResult(resultFor(DailyShift.todayKey, score: 340));
      await plantGhost();

      await pumpScreen(tester);

      expect(find.byKey(const Key('daily_race_ghost_button')),
          findsOneWidget);
      expect(find.text('RACE YOUR GHOST'), findsOneWidget);
    });

    testWidgets('no ghost stored, no race offered', (tester) async {
      // Today is played, but no trace exists for the course (a save from
      // before issue #20, say).
      await gameState
          .recordDailyResult(resultFor(DailyShift.todayKey, score: 340));

      await pumpScreen(tester);

      expect(find.byKey(const Key('daily_race_ghost_button')), findsNothing);
    });

    testWidgets('a ghost from another day is no ghost at all',
        (tester) async {
      await gameState
          .recordDailyResult(resultFor(DailyShift.todayKey, score: 340));
      await plantGhost(
        dateKey: DailyShift.dateKeyFor(
            DateTime.now().subtract(const Duration(days: 1))),
      );

      await pumpScreen(tester);

      expect(find.byKey(const Key('daily_race_ghost_button')), findsNothing);
    });

    testWidgets('an unplayed day shows the invitation, not the race',
        (tester) async {
      await plantGhost();

      await pumpScreen(tester);

      expect(find.byKey(const Key('daily_today_unplayed')), findsOneWidget);
      expect(find.byKey(const Key('daily_race_ghost_button')), findsNothing);
    });
  });
}
