import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/bank_prompt.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/lives.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/widgets/bank_prompt_overlay.dart';
import 'package:taxi_game/ui/widgets/hud_overlay.dart';

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

    testWidgets('a prompt with no badge band settles: the steady state owns '
        'no frames (issue #139)', (tester) async {
      // The common prompt — no daily ghost, so no band to arbitrate and
      // no re-park ever owed. The post-frame measurement used to read
      // `false == false` (no oust, no below-band park) as a branch flip
      // and setState after every painted frame, a self-sustaining
      // rebuild loop for the prompt's whole window at 60 fps.
      final fare0 = EndlessCourse(seed: 42).fare(0);
      final game = await armedGame(tester, fare0);
      await showPrompt(tester, game);
      expect(find.byKey(const ValueKey('bank_prompt_panel')), findsOneWidget);
      expect(game.bankPanelOustsGhostBadge, isFalse,
          reason: 'sanity: no ghost on this road, so no band to claim');

      // Drain: the measurement has landed, any re-park it asked for has
      // painted, and one more zero-duration frame consumes whatever the
      // last frame scheduled.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      // Nothing may want another frame: the overlay's own rebuilds ride
      // its 100 ms poll timer, which only fires inside a pump with
      // duration — a pending frame here is the loop.
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'the fit measurement must not keep scheduling frames '
              'once it agrees with the layout it measured');
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

  group('the panel and the ghost badge (issues #130, #134, #139)', () {
    /// Plants a daily ghost so a ghost race has a car to race — the
    /// scoring HUD's pattern.
    Future<void> plantGhost() async {
      await gameState.recordDailyGhostRun(
        dateKey: DailyShift.todayKey,
        score: 500,
        banked: true,
        vehicleId: 'taxi_yellow',
        samples: const [200, 0, 200, -100, 200, -200],
      );
    }

    /// Mounts a ghost race and arms the save's first-ever offer through
    /// the real delivery flow. Being the primer, that offer freezes the
    /// world under the prompt, so the window cannot expire
    /// mid-measurement; the planted ghost keeps a live gap for the
    /// badge to read. All of it inside the test binding's real-async
    /// window: mounting loads real sprite assets, and the settle
    /// between the arming ticks awaits real futures — the fake-async
    /// zone outside would deadlock on both. Everything after is pumps
    /// and synchronous reads.
    Future<TaxiGame> primerArmedGhostRace(WidgetTester tester) async {
      final mountedGame = await tester.runAsync<TaxiGame>(() async {
        final game = TaxiGame(
          levelLoader: LevelLoaderService(),
          gameState: gameState,
          endlessSeed: DailyShift.seedForDateKey(DailyShift.todayKey),
          isGhostRace: true,
        )
          ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
          ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
          ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
          ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink())
          ..overlays.addEntry('pauseMenu', (_, __) => const SizedBox.shrink());
        game.onGameResize(Vector2(400, 800));
        await game.onLoad();
        // ignore: invalid_use_of_internal_member
        game.mount();
        await game.ready();
        await tickAndSettle(game);

        // No GameWidget drives a headless game: tick the run by hand so
        // the ghost runs off the start line and the gap goes live while
        // the player holds it.
        for (var i = 0; i < 30; i++) {
          game.update(1 / 60);
        }

        deliverFare(game, game.course!.fare(0));
        return game;
      });
      return mountedGame!;
    }

    testWidgets('where the lane fits both, the badge reads on through the '
        'window and the panel parks below it (issues #130, #139)',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await plantGhost();
      final game = await primerArmedGhostRace(tester);
      expect(game.bankPrompt.isActive, isTrue);
      expect(game.ghostGapMetres, isNotNull,
          reason: 'sanity: the race has a live gap to read');

      // The issue's tall-phone surface, 430×932 pt: the lane below the
      // badge band runs 301.75 − 47 ≈ 254.75 px, and the panel's
      // natural height at 1.0 text sits around 130 px under the Ahem
      // test font — both fit with room to spare. (The width binds the
      // world scale on this surface: min(430/400, 932/800) = 1.075, so
      // the half-cab offset uses 430/400.)
      tester.view.physicalSize = const Size(430, 932);
      const nose = 932 / 2 - 30 * (430 / 400); // ≈ 433.75
      const cabClearance = 12.0;

      // Both overlays in the game screen's stacking order — the HUD
      // first, the prompt above it.
      await tester.pumpWidget(
        ChangeNotifierProvider<GameStateService>.value(
          value: gameState,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  HudOverlay(game: game),
                  BankPromptOverlay(game: game),
                ],
              ),
            ),
          ),
        ),
      );
      // One frame lays the panel out and measures its natural height;
      // the next beat is the 100 ms poll both overlays read the fit
      // from.
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull,
          reason: 'the overlays must lay out cleanly');

      // #139's headline: the readout stays up through the decision
      // window — the race is live under every non-primer offer, and the
      // bank-or-push decision turns on the gap it reads.
      expect(game.bankPanelOustsGhostBadge, isFalse,
          reason: 'the panel fits below the badge band on this surface');
      expect(find.byKey(const ValueKey('ghost_badge')), findsOneWidget);
      expect(find.byKey(const ValueKey('bank_prompt_panel')), findsOneWidget);

      final panel =
          tester.getRect(find.byKey(const ValueKey('bank_prompt_panel')));
      expect(panel.top,
          greaterThanOrEqualTo(120 + HudOverlay.ghostBadgeBandHeight),
          reason: 'the panel parks below the badge band (#130), not in it');
      expect(panel.bottom, lessThanOrEqualTo(nose - cabClearance + 0.5),
          reason: 'and it still stops clear of the cab\'s nose (#134)');

      // The choice resolved: the panel is gone, and the readout never
      // left.
      game.pushOn();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(const ValueKey('bank_prompt_panel')), findsNothing);
      expect(find.byKey(const ValueKey('ghost_badge')), findsOneWidget,
          reason: 'the gap readout is still up once no choice is on screen');
    });

    testWidgets('where the lane cannot fit both, the badge stands down and '
        'the panel keeps the cab clear (issues #134, #139)', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await plantGhost();
      final game = await primerArmedGhostRace(tester);
      expect(game.bankPrompt.isActive, isTrue);

      // The issue's short-phone surface, 375×667 pt, at 1.3× text — the
      // reading at which #134 measured the panel over the cab. The lane
      // below the badge band runs 176.49 − 47 ≈ 129.5 px; at 1.0 text
      // the Ahem panel sits within a few px of that line either way, so
      // the hidden case is pinned at the large text the issue was filed
      // against, where the natural height clears 129.5 unambiguously.
      // (The height binds the world scale on this surface:
      // min(375/400, 667/800) = 0.834, so the half-cab offset uses
      // 667/800.)
      tester.view.physicalSize = const Size(375, 667);
      const nose = 667 / 2 - 30 * (667 / 800); // ≈ 308.49
      const cabClearance = 12.0;

      await tester.pumpWidget(
        ChangeNotifierProvider<GameStateService>.value(
          value: gameState,
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: Scaffold(
                body: Stack(
                  children: [
                    HudOverlay(game: game),
                    BankPromptOverlay(game: game),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      // Two beats: the frame that measures the panel's natural height
      // and raises the oust flag, then the poll tick the HUD reads it
      // on and the panel re-parks in.
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull,
          reason: 'the overlays must lay out cleanly');

      expect(game.bankPanelOustsGhostBadge, isTrue,
          reason: 'the panel\'s natural height at 1.3× text does not fit '
              'below the badge band on this surface');
      expect(find.byKey(const ValueKey('bank_prompt_panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('ghost_badge')), findsNothing,
          reason: 'the panel has claimed the band; the readout stands down '
              'for the window — the only phones that lose it');

      final panel =
          tester.getRect(find.byKey(const ValueKey('bank_prompt_panel')));
      expect(panel.top, greaterThanOrEqualTo(120),
          reason: 'the full-lane panel stays below the HUD band');
      expect(panel.bottom, lessThanOrEqualTo(nose - cabClearance + 0.5),
          reason: 'the panel must stop clear of the cab\'s nose — the cap '
              'holds in the oust branch too (#134)');

      // The choice resolved: the band is the badge's again, and the
      // readout returns with the resolution.
      game.pushOn();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(const ValueKey('ghost_badge')), findsOneWidget,
          reason: 'the gap readout is back once no choice is on screen');
      expect(find.byKey(const ValueKey('bank_prompt_panel')), findsNothing);
    });

    testWidgets('the panel stops short of the cab on a 667 pt phone, at any '
        'text scale (issue #134)', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await plantGhost();
      // The same primer-armed ghost race as the band tests: the freeze
      // holds the window open for the measurement. Whichever branch the
      // fit lands in, the cab bound below must hold.
      final game = await primerArmedGhostRace(tester);
      expect(game.bankPrompt.isActive, isTrue);

      // The iPhone SE/8 class surface the issue was filed against:
      // 375×647 pt. The cab's nose, from the geometry the panel's cap
      // is computed against — the vertically-followed, centred cab,
      // half its 60 px body in screen px at the fixed-resolution world
      // scale min(375/400, 647/800).
      tester.view.physicalSize = const Size(375, 647);
      const nose = 647 / 2 - 30 * (647 / 800); // ≈ 299.2
      const cabClearance = 12.0;

      // The issue's report was at growing text: at 1.0 the full panel
      // barely fits the lane, and at 1.3 it does not — the panel must
      // scale down to the lane rather than ride over the cab.
      for (final textScale in [1.0, 1.3]) {
        await tester.pumpWidget(
          ChangeNotifierProvider<GameStateService>.value(
            value: gameState,
            child: MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
                child: Scaffold(
                  body: Stack(
                    children: [
                      HudOverlay(game: game),
                      BankPromptOverlay(game: game),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 150)); // poll tick
        expect(tester.takeException(), isNull,
            reason: 'at $textScale x text the overlays must lay out cleanly');

        final panel =
            tester.getRect(find.byKey(const ValueKey('bank_prompt_panel')));
        expect(panel.top, greaterThanOrEqualTo(120),
            reason: 'at $textScale x the panel stays below the HUD band');
        expect(panel.bottom, lessThanOrEqualTo(nose - cabClearance + 0.5),
            reason: 'at $textScale x text the panel must stop clear of the '
                'cab\'s nose — #130\'s below-the-badge offset had no lower '
                'bound and covered the cab on this phone');
      }
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

    test('a thumb that centred during the primer freeze drives nothing '
        'after the release (issue #103)', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final stick = game.virtualStick!;

      // A running player's hold: the thumb owns the stick and drives half
      // throttle when the delivery lands.
      stick.onDragStart(DragStartEvent(
        7,
        game,
        DragStartDetails(globalPosition: const Offset(200, 600)),
      ));
      stick.onDragUpdate(DragUpdateEvent(
        7,
        game,
        DragUpdateDetails(
          delta: const Offset(0, -60),
          globalPosition: const Offset(200, 600),
        ),
      ));
      expect(game.player.throttleInput, greaterThan(0));

      // The first-ever offer freezes traffic under the held thumb.
      deliverFare(game, game.course!.fare(0));
      expect(game.paused, isTrue, reason: 'the primer holds the freeze');

      // The thumb centres during the freeze: the offset tracks, but the
      // stick feeds nothing while paused — so the pre-freeze throttle is
      // still the last thing the cab was fed.
      stick.onDragUpdate(DragUpdateEvent(
        7,
        game,
        DragUpdateDetails(
          delta: const Offset(0, 60),
          globalPosition: const Offset(200, 600),
        ),
      ));

      game.pushOn();

      // PUSH ON hands the live street back under the centred thumb: the
      // released primer re-feeds the offset it actually holds, not the
      // drive it froze mid-glide.
      expect(game.paused, isFalse, reason: 'the answer releases the freeze');
      expect(stick.isActive, isTrue,
          reason: 'the freeze never took the thumb off the stick');
      expect(game.player.throttleInput, 0,
          reason: 'the re-fed offset is the origin, without waiting for '
              'the thumb to move again');
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

    testWidgets('hides the pause button while it holds the freeze '
        '(issue #132)', (tester) async {
      // Through the real flow, not set by hand: mount, deliver, and let
      // the save's first-ever offer stop the world. Mounting loads real
      // sprite assets, so it rides the test binding's real-async window
      // (the pattern from the prompt-widget group above); everything
      // after it is synchronous game ticks and pumps.
      final fare0 = EndlessCourse(seed: 42).fare(0);
      final game = (await tester.runAsync<TaxiGame>(() async {
        final game = await mountGame(endlessGame(42));
        await tickAndSettle(game);
        deliverFare(game, fare0);
        return game;
      }))!;
      expect(game.isBankPrimerActive, isTrue,
          reason: 'sanity: the primer holds its freeze');

      await tester.pumpWidget(
        ChangeNotifierProvider<GameStateService>.value(
          value: gameState,
          child: MaterialApp(home: Scaffold(body: HudOverlay(game: game))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150)); // poll tick

      // The primer's freeze makes pauseGame ignore the tap, so the
      // button must not sit in the corner looking live.
      expect(find.byIcon(Icons.pause), findsNothing);

      // The answer releases the freeze, and the control returns with it.
      game.pushOn();
      await tester.pump(const Duration(milliseconds: 150)); // poll tick
      expect(find.byIcon(Icons.pause), findsOneWidget,
          reason: 'a live shift has its pause control back');
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

    test('banking from the prompt while paused ends the shift unpaused '
        '(issue #86)', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // A save that has seen the primer: the offer rides live traffic,
      // so the pause menu can stack over the prompt's buttons — the
      // pause button refuses only the primer itself.
      gameState.markBankPromptSeen();

      deliverFare(game, game.course!.fare(0));
      expect(game.bankPrompt.isActive, isTrue);

      // The pause lands while the choice is up — the HUD button, or the
      // lifecycle handler on return from the background.
      game.pauseGame();
      expect(game.paused, isTrue);
      expect(game.overlays.isActive('pauseMenu'), isTrue);

      // The prompt's BANK, tappable under the menu's card: the shift
      // settles, and the ending must take the pause down with it.
      game.bankShift();
      expect(game.isShiftOver, isTrue);
      expect(game.overlays.isActive('shiftBanked'), isTrue);
      expect(game.paused, isFalse,
          reason: 'the summary owns the screen; nothing stays frozen');
      expect(game.overlays.isActive('pauseMenu'), isFalse,
          reason: 'no stale PAUSED card under the summary');

      // DRIVE AGAIN opens a live run — before the fix it opened frozen,
      // needing an extra RESUME on a menu from the previous shift.
      game.retryShift();
      await tickAndSettle(game);
      expect(game.isShiftOver, isFalse);
      expect(game.isGameActive, isTrue);
      expect(game.paused, isFalse);
    });

    test('a banking lesson banked while paused ends the level unpaused '
        '(issue #86)', () async {
      // Level 9 is the ladder's first banking lesson: bankPrompt on, two
      // fares — so the first delivery asks the question while the second
      // fare is still on the road.
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      )
        ..overlays.addEntry('levelComplete', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('pauseMenu', (_, __) => const SizedBox.shrink());
      await mountGame(game);
      await game.loadLevel(9);
      await tickAndSettle(game);
      gameState.markBankPromptSeen(); // no primer: the lesson runs live

      // Collect both fares en route, then deliver the first (issue
      // #112): a delivery made past an uncollected pickup strands that
      // fare behind the one-way street and fails the level, so the
      // realistic route — each fare collected as the cab reaches it —
      // is the one this test must ride too.
      final pickup = game.currentLevel.pickupPoints.first;
      final secondPickup = game.currentLevel.pickupPoints.last;
      final dropoff = game.currentLevel.dropoffPoints.first;
      game.player.position = Vector2(pickup.x, pickup.y + 30);
      game.update(1 / 60);
      game.player.position = Vector2(secondPickup.x, secondPickup.y + 30);
      game.update(1 / 60);
      game.player.position = Vector2(dropoff.x, dropoff.y + 30);
      game.update(1 / 60);
      expect(game.bankPrompt.isActive, isTrue,
          reason: 'the lesson asks after its first fare');

      game.pauseGame();
      expect(game.paused, isTrue);
      game.bankShift();

      expect(game.overlays.isActive('levelComplete'), isTrue);
      expect(game.paused, isFalse,
          reason: 'the level ending cleared the pause (issue #86)');
      expect(game.overlays.isActive('pauseMenu'), isFalse,
          reason: 'no stale menu under the completion panel');

      // NEXT LEVEL opens the next rung live — not frozen behind a menu
      // left over from the banked one.
      final advanced = await game.startNextLevel();
      expect(advanced, isTrue, reason: 'level 10 exists behind level 9');
      expect(game.isGameActive, isTrue);
      expect(game.paused, isFalse);
    });

    test('a wreck 8 px short of a drop-off delivers nothing and offers '
        'no bank (issue #71)', () async {
      final coinsBefore = gameState.totalCoins;
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // The issue's scenario: the fare is aboard, the cab rolls toward
      // its dropoff at full speed, and the third crash lands before the
      // kerb does. Parked 40 px beyond the delivery spot — clear of the
      // zone's 40-px reach plus the cab's own body.
      final fare = game.course!.fare(0);
      game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
      game.update(1 / 60);
      expect(game.player.hasPassenger, isTrue, reason: 'passenger aboard');
      game.player.position = Vector2(fare.dropoff.x, fare.dropoff.y + 30 + 40);
      game.player.velocity = Vector2(0, -150);

      for (var life = 0; life < 3; life++) {
        if (life > 0) {
          // Run out the previous crash's stall so the next crash counts.
          advanceGameTime(game, TaxiGame.crashStallSeconds + 0.01);
        }
        game.onCrash();
      }
      await drain();
      expect(game.overlays.isActive('shiftWrecked'), isTrue);
      expect(game.isShiftOver, isTrue);

      // The panel is up but the world keeps ticking. A dead stick sheds
      // 150 px/s at 600 px/s^2 — roughly 19 px of coast, enough to carry
      // the old, un-halted cab into the zone it died short of.
      advanceGameTime(game, 1.0);

      // And the gate is not only about momentum: even a cab placed on
      // the delivery spot under the panel must deliver nothing.
      game.player.position = Vector2(fare.dropoff.x, fare.dropoff.y + 30);
      game.update(1 / 60);
      advanceGameTime(game, 0.1);

      expect(game.player.hasPassenger, isTrue,
          reason: 'the fare was never delivered');
      expect(gameState.totalCoins, coinsBefore,
          reason: 'the forfeited fare paid nothing into the wallet');
      expect(game.bankPrompt.isActive, isFalse,
          reason: 'no delivery, no bank-or-push offer over the wreck');
      expect(game.overlays.isActive('bankOrPush'), isFalse);
    });

    test('BANK after the shift is over pays nothing (issue #71)',
        () async {
      final coinsBefore = gameState.totalCoins;
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      game.fareChain.score = 300; // the forfeit the wreck panel names

      for (var life = 0; life < 3; life++) {
        if (life > 0) {
          advanceGameTime(game, TaxiGame.crashStallSeconds + 0.01);
        }
        game.onCrash();
      }
      await drain();
      expect(game.isShiftOver, isTrue);

      // Arm the prompt directly — the way the post-wreck coast used to
      // arm it over the wreck panel — so the guard under test is the
      // bank's, not the prompt's absence.
      game.bankPrompt.offer();

      game.bankShift();

      expect(gameState.totalCoins, coinsBefore,
          reason: 'the forfeited score was never the wallet\'s to pay');
      expect(game.lastBankedScore, isNull);
      expect(game.overlays.isActive('shiftBanked'), isFalse,
          reason: 'a settled shift owns the screen; no banked summary '
              'stacks over the wreck');
      expect(game.isShiftOver, isTrue);
    });
  });
}
