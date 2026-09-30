import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/fake_audio_platform.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/systems/lives.dart';
import 'package:taxi_game/game/systems/run_summary.dart';
import 'package:taxi_game/models/achievements.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';
import 'package:taxi_game/ui/widgets/run_summary_panel.dart';

/// An [AudioService] that counts the engine calls reaching it (issue
/// #73): the finished game's per-frame engine-off assertions were half
/// the bug, and the guard is proven by counting exactly those.
class _EngineCountingAudio extends AudioService {
  int runningCalls = 0;
  int intensityCalls = 0;

  @override
  void setEngineRunning(bool running) {
    runningCalls++;
    super.setEngineRunning(running);
  }

  @override
  void setEngineIntensity(double intensity) {
    intensityCalls++;
    super.setEngineIntensity(intensity);
  }
}

/// The end-of-shift run summary panel (issue #15): the six numbers every
/// shift ends with, the personal-best callout, and a DRIVE AGAIN path
/// that restarts the shift in place.
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
    nearMisses: 9,
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
          Provider<AudioService>.value(value: AudioService()),
          Provider<HapticsService>.value(value: HapticsService()),
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
    expect(find.text('Tip: banking at a dropoff keeps your coins safe.'),
        findsNothing,
        reason: 'the tip is the wreck\'s lesson, not the bank\'s');
    expect(find.text('Score'), findsOneWidget);
    expect(find.text('240'), findsOneWidget);
    expect(find.text('Best chain'), findsOneWidget);
    expect(find.text('\u00d74'), findsOneWidget);
    expect(find.text('Fares delivered'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Close calls'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
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
    expect(find.text('Tip: banking at a dropoff keeps your coins safe.'),
        findsOneWidget,
        reason: 'the failure teaches its own escape');
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

  group('achievement unlock banners (issue #21)', () {
    testWidgets('a shift that earned achievements names each one',
        (tester) async {
      final game = endlessGame();
      const summary = RunSummary(
        outcome: ShiftOutcome.banked,
        score: 240,
        bestChain: 5,
        faresDelivered: 12,
        distancePx: 12340,
        coinsEarned: 195,
        isPersonalBest: true,
        previousBest: 180,
        achievementsUnlocked: [
          AchievementCatalog.chain3,
          AchievementCatalog.chain5,
        ],
      );
      await showPanel(tester, game, summary);

      expect(find.text('ACHIEVEMENT UNLOCKED'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('achievement_unlock_chain_3')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('achievement_unlock_chain_5')),
          findsOneWidget);
      expect(find.text(AchievementCatalog.chain3.title), findsOneWidget);
      expect(find.text(AchievementCatalog.chain5.title), findsOneWidget);
    });

    testWidgets('an ordinary shift shows no unlock banners',
        (tester) async {
      final game = endlessGame();
      await showPanel(tester, game, bankedSummary);

      expect(find.text('ACHIEVEMENT UNLOCKED'), findsNothing);
    });
  });

  group('the share score card (issue #22)', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('cab_hustle/share'), null);
    });

    void mockShareChannel(List<MethodCall> calls) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('cab_hustle/share'),
              (call) async {
        calls.add(call);
        return null;
      });
    }

    TaxiGame dailyGame() => TaxiGame(
          levelLoader: LevelLoaderService(),
          gameState: gameState,
          endlessSeed: 9,
          isDailyShift: true,
        );

    /// Waits until [done] holds, alternating a short real delay with a
    /// frame pump — the same deadline-polling share_score_button_test
    /// adopted for issue #46. The one-tap share renders the card into a
    /// real PNG and round-trips the platform channel, so the turns it
    /// needs vary with machine load; the fixed 100 ms drain this replaced
    /// raced on loaded CI runners. A 5 s deadline makes quick runs exit
    /// early, slow ones keep stepping, and a genuine hang fail loudly.
    Future<void> untilShareSettles(
      WidgetTester tester,
      bool Function() done,
    ) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!done()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('timed out waiting for the share flow to settle');
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
    }

    testWidgets('an ended shift offers to share the score', (tester) async {
      // The native half of the channel is iOS-only, so the offer is.
      // The override is cleared inside the body: the binding checks its
      // invariants before dart-test teardowns run.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await showPanel(tester, endlessGame(), bankedSummary);

        expect(
            find.byKey(const ValueKey('share_score_button')), findsOneWidget);
        expect(find.text('SHARE SCORE'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('platforms without the native half offer nothing',
        (tester) async {
      // Tests default to android: no handler was ever written for it,
      // and a button that can only error is no button at all.
      await showPanel(tester, endlessGame(), bankedSummary);

      expect(find.byKey(const ValueKey('share_score_button')), findsNothing);
    });

    testWidgets('tapping it shares the day’s facts for a daily',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final calls = <MethodCall>[];
        mockShareChannel(calls);
        await showPanel(tester, dailyGame(), bankedSummary);

        await tester.tap(find.byKey(const ValueKey('share_score_button')));
        // Done when the channel has actually been handed the card (issue
        // #46) — not after a guess at how long the raster takes.
        await untilShareSettles(tester, () => calls.isNotEmpty);

        expect(calls, hasLength(1));
        final args = calls.single.arguments as Map<Object?, Object?>;
        final text = args['text'] as String;
        expect(text, contains('240 pts'),
            reason: 'the card shares the panel’s numbers');
        expect(text, contains(DailyShift.todayKey));
        expect(text, contains('seed 9'));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
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

    testWidgets('tapping the button starts the ghost race in place — no '
        'second game stacked (issue #73)', (tester) async {
      await plantGhostForToday();
      final game = dailyGame();
      // Pin the run's day the way the live flow does (issue #96): the
      // summary only ever exists over a shift that ran, and the tap's
      // day-guard reads that run's pinned day — an unstarted game has
      // none, which a midnight tap must refuse.
      await game.startEndlessRun(
          seed: DailyShift.seedForDateKey(DailyShift.todayKey));
      await showPanel(tester, game, bankedSummary);

      await tester.tap(find.byKey(const ValueKey('race_ghost_button')));
      await tester.pump();

      // The race replaced this summary on the same route — the way
      // DRIVE AGAIN always restarted the shift. The old button pushed a
      // whole second GameScreen over the finished game; none appears.
      expect(find.byType(GameScreen), findsNothing,
          reason: 'the restart is in place, never a stacked route');
      expect(game.isGhostRace, isTrue);
      expect(game.isDailyShift, isFalse,
          reason: 'the scoring attempt was spent by the settled shift');
      expect(game.isGameActive, isTrue,
          reason: 'the race is live immediately');
      expect(game.overlays.activeOverlays, isEmpty,
          reason: 'the summary panel stood down with the tap');
      expect(game.lastRunSummary, isNull,
          reason: 'the settled shift is cleared');
      expect(game.runSeed, DailyShift.seedForDateKey(DailyShift.todayKey),
          reason: "the race rides today's course, the one the ghost "
              'recorded its trace on');
    });

    testWidgets('a tap after midnight refuses: no D+1 course, no D+1 '
        'ghost (issue #96)', (tester) async {
      // Day D: the daily settles with its ghost stored, and the summary
      // — whose RACE YOUR GHOST was built for D — is on screen.
      final dayD = DailyShift.todayKey;
      final dayE = DailyShift.dateKeyFor(
          DateTime.now().add(const Duration(days: 1)));
      await plantGhostForToday();
      final game = dailyGame();
      await game.startEndlessRun(
          seed: DailyShift.seedForDateKey(DailyShift.todayKey));
      await showPanel(tester, game, bankedSummary);
      expect(find.byKey(const ValueKey('race_ghost_button')), findsOneWidget,
          reason: 'precondition: the button was built on day D');

      // Midnight passes with the summary left open. Nothing notifies the
      // panel, so the button — and the settled run's pinned day — are
      // still D's; the tap must not hand out D+1's course.
      DailyShift.clock = () => DateTime.now().add(const Duration(days: 1));
      addTearDown(() => DailyShift.clock = DateTime.now);

      await tester.tap(find.byKey(const ValueKey('race_ghost_button')));
      await tester.pump();

      // The tap changed nothing: the guard returned before a single flag
      // moved. With the bug, the tap flipped the game into a D+1 ghost
      // race — isGhostRace true, isDailyShift false, the run re-seeded
      // to D+1's course.
      expect(game.isGhostRace, isFalse,
          reason: 'the refused tap starts no race');
      expect(game.isDailyShift, isTrue,
          reason: "the settled shift's flags are untouched");
      expect(game.runSeed, DailyShift.seedForDateKey(dayD),
          reason: "the run on the game is still the settled daily, not "
              'D+1\'s course');
      expect(gameState.ghostFor(dayE), isNull,
          reason: 'nothing was written for a day that has not been driven');
      expect(gameState.ghostFor(dayD)!.score, 500,
          reason: "D's ghost survives untouched");
    });

    testWidgets('RACE YOUR GHOST over a real GameScreen: one MAIN MENU '
        'tap comes home (issue #73)', (tester) async {
      await plantGhostForToday();

      // The menu route the daily shift is pushed over — a marker
      // screen, so the test can name exactly where MAIN MENU lands.
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
              key: ValueKey('issue73_home'),
              body: Center(child: Text('HOME')),
            ),
          ),
        ),
      );

      // Push today's daily shift the way the menu does — the one route
      // the old button used to stack its second game on top of.
      final home = tester.element(find.text('HOME'));
      Navigator.push(
        home,
        MaterialPageRoute(
          builder: (context) => GameScreen(
            endlessSeed: DailyShift.seedForDateKey(DailyShift.todayKey),
            isDailyShift: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // The daily shift goes live (the control-hint harness's wait:
      // real sprite I/O needs real async time; the panel must never
      // pumpAndSettle over a live game).
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
      expect(game.isGameActive, isTrue);

      // Settle the shift through its public seams: a score, then the
      // pause menu's bank.
      game.fareChain.awardNearMiss();
      game.bankFromPause();
      await tester.pump();
      expect(find.byKey(const ValueKey('run_summary_panel')), findsOneWidget,
          reason: 'the daily\'s summary owns the screen');

      // The race restarts in place: still exactly one game screen on
      // the stack, now a live ghost race of today's course.
      await tester
          .ensureVisible(find.byKey(const ValueKey('race_ghost_button')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('race_ghost_button')));
      await tester.pump();

      expect(find.byType(GameScreen), findsOneWidget,
          reason: 'the finished game was reused, not covered');
      expect(game.isGhostRace, isTrue);
      expect(game.isGameActive, isTrue);
      expect(game.overlays.activeOverlays, isNot(contains('shiftBanked')));

      // Settle the ghost race the same way...
      game.fareChain.awardNearMiss();
      game.bankFromPause();
      await tester.pump();
      expect(find.byKey(const ValueKey('run_summary_panel')), findsOneWidget);

      // ...and one MAIN MENU tap comes home. Stacked, the pop would
      // have landed on the daily's old summary instead of the menu.
      await tester.ensureVisible(find.text('MAIN MENU'));
      await tester.pump();
      await tester.tap(find.text('MAIN MENU'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('HOME'), findsOneWidget,
          reason: 'one tap, one route popped: the menu');
      expect(find.byType(GameScreen), findsNothing);
      expect(find.byKey(const ValueKey('run_summary_panel')), findsNothing,
          reason: 'no older summary was left underneath');
    });
  });

  group('the shift-over game goes quiet (issue #73)', () {
    test('update() asserts nothing at the engine once the shift settles',
        () async {
      final audio = _EngineCountingAudio();
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        audio: audio,
        endlessSeed: 9,
      )
        ..overlays.addEntry(
            'shiftBanked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry(
            'shiftWrecked', (_, __) => const SizedBox.shrink());

      // The endless-run mount: chunks arm their world in onMount, so a
      // bare onLoad would leave the road unmanaged.
      game.onGameResize(Vector2(400, 800));
      await game.onLoad();
      // ignore: invalid_use_of_internal_member
      game.mount();
      await game.ready();

      // Settle the shift the way a real one does: a score, then the
      // pause menu's bank.
      game.fareChain.awardNearMiss();
      game.bankFromPause();
      expect(game.isShiftOver, isTrue, reason: 'precondition: settled');

      // The frames the summary sits through — under the old code each
      // one re-asserted engine-off through the shared AudioService,
      // fighting any live game driven over it.
      audio.runningCalls = 0;
      audio.intensityCalls = 0;
      for (var i = 0; i < 10; i++) {
        game.update(1 / 60);
      }

      expect(audio.runningCalls, 0,
          reason: 'a settled shift has no engine claim to assert');
      expect(audio.intensityCalls, 0);
    });
  });
}
