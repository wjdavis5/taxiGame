import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'helpers/calendar_days.dart';
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

  /// Calendar days ago, never now − n·24h (issue #196): on the 25-hour
  /// fall-back day, now − 24h is still today for the hour after midnight,
  /// and a "history" row planted for today disappears into the today card.
  String daysAgoKey(int days) =>
      DailyShift.dateKeyFor(calendarDaysFromNow(-days));

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

  group('the played score row fits a 320 pt phone (issue #157)', () {
    /// Pumps the screen as the day's card looks on the narrowest real
    /// surface — the 4-inch SE / Display Zoom width, the garage tests'
    /// viewport (issue #149). Nothing in the played score row could
    /// shrink, so a five-digit day shoved the BANKED/WRECKED chip 16–50
    /// px past the card's edge. Ahem advances a square per glyph —
    /// roughly twice Roboto — so 0.85 text scale stands in for real-font
    /// metrics while staying wider than Roboto renders the same digits,
    /// keeping the overflow check conservative where the bug lived.
    Future<double> pumpPlayedAt320(
      WidgetTester tester, {
      required int score,
      required bool banked,
    }) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 0.85;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await gameState.recordDailyResult(
          resultFor(DailyShift.todayKey, score: score, banked: banked));
      await pumpScreen(tester);

      // The key sits on the chip's text, so this is the label's right
      // edge — 10 px (the chip's own right inset) inside the rounded
      // badge. The card's content ends at 320 − 24 screen padding − 20
      // card padding = 276; the row the chip lives in must not push it
      // past that, which is exactly what an unshrinkable score did.
      return tester
          .getTopRight(
              find.byKey(Key('daily_outcome_${banked ? 'banked' : 'wrecked'}')))
          .dx;
    }

    testWidgets('a five-digit banked score keeps the chip inside the card',
        (tester) async {
      final chipRight =
          await pumpPlayedAt320(tester, score: 12345, banked: true);

      expect(tester.takeException(), isNull,
          reason: 'the score row must lay out, not overflow its card');
      expect(find.text('12345'), findsOneWidget);
      expect(chipRight, lessThanOrEqualTo(276),
          reason: 'the BANKED chip stays inside the card at 320 pt — the '
              'score group scales down instead of shoving it out');
    });

    testWidgets('a six-digit wrecked score keeps the chip inside the card',
        (tester) async {
      final chipRight =
          await pumpPlayedAt320(tester, score: 123456, banked: false);

      expect(tester.takeException(), isNull,
          reason: 'the score row must lay out, not overflow its card');
      expect(find.text('123456'), findsOneWidget);
      expect(chipRight, lessThanOrEqualTo(276),
          reason: 'the WRECKED chip — wider than BANKED, and behind an even '
              'wider score — stays inside the card at 320 pt');
    });
  });

  group('the chip centers on the scaled score (issue #161)', () {
    // The #157 fix shrank the number but left the outer row
    // baseline-aligned — and a scaled FittedBox reports its child's
    // *unscaled* baseline, so the chip aligned to a baseline 13 px below
    // where the shrunk number actually paints and hung under it. The row
    // now centers, which is scale-independent: the FittedBox's own box
    // shrinks with its child, so "chip center == score center" holds at
    // every scale factor. Same viewport recipe as the #157 group — the
    // narrowest real surface, and Ahem's square glyphs at 0.85 text
    // scale — because that is where the scale-down engages.

    /// Pumps the played card at 320 pt and returns the vertical distance
    /// between the chip's center and the score's *painted* center —
    /// getCenter measures through the FittedBox's paint transform, so
    /// this is the shrunk number the player sees, not its layout box.
    Future<double> pumpAndMeasureChipDelta(
      WidgetTester tester, {
      required int score,
      required bool banked,
    }) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 0.85;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await gameState.recordDailyResult(
          resultFor(DailyShift.todayKey, score: score, banked: banked));
      await pumpScreen(tester);

      // Precondition: the number really is scaled down — if it still fit,
      // baseline and center coincide and this pin would be vacuous.
      final scoreFinder = find.byKey(const Key('daily_today_score'));
      final painted = tester.getRect(scoreFinder);
      final laidOut = tester.renderObject<RenderParagraph>(scoreFinder).size;
      expect(painted.height, lessThan(laidOut.height * 0.9),
          reason: 'the FittedBox must be scaling the number for this test '
              'to mean anything');

      final scoreCenter = tester.getCenter(scoreFinder).dy;
      final chipCenter = tester
          .getCenter(
              find.byKey(Key('daily_outcome_${banked ? 'banked' : 'wrecked'}')))
          .dy;
      return (chipCenter - scoreCenter).abs();
    }

    testWidgets('a five-digit banked score centers the chip on the shrunk '
        'number', (tester) async {
      final delta =
          await pumpAndMeasureChipDelta(tester, score: 12345, banked: true);

      expect(delta, lessThanOrEqualTo(2),
          reason: 'the BANKED chip must ride the scaled number\'s center — '
              'under the baseline alignment it hung ~13 px below');
    });

    testWidgets('a six-digit wrecked score centers the chip on the shrunk '
        'number', (tester) async {
      final delta =
          await pumpAndMeasureChipDelta(tester, score: 123456, banked: false);

      expect(delta, lessThanOrEqualTo(2),
          reason: 'the WRECKED chip must ride the scaled number\'s center — '
              'the deeper the scale-down, the further the unscaled '
              'baseline drifts from the painted one');
    });
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
        dateKey: DailyShift.dateKeyFor(calendarDaysFromNow(-1)),
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
      // ghost, overwriting D's). Tomorrow at noon — calendar tomorrow,
      // never now + 24h (issue #196), which on the 25-hour fall-back day
      // is still day D for an hour and makes the refusal vacuous.
      DailyShift.clock = () => calendarDaysFromNow(1);
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

  group('the screen survives the day rolling over (issue #113)', () {
    // Like the menu's card, this screen's two day-dependent blocks were
    // Consumers that only re-ran on save writes, so a day that changed
    // under them left yesterday's result in the today card and
    // yesterday out of the history. The clock is pinned per the #96
    // convention; both rollover witnesses — resume and the minute tick
    // — must flip the screen.

    /// Day D played and the screen pumped: the card in its spent state,
    /// D not yet in the history.
    Future<String> pumpPlayedDay(WidgetTester tester) async {
      final dayD = DailyShift.todayKey;
      await gameState.recordDailyResult(resultFor(dayD, score: 340));
      await pumpScreen(tester);
      expect(find.byKey(const Key('daily_today_score')), findsOneWidget,
          reason: 'precondition: the card was built on the played day');
      expect(find.byKey(const Key('daily_empty_history')), findsOneWidget,
          reason: 'precondition: the played day has no history yet');
      return dayD;
    }

    void rollToTomorrow() {
      // Calendar tomorrow at noon (issue #196): now + 24h is not tomorrow
      // for an hour at each end of a DST change day, and the rollover this
      // steps through must actually cross a midnight.
      DailyShift.clock = () => calendarDaysFromNow(1);
      addTearDown(() => DailyShift.clock = DateTime.now);
    }

    /// The flipped screen: the new day is unplayed — invitation, start
    /// button, no score in the today card — and yesterday's result has
    /// joined the history rows.
    void expectNewDayUnplayed(String dayD) {
      expect(find.byKey(const Key('daily_today_unplayed')), findsOneWidget);
      expect(find.byKey(const Key('daily_start_button')), findsOneWidget,
          reason: "the new day's one attempt is unspent");
      expect(find.byKey(const Key('daily_today_score')), findsNothing);
      expect(find.byKey(const Key('daily_empty_history')), findsNothing,
          reason: 'the played day left the card and joined the history');
      expect(find.text(dayD), findsOneWidget,
          reason: 'yesterday is one of the past days now');
      expect(find.text('340'), findsOneWidget,
          reason: 'the score lives on as a history row');
      expect(find.text(DailyShift.todayKey), findsOneWidget,
          reason: "the today card's date is the new day's");
    }

    testWidgets('an app resumed the next day shows the new day unplayed, '
        'yesterday moved to the history', (tester) async {
      final dayD = await pumpPlayedDay(tester);

      rollToTomorrow();
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expectNewDayUnplayed(dayD);
    });

    testWidgets('midnight passing with the screen open flips it on the '
        'minute tick', (tester) async {
      final dayD = await pumpPlayedDay(tester);

      rollToTomorrow();
      await tester.pump(const Duration(minutes: 1));

      expectNewDayUnplayed(dayD);
    });
  });
}
