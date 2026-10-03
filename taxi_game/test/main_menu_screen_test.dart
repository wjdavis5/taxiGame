import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/models/daily_result.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/main_menu_screen.dart';
import 'package:taxi_game/ui/screens/records_screen.dart';
import 'helpers/calendar_days.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildMenu(GameStateService gameState, StorageService storage) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<GameStateService>.value(value: gameState),
        Provider<AudioService>.value(value: AudioService()),
        Provider<StorageService>.value(value: storage),
      ],
      child: const MaterialApp(
        home: MainMenuScreen(),
      ),
    );
  }

  testWidgets('displays current level and coin total', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    gameStateService.addCoins(75);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('75 Coins'), findsOneWidget);
    expect(find.text('CAB HUSTLE'), findsOneWidget);
  });

  testWidgets('play button is present and enabled', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final playButton = find.byKey(const ValueKey('play_button'));
    expect(playButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(playButton).onPressed, isNotNull);
  });

  testWidgets('garage button is present and enabled', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final garageButton = find.byKey(const ValueKey('garage_button'));
    expect(garageButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(garageButton).onPressed, isNotNull);
  });

  testWidgets('endless shift button is present and enabled', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final endlessButton = find.byKey(const ValueKey('endless_button'));
    expect(endlessButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(endlessButton).onPressed, isNotNull);
    expect(find.text('ENDLESS SHIFT'), findsOneWidget);
  });

  testWidgets('on a fresh save the ladder leads — the designed on-ramp '
      'is the headline action, and the one-attempt daily stands back',
      (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final playButton = find.byKey(const Key('play_button'));
    final endlessButton = find.byKey(const ValueKey('endless_button'));
    final dailyButton = find.byKey(const ValueKey('daily_button'));
    expect(find.text('START DRIVING'), findsOneWidget,
        reason: 'the first-run label names the on-ramp');
    expect(
      tester.getRect(playButton).top,
      lessThan(tester.getRect(endlessButton).top),
      reason: 'a first-timer is led to the ladder, not the daily gamble',
    );
    expect(
      tester.getRect(endlessButton).top,
      lessThan(tester.getRect(dailyButton).top),
      reason: 'the daily — one attempt a day — comes last for a first-timer',
    );

    // And the on-ramp is styled as the headline: the yellow signature
    // colour, while the mode buttons step back in white.
    final playColor =
        tester.widget<ElevatedButton>(playButton).style?.backgroundColor;
    final endlessColor =
        tester.widget<ElevatedButton>(endlessButton).style?.backgroundColor;
    expect(playColor, isNot(endlessColor),
        reason: 'only the on-ramp is styled like the headline');
  });

  testWidgets('a finished save keeps the retained order: daily first, '
      'endless the headline beneath it (issues #15, #19)', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);
    // Climb the whole ladder: the save now sits past the last rung.
    for (var level = 1; level <= 10; level++) {
      gameStateService.completeLevel(level, 0);
    }
    expect(gameStateService.tutorialComplete, isTrue);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final dailyButton = find.byKey(const ValueKey('daily_button'));
    final endlessButton = find.byKey(const ValueKey('endless_button'));
    final playButton = find.byKey(const Key('play_button'));
    expect(
      tester.getRect(dailyButton).top,
      lessThan(tester.getRect(endlessButton).top),
      reason: "today's shared course leads a retained player's menu",
    );
    expect(
      tester.getRect(endlessButton).top,
      lessThan(tester.getRect(playButton).top),
      reason: 'endless sits above the career ladder',
    );
    expect(find.text('PLAY'), findsOneWidget,
        reason: 'the finished save keeps the plain PLAY label');
  });

  testWidgets('the personal best shows under the endless button once a '
      'shift has ended (issue #15)', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();
    expect(find.text('BEST 340'), findsNothing,
        reason: 'a new player has no best to show');

    gameStateService.recordEndlessScore(340);
    await tester.pump();

    expect(find.text('BEST 340'), findsOneWidget);
  });

  testWidgets('records button is present and opens the records screen',
      (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final recordsButton = find.byKey(const Key('records_button'));
    expect(recordsButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(recordsButton).onPressed, isNotNull);
    expect(find.text('RECORDS'), findsOneWidget);

    await tester.ensureVisible(recordsButton);
    await tester.tap(recordsButton);
    await tester.pumpAndSettle();

    expect(find.byType(RecordsScreen), findsOneWidget);
  });

  group('daily shift (issue #19)', () {
    testWidgets('button is present and enabled with today\'s date status',
        (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      final dailyButton = find.byKey(const ValueKey('daily_button'));
      expect(dailyButton, findsOneWidget);
      expect(tester.widget<ElevatedButton>(dailyButton).onPressed, isNotNull);
      expect(find.text('DAILY SHIFT'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('daily_status')),
        findsOneWidget,
      );
      expect(find.textContaining(DailyShift.todayKey), findsOneWidget,
          reason: 'the shared course is the date, shown on the menu');
      expect(find.textContaining('ONE SHIFT'), findsOneWidget);
    });

    testWidgets('the daily leads the menu once the ladder is finished',
        (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);
      for (var level = 1; level <= 10; level++) {
        gameStateService.completeLevel(level, 0);
      }

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      final dailyButton = find.byKey(const ValueKey('daily_button'));
      final endlessButton = find.byKey(const ValueKey('endless_button'));
      expect(
        tester.getRect(dailyButton).top,
        lessThan(tester.getRect(endlessButton).top),
        reason: 'today\'s shared course leads the menu',
      );
    });

    testWidgets('once today\'s daily has ended, the button names the '
        'destination it opens instead of offering a replay', (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();
      expect(find.text("TODAY'S RESULT"), findsNothing);

      await gameStateService.recordDailyResult(DailyResult(
        dateKey: DailyShift.todayKey,
        score: 340,
        banked: true,
        completedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
      await tester.pump();

      expect(find.text("TODAY'S RESULT"), findsOneWidget);
      expect(find.text('DAILY SHIFT'), findsNothing);
      expect(find.textContaining('340 PTS'), findsOneWidget,
          reason: 'the day\'s score stays on the menu until midnight');

      final dailyButton = find.byKey(const ValueKey('daily_button'));
      expect(tester.widget<ElevatedButton>(dailyButton).onPressed, isNotNull,
          reason: 'done is not dead — the button opens the day\'s result');
    });

    testWidgets('a completed daily button opens the daily result screen',
        (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);
      await gameStateService.recordDailyResult(DailyResult(
        dateKey: DailyShift.todayKey,
        score: 340,
        banked: true,
        completedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('daily_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('daily_screen')), findsOneWidget);
    });

    testWidgets('the daily history link opens the daily result screen',
        (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      await tester
          .tap(find.byKey(const ValueKey('daily_history_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('daily_screen')), findsOneWidget,
          reason: 'history is reachable even before today\'s shift ends');
    });
  });

  group('the daily card survives the day rolling over (issue #113)', () {
    // The bug the issue title describes: the card computed the day's
    // state once inside a Consumer that only re-runs on save writes, so
    // nothing rebuilt it when the day changed — the next morning's menu
    // still said TODAY'S RESULT · DONE FOR TODAY, the new Daily Shift
    // hidden behind yesterday's card until some unrelated save write
    // happened along. The clock is pinned per the #96 convention so the
    // rollover is a controlled step, not a sleep.

    /// Day D played and the menu pumped: the card in its spent state.
    Future<void> pumpPlayedDay(WidgetTester tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);
      await gameStateService.recordDailyResult(DailyResult(
        dateKey: DailyShift.todayKey,
        score: 340,
        banked: true,
        completedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      expect(find.text("TODAY'S RESULT"), findsOneWidget,
          reason: 'precondition: the card was built on the played day');
      expect(find.textContaining('DONE FOR TODAY'), findsOneWidget);
      expect(find.text('DAILY SHIFT'), findsNothing);
    }

    /// Moves the clock into tomorrow, restoring the real one afterwards.
    void rollToTomorrow() {
      // Calendar tomorrow at noon (issue #196): now + 24h is still today
      // for an hour at each end of a DST change day, and a "rollover"
      // that stays on day D proves nothing about the card flipping.
      DailyShift.clock = () => calendarDaysFromNow(1);
      addTearDown(() => DailyShift.clock = DateTime.now);
    }

    /// The flipped card: the new day's course offered, the spent state
    /// gone, and the history link back (it exists only while today is
    /// unplayed).
    void expectNewDayOffered() {
      expect(find.text('DAILY SHIFT'), findsOneWidget,
          reason: "the new day's shift is the button again");
      expect(find.text("TODAY'S RESULT"), findsNothing);
      expect(find.textContaining('DONE FOR TODAY'), findsNothing);
      expect(find.textContaining('ONE SHIFT'), findsOneWidget);
      expect(find.textContaining(DailyShift.todayKey), findsOneWidget,
          reason: 'the status names the new day\'s date');
      expect(
          find.byKey(const ValueKey('daily_history_button')), findsOneWidget);
    }

    testWidgets('an app resumed the next day shows the new daily, not '
        "yesterday's DONE FOR TODAY", (tester) async {
      await pumpPlayedDay(tester);

      // Midnight passed while the app was backgrounded; the owner
      // reopens it the next day. No save change fires — only the
      // lifecycle does.
      rollToTomorrow();
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expectNewDayOffered();
    });

    testWidgets('midnight passing in the foreground flips the card on the '
        'minute tick', (tester) async {
      await pumpPlayedDay(tester);

      // The app stays open across midnight: no lifecycle event will
      // ever come, so the one-minute timer is the only witness.
      rollToTomorrow();
      await tester.pump(const Duration(minutes: 1));

      expectNewDayOffered();
    });
  });

  testWidgets('the title and daily status stay one line at every iPhone '
      'width (issues #187, #201)', (tester) async {
    // 'CAB HUSTLE' at 48 px is ~480 px of bold type, and the 280 px left
    // on a 320 pt iPhone wrapped the menu's headline into two flush-left
    // lines. #201 caught the daily block's status line doing the same:
    // the unplayed branch — '$dayKey · ONE SHIFT, SAME FOR EVERYONE' —
    // wrapped under the button, and it rides the title's scale-down box
    // now. The completion panel's #159 sweep pattern: one line of ink,
    // laid out under the scale-down box's unbounded width. Ahem advances
    // a square per glyph — roughly twice Roboto — so the checks are
    // strictly conservative (the #156 garage width-sweep reasoning).
    addTearDown(tester.view.reset);
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    for (final width in [320.0, 375.0, 390.0, 393.0]) {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      // (the label the reason strings name, its finder)
      final labels = <(String, Finder)>[
        ('CAB HUSTLE', find.text('CAB HUSTLE')),
        // Keyed, not text-matched: the status carries the day's date,
        // and the key is what production and the other tests find it by.
        ('the daily status line',
            find.byKey(const ValueKey('daily_status'))),
      ];
      for (final (name, finder) in labels) {
        expect(finder, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final fontSize = tester.widget<Text>(finder).style!.fontSize!;
        expect(
          paragraph.size.height,
          lessThan(fontSize * 1.5),
          reason: '$name must be a single line on a ${width.round()} pt '
              'screen — two Ahem lines measure ~${(fontSize * 2).round()}',
        );
        expect(
          paragraph.constraints.maxWidth,
          equals(double.infinity),
          reason: '$name must lay out under the FittedBox\'s unbounded '
              'width to be wrap-proof',
        );
      }
    }
  });
}
