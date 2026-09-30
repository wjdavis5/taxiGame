import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/bank_prompt.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/lives.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/widgets/bank_prompt_overlay.dart';

/// The bank-or-push decision at every endless dropoff (issue #13): a
/// timed choice that never stops the game, where banking is the only way
/// to make the score permanent and pushing raises the multiplier.
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

  /// Mounts [game] headlessly so component `onLoad` hooks run (the
  /// endless-run test pattern; [Game.mount] is what GameWidget calls in
  /// production).
  /// Advances game time by [seconds], in clamped frames (issue #36): no
  /// single frame may consume more than [TaxiGame.maxUpdateDelta], so
  /// fast-forwarding a shift means many small frames, never one giant
  /// one — exactly the invariant the live game now runs under.
  void advanceGameTime(TaxiGame game, double seconds) {
    var remaining = seconds;
    while (remaining > 0) {
      final step = math.min(remaining, TaxiGame.maxUpdateDelta);
      game.update(step);
      remaining -= step;
    }
  }

  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  /// Headless games have no overlay builder map; the decision flow adds
  /// and removes 'bankOrPush' and 'shiftBanked', and the crash path adds
  /// 'levelFailed' in level mode or 'shiftWrecked' at the third endless
  /// crash (issue #14), so register stand-ins as [GameScreen] does.
  TaxiGame endlessGame(int seed) => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: seed,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('pauseMenu', (_, __) => const SizedBox.shrink());

  /// Lets pending component mounts finish before the next simulated tick.
  Future<void> drain() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.value();
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> tickAndSettle(TaxiGame game) async {
    game.update(1 / 60);
    await drain();
    game.update(1 / 60);
    await drain();
  }

  /// Delivers [fare] by teleporting the taxi to its kerbs, the way the
  /// endless-run tests do. Assumes the fare's zones are mounted.
  void deliverFare(TaxiGame game, EndlessFare fare) {
    game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
    game.update(1 / 60);
    expect(game.player.hasPassenger, isTrue, reason: 'passenger boarded');
    game.player.position = Vector2(fare.dropoff.x, fare.dropoff.y + 30);
    game.update(1 / 60);
  }

  group('the choice at an endless dropoff', () {
    test('a completed dropoff arms the choice without stopping the game',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      deliverFare(game, game.course!.fare(0));

      expect(game.bankPrompt.isActive, isTrue);
      expect(
        game.bankPrompt.remainingSeconds,
        closeTo(BankPrompt.windowSeconds, 1 / 30),
        reason: 'the window opens fully stocked (less the dropoff frame)',
      );
      expect(game.overlays.isActive('bankOrPush'), isTrue);
      // The prompt rides above a live street: the shift goes on whether
      // or not the player answers.
      expect(game.isGameActive, isTrue);
    });

    test('level deliveries arm nothing — levels settle at completion',
        () async {
      // Mounted headless with no endlessSeed: a level run.
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      )
        ..overlays.addEntry('levelComplete', (_, __) => const SizedBox.shrink());
      await mountGame(game);

      final pickup = game.currentLevel.pickupPoints.first;
      final dropoff = game.currentLevel.dropoffPoints.first;
      game.player.position = Vector2(pickup.x, pickup.y + 30);
      game.update(1 / 60);
      game.player.position = Vector2(dropoff.x, dropoff.y + 30);
      game.update(1 / 60);

      expect(game.score, greaterThan(0));
      expect(game.bankPrompt.isActive, isFalse);
      expect(game.overlays.isActive('bankOrPush'), isFalse);
    });

    test('letting the window close pushes on at the increased multiplier',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      expect(game.fareChain.multiplier, 2, reason: 'the delivery stepped it');

      // Six seconds of game time across a five-second window.
      advanceGameTime(game, 6);

      expect(game.bankPrompt.isActive, isFalse);
      expect(game.overlays.isActive('bankOrPush'), isFalse);
      expect(game.fareChain.multiplier, 3,
          reason: 'the default is pushing on, bonus and all');
      expect(game.isGameActive, isTrue,
          reason: 'the shift never stopped to ask');

      // The increased multiplier prices the next fare.
      await tickAndSettle(game);
      final fare1 = game.course!.fare(1);
      deliverFare(game, fare1);
      expect(game.score, fare0.reward + 3 * fare1.reward,
          reason: 'the next fare pays at the pushed multiplier');
    });

    test('banking pays the score into the wallet 1:1 and ends the shift',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final coinsBefore = gameState.totalCoins;

      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      // The fare itself already paid its base coins; the score sits
      // unbanked on top.
      expect(gameState.totalCoins, coinsBefore + fare0.reward);
      expect(game.score, fare0.reward);

      game.bankShift();

      expect(game.lastBankedScore, fare0.reward);
      expect(gameState.totalCoins, coinsBefore + fare0.reward + fare0.reward,
          reason: 'banking converts the score 1:1 into coins');
      expect(game.isGameActive, isFalse, reason: 'the shift is over');
      expect(game.overlays.isActive('shiftBanked'), isTrue);
      expect(game.overlays.isActive('bankOrPush'), isFalse);
      // The run summary (issue #15) carries the distance the shift
      // covered by the time it was banked.
      expect(game.lastRunSummary!.distancePx, greaterThan(0));
    });

    test('a crash kills the open prompt and leaves the score unbanked',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final coinsBefore = gameState.totalCoins;

      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      expect(game.bankPrompt.isActive, isTrue);
      expect(game.score, fare0.reward);

      game.onCrash();

      expect(game.bankPrompt.isActive, isFalse);
      expect(game.overlays.isActive('bankOrPush'), isFalse);
      expect(game.fareChain.multiplier, 1,
          reason: 'the crash breaks the chain, dismissing the prompt '
              'without its push bonus');
      expect(game.lives.remaining, LivesTracker.maxLives - 1,
          reason: 'the crash spends a life, not the shift');
      expect(game.isGameActive, isFalse,
          reason: 'the crash stalls the shift before it resumes');
      // The unbanked score never reached the wallet: only the fare's
      // base coins did. It is still on the table for the bank prompt at
      // the next dropoff.
      expect(gameState.totalCoins, coinsBefore + fare0.reward);
      expect(game.score, fare0.reward,
          reason: 'the score survives the crash, still at risk');

      // And once the stall plays out, the shift resumes with all of it.
      advanceGameTime(game, TaxiGame.crashStallSeconds + 0.01);
      expect(game.isGameActive, isTrue);
      expect(game.overlays.activeOverlays, isEmpty,
          reason: 'no end-of-shift panel for a survivable crash');
    });

    test('pushing twice pays the bonus once', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      deliverFare(game, game.course!.fare(0));
      expect(game.fareChain.multiplier, 2);

      game.pushOn();
      expect(game.fareChain.multiplier, 3);
      expect(game.bankPrompt.isActive, isFalse);

      game.pushOn();
      expect(game.fareChain.multiplier, 3,
          reason: 'a resolved prompt cannot pay out again');
    });

    test('a fresh shift clears the decision and the banked summary',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      deliverFare(game, game.course!.fare(0));
      game.bankShift();
      expect(game.lastBankedScore, isNotNull);

      await game.startEndlessRun(seed: 43);

      expect(game.lastBankedScore, isNull);
      expect(game.lastRunSummary, isNull);
      expect(game.bankPrompt.isActive, isFalse);
      expect(game.overlays.isActive('bankOrPush'), isFalse);
      expect(game.score, 0);
      expect(game.isGameActive, isTrue);
    });
  });

  group('the prompt widget', () {
    /// Mounts an endless game and delivers [fare], inside [tester.runAsync]:
    /// mounting loads real sprite assets, and real IO can only complete in
    /// the test binding's real-async window — the fake-async zone of a
    /// widget test would deadlock on it. Everything after this call is
    /// synchronous game ticks, which the fake-async zone handles fine.
    Future<TaxiGame> armedGame(
      WidgetTester tester,
      EndlessFare fare,
    ) async {
      // runAsync is declared Future<T?> — the callback cannot return null
      // here, so unwrap.
      final game = await tester.runAsync<TaxiGame>(() async {
        final game = await mountGame(endlessGame(42));
        await tickAndSettle(game);
        deliverFare(game, fare);
        return game;
      });
      return game!;
    }

    Future<void> showPrompt(WidgetTester tester, TaxiGame game) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: BankPromptOverlay(game: game)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150)); // poll tick
    }

    testWidgets('offers both options priced, over a live game',
        (tester) async {
      // The course is a pure function of the seed, so the fare the
      // mounted game will hold can be looked up before mounting.
      final fare0 = EndlessCourse(seed: 42).fare(0);
      final game = await armedGame(tester, fare0);
      await showPrompt(tester, game);

      expect(find.text('BANK ${fare0.reward}'), findsOneWidget);
      expect(find.text('PUSH ON \u00d73'), findsOneWidget,
          reason: 'the push button shows the multiplier it buys');
      expect(find.text('AT RISK ${fare0.reward}'), findsOneWidget,
          reason: 'the header names the currency: the score is at risk, '
              'not yet the wallet\'s');
      expect(find.byKey(const ValueKey('bank_prompt_bar')), findsOneWidget,
          reason: 'the window shows itself running out');
    });

    testWidgets('renders nothing while no choice is open', (tester) async {
      final game = (await tester.runAsync<TaxiGame>(() async {
        final game = await mountGame(endlessGame(42));
        await tickAndSettle(game);
        return game;
      }))!;
      await showPrompt(tester, game);

      expect(find.text('BANK OR PUSH?'), findsNothing);
    });

    testWidgets('tapping PUSH ON raises the multiplier and stands down',
        (tester) async {
      final fare0 = EndlessCourse(seed: 42).fare(0);
      final game = await armedGame(tester, fare0);
      await showPrompt(tester, game);

      await tester.tap(find.text('PUSH ON \u00d73'));
      await tester.pump(const Duration(milliseconds: 150));

      expect(game.fareChain.multiplier, 3);
      expect(game.bankPrompt.isActive, isFalse);
      expect(game.isGameActive, isTrue, reason: 'pushing keeps the shift');
      expect(find.text('BANK ${fare0.reward}'), findsNothing,
          reason: 'the prompt stood down with the choice');
    });

    testWidgets('tapping BANK pays out and ends the shift', (tester) async {
      final coinsBefore = gameState.totalCoins;
      final fare0 = EndlessCourse(seed: 42).fare(0);
      final game = await armedGame(tester, fare0);
      await showPrompt(tester, game);

      await tester.tap(find.text('BANK ${fare0.reward}'));
      await tester.pump(const Duration(milliseconds: 150));

      expect(game.lastBankedScore, fare0.reward);
      expect(gameState.totalCoins, coinsBefore + fare0.reward + fare0.reward);
      expect(game.isGameActive, isFalse);
      expect(game.overlays.isActive('shiftBanked'), isTrue);
    });
  });

  group("the primer: the first offer a save ever sees", () {
    test('stops traffic for the first offer and releases it on the answer',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      expect(game.paused, isFalse, reason: 'sanity: the shift starts live');

      deliverFare(game, game.course!.fare(0));

      expect(game.bankPrompt.isActive, isTrue);
      expect(game.paused, isTrue,
          reason: 'the first-ever choice is read, not reacted to');
      expect(gameState.bankPromptSeen, isTrue,
          reason: 'the primer is once per save, and it is already spent');

      game.pushOn();
      expect(game.paused, isFalse, reason: 'the answer releases the freeze');
      expect(game.fareChain.multiplier, 3);
    });

    test('an offer to a save that has already seen one rides live traffic',
        () async {
      gameState.markBankPromptSeen();
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      deliverFare(game, game.course!.fare(0));

      expect(game.bankPrompt.isActive, isTrue);
      expect(game.paused, isFalse,
          reason: 'only the first-ever offer stops the world');
    });

    test('the pause button stands down while the primer holds the freeze',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      deliverFare(game, game.course!.fare(0));

      game.pauseGame();
      expect(game.overlays.isActive('pauseMenu'), isFalse,
          reason: 'the primer already owns the freeze; no menu stacks on it');

      game.resumeGame();
      expect(game.paused, isTrue,
          reason: 'a stray resume cannot unfreeze the primer');

      game.bankShift();
      expect(game.paused, isFalse,
          reason: 'the choice itself is still the way out');
    });
  });

  group('banking out of the pause menu', () {
    test('pays the at-risk score out and ends the shift with its summary',
        () async {
      final coinsBefore = gameState.totalCoins;
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      game.fareChain.score = 240;

      game.bankFromPause();

      expect(game.lastBankedScore, 240);
      expect(gameState.totalCoins, coinsBefore + 240);
      expect(game.overlays.isActive('shiftBanked'), isTrue,
          reason: 'quitting through the bank earns the summary, not silence');
      expect(game.isGameActive, isFalse);
    });

    test('is a no-op without a score to protect', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      game.bankFromPause();

      expect(game.overlays.isActive('shiftBanked'), isFalse);
      expect(game.lastBankedScore, isNull);
    });
  });

  group('a settled shift closes the bank (issue #52)', () {
    test('banking twice: the second pause-menu bank pays nothing', () async {
      final coinsBefore = gameState.totalCoins;
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      game.fareChain.score = 500;

      game.bankFromPause();
      expect(gameState.totalCoins, coinsBefore + 500);
      final historyAfterBank = gameState.runHistory.length;

      // The issue's exploit, verbatim: the summary leaves the top-right
      // pause button reachable, the menu still reads "500 coins at
      // risk", and every BANK 500 & QUIT tap paid out again.
      game.pauseGame();
      expect(game.overlays.isActive('pauseMenu'), isFalse,
          reason: 'the summary owns the screen; no menu stacks under it');
      game.bankFromPause();

      expect(gameState.totalCoins, coinsBefore + 500,
          reason: 'a settled shift has nothing left to pay');
      expect(gameState.runHistory.length, historyAfterBank,
          reason: 'and no extra run records either');
      expect(game.isShiftOver, isTrue);
    });

    test('a wrecked shift\'s forfeited score pays nothing through the '
        'pause menu', () async {
      final coinsBefore = gameState.totalCoins;
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      game.fareChain.score = 400; // the forfeit the wreck panel names

      for (var life = 0; life < 3; life++) {
        if (life > 0) {
          // Run out the previous crash's stall so the next crash counts.
          advanceGameTime(game, TaxiGame.crashStallSeconds + 0.01);
        }
        game.onCrash();
      }
      await drain();
      expect(game.overlays.isActive('shiftWrecked'), isTrue);

      game.pauseGame();
      game.bankFromPause();

      expect(gameState.totalCoins, coinsBefore,
          reason: 'the forfeited score was never the wallet\'s to pay');
      expect(game.isShiftOver, isTrue);
    });

    test('a bank made during a crash stall stays ended — the stall cannot '
        'resume the world under the summary', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      game.fareChain.score = 240;

      game.onCrash(); // a life spent; the 1.2 s stall begins
      game.pauseGame(); // still legal mid-stall — the shift is live
      game.bankFromPause();
      expect(game.overlays.isActive('shiftBanked'), isTrue);

      // Two seconds of frames — past the stall's full countdown. Before
      // the fix the countdown finished here and flipped [isGameActive]
      // back on underneath the panel, engine and stick included.
      advanceGameTime(game, 2.0);

      expect(game.isGameActive, isFalse,
          reason: 'the stall must not resume the world under the panel');
      expect(game.isShiftOver, isTrue);
    });

    test('a fresh shift re-arms the pause menu', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      game.fareChain.score = 240;
      game.bankFromPause();
      expect(game.isShiftOver, isTrue);

      // DRIVE AGAIN: the summary is gone and the next shift is a live
      // run with a working pause menu again.
      game.retryShift();
      await tickAndSettle(game);

      expect(game.isShiftOver, isFalse);
      expect(game.isGameActive, isTrue);
      game.pauseGame();
      expect(game.overlays.isActive('pauseMenu'), isTrue,
          reason: 'the fresh shift has a pause menu to offer again');
      game.resumeGame();
      expect(game.paused, isFalse);
    });
  });
}
