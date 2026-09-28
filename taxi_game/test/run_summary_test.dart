import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/impact_fx.dart';
import 'package:taxi_game/game/systems/lives.dart';
import 'package:taxi_game/game/systems/run_summary.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The end-of-shift run summary (issue #15): every shift end snapshots
/// score, best chain, fares, distance, coins earned, and whether the run
/// beat the personal best — and DRIVE AGAIN restarts without touching the
/// menu.
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

  /// Headless games have no overlay builder map; the end-of-shift flows
  /// add 'shiftBanked' at a bank, 'shiftWrecked' at the third crash, and
  /// 'bankOrPush' at a delivery, so register stand-ins as [GameScreen]
  /// does in production.
  TaxiGame endlessGame(int seed) => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: seed,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());

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

  /// Plays out the aftermath of a survivable crash: the crash hit-stop
  /// burns off first, then the stall elapses and the shift resumes.
  void playOutStall(TaxiGame game) {
    advanceGameTime(game, ImpactFx.crashHitStopDuration + 0.01);
    advanceGameTime(game, TaxiGame.crashStallSeconds + 0.01);
  }

  group('RunSummary', () {
    test('distance reads in metres under a kilometre', () {
      const summary = RunSummary(
        outcome: ShiftOutcome.banked,
        score: 100,
        bestChain: 3,
        faresDelivered: 4,
        distancePx: 1234,
        coinsEarned: 55,
        isPersonalBest: true,
        previousBest: 80,
      );

      expect(summary.distanceLabel, '123 m');
    });

    test('distance reads in kilometres above one', () {
      const summary = RunSummary(
        outcome: ShiftOutcome.wrecked,
        score: 0,
        bestChain: 1,
        faresDelivered: 0,
        distancePx: 12000,
        coinsEarned: 0,
        isPersonalBest: false,
        previousBest: 500,
      );

      expect(summary.distanceLabel, '1.2 km');
    });
  });

  group('a banked shift settles into a summary', () {
    test('the snapshot carries the whole run, and the payout counts as '
        'coins earned', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final coinsBefore = gameState.totalCoins;

      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      game.bankShift();

      final summary = game.lastRunSummary;
      expect(summary, isNotNull,
          reason: 'the panel reads a snapshot, not the live game');
      expect(summary!.outcome, ShiftOutcome.banked);
      expect(summary.score, fare0.reward,
          reason: 'the bank paid the whole run score');
      expect(summary.bestChain, 2,
          reason: 'one on-time delivery peaked the chain at 2x');
      expect(summary.faresDelivered, 1);
      expect(summary.distancePx, greaterThan(0));
      expect(summary.coinsEarned, fare0.reward * 2,
          reason: 'the fare base plus the banked payout');
      expect(summary.isPersonalBest, isTrue,
          reason: 'a fresh save has no best — any score sets one');
      expect(summary.previousBest, 0);

      // Recording the best changed no wallet math: fare base + bank, as
      // before issue #15.
      expect(gameState.totalCoins, coinsBefore + fare0.reward * 2);
      expect(gameState.endlessBestScore, fare0.reward);
      expect(game.overlays.isActive('shiftBanked'), isTrue);
    });

    test('a best nobody beat is shown as the number to beat', () async {
      gameState.recordEndlessScore(100000);

      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      deliverFare(game, game.course!.fare(0));
      game.bankShift();

      expect(game.lastRunSummary!.isPersonalBest, isFalse);
      expect(game.lastRunSummary!.previousBest, 100000);
    });

    test('a stored best that falls is beaten, with the old best kept for '
        'the panel', () async {
      gameState.recordEndlessScore(1);

      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      deliverFare(game, game.course!.fare(0));
      game.bankShift();

      expect(game.lastRunSummary!.isPersonalBest, isTrue);
      expect(game.lastRunSummary!.previousBest, 1);
      expect(gameState.endlessBestScore, greaterThan(1));
    });
  });

  group('a wrecked shift settles into a summary', () {
    test('the snapshot carries the run, and only fare coins were earned',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final coinsBefore = gameState.totalCoins;

      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);

      game.onCrash();
      playOutStall(game);
      game.onCrash();
      playOutStall(game);
      game.onCrash(); // the third: no report, so no hit-stop — panel now

      expect(game.overlays.isActive('shiftWrecked'), isTrue);

      final summary = game.lastRunSummary!;
      expect(summary.outcome, ShiftOutcome.wrecked);
      expect(summary.score, fare0.reward,
          reason: 'the unbanked score died with the shift');
      expect(summary.bestChain, 2,
          reason: 'the crash broke the chain but not the record of it');
      expect(summary.faresDelivered, 1);
      expect(summary.coinsEarned, fare0.reward,
          reason: 'only the fare base ever reached the wallet');
      expect(summary.isPersonalBest, isTrue,
          reason: 'the forfeited score still counts as a score');
      expect(gameState.totalCoins, coinsBefore + fare0.reward);
      expect(game.lives.remaining, 0);
      expect(game.lives.isExhausted, isTrue);
    });

    test('exhausting the budget refills on retry, straight into driving',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      deliverFare(game, game.course!.fare(0));
      game.onCrash();
      playOutStall(game);
      game.onCrash();
      playOutStall(game);
      game.onCrash();
      expect(game.overlays.isActive('shiftWrecked'), isTrue);

      // What the summary's DRIVE AGAIN button calls.
      game.retryShift();
      await drain();

      expect(game.overlays.activeOverlays, isEmpty,
          reason: 'the summary panel is gone — no menu in between');
      expect(game.isGameActive, isTrue,
          reason: 'the player is back behind the wheel immediately');
      expect(game.lives.remaining, LivesTracker.maxLives);
      expect(game.fareChain.score, 0, reason: 'a fresh shift, fresh chain');
      expect(game.lastRunSummary, isNull,
          reason: 'the settled shift is cleared with the rest');
      expect(game.isEndless, isTrue, reason: 'the retry is still endless');
    });

    test('retry after a bank also restarts immediately', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      deliverFare(game, game.course!.fare(0));
      game.bankShift();
      expect(game.overlays.isActive('shiftBanked'), isTrue);

      game.retryShift();
      await drain();

      expect(game.overlays.activeOverlays, isEmpty);
      expect(game.isGameActive, isTrue);
      expect(game.lives.remaining, LivesTracker.maxLives);
    });
  });

  group('a fresh shift clears the settled summary', () {
    test('starting a run resets the snapshot and the coin tally',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      deliverFare(game, game.course!.fare(0));
      game.bankShift();
      expect(game.lastRunSummary, isNotNull);

      await game.startEndlessRun(seed: 43);

      expect(game.lastRunSummary, isNull);
      expect(game.isGameActive, isTrue);
    });
  });
}
