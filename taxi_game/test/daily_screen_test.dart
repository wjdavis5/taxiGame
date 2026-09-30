import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/daily_result.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/daily_screen.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';
import 'helpers/fake_audio_platform.dart';
/// The Daily Shift screen (issue #19): today's result and the history
/// behind it — the two things a player checks before screenshotting their
/// score for the group chat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;
  late StorageService storage;

  setUp(() async {
    // The start button (issue #64) pushes a live GameScreen, whose audio
    // runs for real — hermetic platform fakes, the control-hint tests'
    // recipe for pumping live screens.
    installFakeAudioPlatform();
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          // GameScreen.initState reads the whole service stack, and the
          // start button pushes one — the provider set the game-screen
          // tests pump with.
          Provider<AudioService>.value(value: AudioService()),
          Provider<HapticsService>.value(value: HapticsService()),
          Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        ],
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
    // Nothing has been played at all, so the plain wording is the truth
    // here (issue #44).
    expect(find.text('No completed daily shifts yet.'), findsOneWidget);
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
    // Today has its card; it is not repeated in the history list. And
    // the empty history is worded for the past days — not the flat "no
    // completed shifts" that contradicted the card above it (issue #44).
    expect(find.byKey(const Key('daily_empty_history')), findsOneWidget);
    expect(
      find.text('No past daily shifts yet — come back tomorrow for a new '
          'course.'),
      findsOneWidget,
    );
    expect(find.text('No completed daily shifts yet.'), findsNothing);
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

    testWidgets('a tap after midnight refuses the next day\'s course '
        '(issue #96)', (tester) async {
      // Day D is played with its ghost stored, and the screen — its
      // result card and RACE YOUR GHOST — is built for D.
      final dayD = DailyShift.todayKey;
      await gameState
          .recordDailyResult(resultFor(dayD, score: 340));
      await plantGhost();
      await pumpScreen(tester);
      expect(find.byKey(const Key('daily_race_ghost_button')), findsOneWidget,
          reason: 'precondition: the button was built on day D');

      // Midnight passes with the screen left open. The Consumer only
      // rebuilds on a save change, so the card — and the day its tap is
      // guarded to — are still D's; the tap must not start D+1's course
      // as ghostless free practice (whose trace would become D+1's
      // ghost, overwriting D's).
      DailyShift.clock = () => DateTime.now().add(const Duration(days: 1));
      addTearDown(() => DailyShift.clock = DateTime.now);

      await tester.tap(find.byKey(const Key('daily_race_ghost_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(GameScreen), findsNothing,
          reason: 'no course started from a button built for yesterday');
      expect(gameState.ghostFor(DailyShift.todayKey), isNull,
          reason: "no practice trace was written as D+1's ghost");
      expect(gameState.ghostFor(dayD)!.score, 500,
          reason: "D's ghost survives untouched");
    });
  });

  group("the start-today's-shift button (issue #64)", () {
    testWidgets('an unplayed day offers to start the shift, not the ghost '
        'race', (tester) async {
      await pumpScreen(tester);

      final start = find.byKey(const Key('daily_start_button'));
      expect(start, findsOneWidget,
          reason: 'the card invites the player; the button accepts');
      expect(tester.widget<ElevatedButton>(start).onPressed, isNotNull);
      expect(find.text("START TODAY'S SHIFT"), findsOneWidget);
      // The one scoring attempt is unspent, and no run exists to race —
      // the race button belongs to a played day (issue #20).
      expect(find.byKey(const Key('daily_race_ghost_button')), findsNothing);
    });

    testWidgets("tapping it opens today's daily course, live", (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('daily_start_button')));
      await tester.pump(); // the route push
      // The HUD polls on a repeating timer, so fixed durations — never
      // pumpAndSettle (the game-screen tests' convention).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(GameScreen), findsOneWidget);
      final game = tester
          .widget<GameWidget<TaxiGame>>(find.byType(GameWidget<TaxiGame>))
          .game!;
      expect(game.isDailyShift, isTrue,
          reason: "this run is the day's one scoring attempt");
      expect(game.endlessSeed, DailyShift.seedForDateKey(DailyShift.todayKey),
          reason: 'the same date-derived course the menu button starts');
      expect(game.isGameActive, isTrue,
          reason: 'the daily course is running, not just mounted');
    });

    testWidgets('a played day offers no second attempt', (tester) async {
      await gameState
          .recordDailyResult(resultFor(DailyShift.todayKey, score: 340));

      await pumpScreen(tester);

      expect(find.byKey(const Key('daily_start_button')), findsNothing,
          reason: 'the daily is one shift a day — the spent attempt must '
              'not be re-offered here');
    });
  });
}
