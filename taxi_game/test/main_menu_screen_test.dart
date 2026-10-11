import 'dart:convert';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/data/vehicle_catalog.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/achievements.dart';
import 'package:taxi_game/models/city_license.dart';
import 'package:taxi_game/models/daily_result.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';
import 'package:taxi_game/ui/screens/main_menu_screen.dart';
import 'package:taxi_game/ui/screens/records_screen.dart';
import 'package:taxi_game/ui/widgets/cab_button.dart';
import 'helpers/calendar_days.dart';
import 'helpers/fake_audio_platform.dart';

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
    expect(tester.widget<CabButton>(playButton).onPressed, isNotNull);
  });

  testWidgets('garage button is present and enabled', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final garageButton = find.byKey(const ValueKey('garage_button'));
    expect(garageButton, findsOneWidget);
    expect(tester.widget<CabButton>(garageButton).onPressed, isNotNull);
  });

  testWidgets('endless shift button is present and enabled', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final endlessButton = find.byKey(const ValueKey('endless_button'));
    expect(endlessButton, findsOneWidget);
    expect(tester.widget<CabButton>(endlessButton).onPressed, isNotNull);
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
    // face, while the mode buttons step back in white (issue #264's
    // CabButton carries the style now).
    final playPrimary = tester.widget<CabButton>(playButton).primary;
    final endlessPrimary = tester.widget<CabButton>(endlessButton).primary;
    expect(playPrimary, isTrue,
        reason: 'only the on-ramp is styled like the headline');
    expect(endlessPrimary, isFalse,
        reason: 'the modes step back from the on-ramp');
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
    expect(tester.widget<CabButton>(recordsButton).onPressed, isNotNull);
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
      expect(tester.widget<CabButton>(dailyButton).onPressed, isNotNull);
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
      expect(tester.widget<CabButton>(dailyButton).onPressed, isNotNull,
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

      // The streak line (issue #281) adds a row to the daily block; on
      // the 800x600 test surface the link now sits just past the fold of
      // the menu's scroll view, exactly like a small real phone.
      await tester.ensureVisible(
          find.byKey(const ValueKey('daily_history_button')));
      await tester.pump();
      await tester
          .tap(find.byKey(const ValueKey('daily_history_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('daily_screen')), findsOneWidget,
          reason: 'history is reachable even before today\'s shift ends');
    });
  });

  group('the visible streak (issue #281)', () {
    testWidgets('the menu shows the current run and the best ever',
        (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);
      // A two-day run ending today.
      for (var i = 1; i >= 0; i--) {
        await gameStateService.recordDailyResult(DailyResult(
          dateKey: DailyShift.dateKeyFor(calendarDaysFromNow(-i)),
          score: 340,
          banked: true,
          completedAtMs: DateTime.now().millisecondsSinceEpoch,
        ));
      }

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      expect(find.text('STREAK 2 \u00b7 BEST 2'), findsOneWidget);
    });

    testWidgets('a missed day shows 0 while the best stays', (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);
      // A three-day run ending two days ago: nothing is alive today.
      for (var i = 4; i >= 2; i--) {
        await gameStateService.recordDailyResult(DailyResult(
          dateKey: DailyShift.dateKeyFor(calendarDaysFromNow(-i)),
          score: 340,
          banked: true,
          completedAtMs: DateTime.now().millisecondsSinceEpoch,
        ));
      }

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      expect(find.text('STREAK 0 \u00b7 BEST 3'), findsOneWidget,
          reason: 'a missed day costs the visible run; the best is a record');
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

  group('the daily card and its button share one day (issue #245)', () {
    testWidgets('a rebuild inside the midnight window starts the day the '
        'card names', (tester) async {
      // The card's status line is a snapshot of the day it was built
      // for (#113), but its result and its button used to read the live
      // clock: a save write in the ≤59 s after midnight rebuilt the
      // card showing D's date while its button started D+1's course.
      // Every part of the card now reads the one snapshot day.
      installFakeAudioPlatform();
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GameStateService>.value(
                value: gameStateService),
            Provider<AudioService>.value(value: AudioService()),
            Provider<HapticsService>.value(value: HapticsService()),
            Provider<LevelLoaderService>.value(value: LevelLoaderService()),
            Provider<StorageService>.value(value: storageService),
          ],
          child: const MaterialApp(home: MainMenuScreen()),
        ),
      );
      await tester.pump();

      final dayD = DailyShift.todayKey;
      expect(find.textContaining(dayD), findsOneWidget,
          reason: 'precondition: the card names day D');

      // Midnight passes; a save write rebuilds the card before the
      // DayKeyBuilder's minute tick has flipped its snapshot.
      DailyShift.clock = () => calendarDaysFromNow(1);
      addTearDown(() => DailyShift.clock = DateTime.now);
      gameStateService.addCoins(1);
      await tester.pump();

      expect(find.textContaining(dayD), findsOneWidget,
          reason: 'the rebuilt card still names the day it was built for');

      await tester.tap(find.byKey(const ValueKey('daily_button')));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final game = tester
          .widget<GameWidget<TaxiGame>>(find.byType(GameWidget<TaxiGame>))
          .game!;
      expect(game.endlessSeed, DailyShift.seedForDateKey(dayD),
          reason: 'the tapped day is the day the card named — the label '
              'cannot disagree with the course it starts');
      expect(game.runDateKey, dayD,
          reason: 'and the run pins the carried day (issue #248), not the '
              'clock read at start');
    });
  });

  testWidgets('the title, daily status and button labels stay one line at '
      'every iPhone width (issues #187, #201, #208)', (tester) async {
    // 'CAB HUSTLE' at 48 px is ~480 px of bold type, and the 280 px left
    // on a 320 pt iPhone wrapped the menu's headline into two flush-left
    // lines. #201 caught the daily block's status line doing the same:
    // the unplayed branch — '$dayKey · ONE SHIFT, SAME FOR EVERYONE' —
    // wrapped under the button, and it rides the title's scale-down box
    // now. #208 caught the buttons themselves: the menu's widest labels
    // — START DRIVING, ENDLESS SHIFT, DAILY SHIFT, and once the day is
    // spent TODAY'S RESULT — wrapped too, and _MenuButton now puts every
    // one of them in the same box. The completion panel's #159 sweep
    // pattern: one line of ink, laid out under the scale-down box's
    // unbounded width. Ahem advances a square per glyph — roughly twice
    // Roboto — so the checks are strictly conservative (the #156 garage
    // width-sweep reasoning).
    addTearDown(tester.view.reset);
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    void expectSingleLine(Finder finder, String name, double width) {
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
        ('the daily streak line',
            find.byKey(const ValueKey('daily_streak_status'))),
        ('the daily ghost line',
            find.byKey(const ValueKey('daily_ghost_status'))),
        ('the endless rule line',
            find.byKey(const ValueKey('endless_rule_status'))),
        ('the next goal line',
            find.byKey(const ValueKey('menu_next_goal'))),
        // #208: a fresh save shows the three widest button labels —
        // the on-ramp headline and both mode labels.
        ('START DRIVING', find.text('START DRIVING')),
        ('ENDLESS SHIFT', find.text('ENDLESS SHIFT')),
        ('DAILY SHIFT', find.text('DAILY SHIFT')),
      ];
      for (final (name, finder) in labels) {
        expectSingleLine(finder, name, width);
      }
    }

    // The spent day (the #113 group's pumpPlayedDay setup) swaps DAILY
    // SHIFT for the widest menu label of all, TODAY'S RESULT — the
    // headline #208 names. Same sweep, one more label.
    await gameStateService.recordDailyResult(DailyResult(
      dateKey: DailyShift.todayKey,
      score: 340,
      banked: true,
      completedAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    for (final width in [320.0, 375.0, 390.0, 393.0]) {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      expectSingleLine(find.text("TODAY'S RESULT"), "TODAY'S RESULT", width);
    }
  });

  group('the push transition is re-entry safe (issue #220)', () {
    testWidgets('a second tap during the push stacks no second shift',
        (tester) async {
      // The menu stays hit-testable through the push transition, so two
      // taps on a mode button both reached its callback — two pushes,
      // two live games, and a pop that lands in a shift nobody started.
      // The second invocation must be refused while the menu's route is
      // no longer current.
      installFakeAudioPlatform();
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GameStateService>.value(
                value: gameStateService),
            Provider<AudioService>.value(value: AudioService()),
            Provider<HapticsService>.value(value: HapticsService()),
            Provider<LevelLoaderService>.value(value: LevelLoaderService()),
            Provider<StorageService>.value(value: storageService),
          ],
          child: const MaterialApp(home: MainMenuScreen()),
        ),
      );
      await tester.pump();

      final endless = find.byKey(const ValueKey('endless_button'));
      final onPressed = tester.widget<CabButton>(endless).onPressed;
      onPressed();
      onPressed();

      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.byType(GameScreen, skipOffstage: false),
        findsOneWidget,
        reason: 'one push, one live shift — a stacked second game keeps '
            'simulating behind the visible one',
      );
    });
  });

  group('the branded first screen (issue #264)', () {
    testWidgets('a fresh save opens on the Cab Hustle wordmark, and the '
        'menu speaks no stock Material control language', (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      expect(find.byKey(const ValueKey('cab_hustle_wordmark')),
          findsOneWidget,
          reason: 'the first screen is the game\'s own mark, not a bare '
              'centered Text');
      expect(find.text('CAB HUSTLE'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing,
          reason: 'every menu action is a CabButton — the custom face — '
              'not a stock Material button, the Daily History link '
              'included');
      expect(
        tester.widget(find.byKey(const ValueKey('daily_history_button'))),
        isA<CabButton>(),
        reason: 'the history link was the one stock TextButton left on '
            'the fresh-save menu',
      );
    });

    testWidgets('the Daily History button reads its label exactly once and '
        'stays activatable to semantics', (tester) async {
      // The explicit Semantics label is the button's whole semantics;
      // without excludeSemantics the visible Text adds a labeled child
      // node and a screen reader announces the label twice. And the tap
      // action must sit on the same node: excludeSemantics drops the
      // GestureDetector's subtree, so a node without its own onTap is
      // announced but cannot be activated.
      final semantics = tester.ensureSemantics();
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      final node = tester.getSemantics(
          find.byKey(const ValueKey('daily_history_button')));
      expect(node.label, 'DAILY HISTORY');
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue,
          reason: 'the button must stay activatable, not just announced');
      final labeledChildren = <String>[];
      node.visitChildren((child) {
        labeledChildren.add(child.label);
        return true;
      });
      expect(labeledChildren.where((label) => label == 'DAILY HISTORY'),
          isEmpty,
          reason: 'the child Text must not duplicate the button label');
      // Disposed in the body, not a tear-down: the binding checks for
      // live handles before tear-downs run.
      semantics.dispose();
    });

    testWidgets('the Daily History link is the compact face with a 44 pt '
        'tap target', (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      final link = find.byKey(const ValueKey('daily_history_button'));
      expect(tester.widget<CabButton>(link).compact, isTrue,
          reason: 'the link is the compact face, not a mode-sized button');
      expect(tester.getSize(link).height, greaterThanOrEqualTo(44),
          reason: 'the TextButton it replaced enforced a 48 px hit area; '
              'the custom face must keep at least the 44 pt iOS minimum');
    });

    testWidgets('ENDLESS SHIFT names the three-crash and bank-or-push rule '
        'in one line', (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      expect(
        find.text('3 CRASHES END IT \u2014 BANK OR PUSH AT EVERY DROPOFF'),
        findsOneWidget,
        reason: 'the flagship rule is stated before the mode is entered, '
            'on a fresh save',
      );
    });

    testWidgets('the daily card names the shared course and the ghost '
        'payoff before the first attempt', (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      expect(find.textContaining('SAME FOR EVERYONE'), findsOneWidget,
          reason: 'the shared course is the first half of the pitch');
      expect(find.text('RACE YOUR GHOST AFTER YOUR RUN'), findsOneWidget,
          reason: 'the local ghost is the payoff, named before the first '
              'attempt');
    });
  });

  group('the next goal (issue #282)', () {
    testWidgets('a fresh save points at the next car and its shortfall',
        (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      expect(find.byKey(const ValueKey('menu_next_goal')), findsOneWidget);
      expect(find.text('NEXT GOAL \u00b7 CITY COMPACT \u2014 5000 COINS '
          'TO GO'), findsOneWidget);
    });

    testWidgets('the goal moves with the wallet', (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);
      gameStateService.addCoins(2000);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      expect(find.text('NEXT GOAL \u00b7 CITY COMPACT \u2014 3000 COINS '
          'TO GO'), findsOneWidget);
    });

    testWidgets('with the fleet complete the goal points at the next open '
        'license objective (issue #278)', (tester) async {
      // The garage ladder is spent and the board is untouched: the
      // post-tutorial board leads, with its first objective named.
      final save = SaveData.createDefault();
      save.unlockedVehicles
        ..clear()
        ..addAll(VehicleCatalog.vehicles.map((v) => v.id));
      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey: jsonEncode(save.toJson()),
      });
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);
      await gameStateService.loadSaveData();

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      expect(
          find.text('NEXT GOAL \u00b7 CLEAN BANK \u2014 BANK A SHIFT WITH 0 '
              'CRASHES'),
          findsOneWidget);
    });

    testWidgets('a completed board points at the closest locked achievement',
        (tester) async {
      final save = SaveData.createDefault();
      save.unlockedVehicles
        ..clear()
        ..addAll(VehicleCatalog.vehicles.map((v) => v.id));
      for (final rule in CityLicense.board) {
        save.licenseObjectives[rule.id] = true;
      }
      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey: jsonEncode(save.toJson()),
      });
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);
      await gameStateService.loadSaveData();
      // A 3 km run earns the 1 km and 3 km distance tiers and leaves the
      // 5 km tier at 3000/5000 — closer than anything else locked.
      await gameStateService.recordEndlessRun(const RunRecord(
        endedAtMs: 0,
        distancePx: 30000,
        score: 100,
        faresDelivered: 2,
        longestChain: 1,
        livesLost: 0,
        lifeLossDistancesPx: [],
        banked: true,
        durationSeconds: 60,
      ));

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      expect(find.text('NEXT GOAL \u00b7 CROSS-TOWN LEGEND \u2014 3000/5000'),
          findsOneWidget);
    });

    testWidgets('a completed save shows no next-goal line', (tester) async {
      // Every car owned, every license objective complete, and every
      // achievement earned: nothing is left to chase, so the surface
      // renders no line at all — a placeholder goal would be a lie.
      final save = SaveData.createDefault();
      save.unlockedVehicles
        ..clear()
        ..addAll(VehicleCatalog.vehicles.map((v) => v.id));
      for (final def in AchievementCatalog.all) {
        save.achievements[def.id] = true;
      }
      for (final rule in CityLicense.board) {
        save.licenseObjectives[rule.id] = true;
      }
      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey: jsonEncode(save.toJson()),
      });
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);
      await gameStateService.loadSaveData();
      expect(gameStateService.nextGoal, isNull,
          reason: 'precondition: the save is fully completed');

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      expect(find.byKey(const ValueKey('menu_next_goal')), findsNothing);
    });

    testWidgets('the City License board is one tap from the menu '
        '(issue #278)', (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      final licenseButton = find.byKey(const Key('license_button'));
      expect(licenseButton, findsOneWidget);
      expect(find.text('CITY LICENSE'), findsOneWidget);
      expect(tester.widget<CabButton>(licenseButton).onPressed, isNotNull);
      await tester.ensureVisible(licenseButton);
      await tester.tap(licenseButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('city_license_screen')), findsOneWidget);
      expect(find.byKey(const ValueKey('license_progress')), findsOneWidget);
    });

    testWidgets('the shift-stats screen is one tap from the menu',
        (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      final statsButton = find.byKey(const Key('stats_button'));
      expect(statsButton, findsOneWidget);
      expect(find.text('SHIFT STATS'), findsOneWidget);
      await tester.ensureVisible(statsButton);
      await tester.tap(statsButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('stats_screen')), findsOneWidget,
          reason: 'the mastery wall must not hide behind Settings');
    });
  });
}
