import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/impact_fx.dart';
import 'package:taxi_game/game/systems/lives.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The recording leg of the on-device stats (issue #17): every ended
/// shift — banked or wrecked — lands in the GameStateService history with
/// the whole run's numbers, including where each life was lost and how
/// long the shift was driven. The stats screen is only as truthful as
/// this pipe.
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
  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  /// Headless games have no overlay builder map; the end-of-shift flows
  /// add overlays by name, so register stand-ins as [GameScreen] does in
  /// production.
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
    game.update(ImpactFx.crashHitStopDuration + 0.01);
    game.update(TaxiGame.crashStallSeconds + 0.01);
  }

  group('a banked shift is recorded', () {
    test('the history entry carries the whole run', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      expect(gameState.runHistory, isEmpty,
          reason: 'a shift still running is not a data point yet');

      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);

      // A second of driving, tick by tick, with the shift live.
      for (var i = 0; i < 60; i++) {
        game.update(1 / 60);
      }

      game.bankShift();

      expect(gameState.runHistory.length, 1);
      final record = gameState.runHistory.single;
      expect(record.score, fare0.reward,
          reason: 'the bank paid the run score — the record keeps it');
      expect(record.faresDelivered, 1);
      expect(record.longestChain, 2,
          reason: 'one on-time delivery peaked the chain at 2x');
      expect(record.distancePx, game.lastRunSummary!.distancePx,
          reason: 'the stats record and the summary agree on distance');
      expect(record.banked, isTrue);
      expect(record.livesLost, 0);
      expect(record.lifeLossDistancesPx, isEmpty);
      expect(record.durationSeconds, greaterThan(1.0),
          reason: 'over a second of live driving was ticked');
      expect(record.durationSeconds, lessThan(1.5));
      expect(record.endedAtMs, greaterThan(0));
    });

    test('the aggregate reads the shift immediately', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      deliverFare(game, game.course!.fare(0));
      game.bankShift();

      expect(gameState.runStats.runCount, 1);
      expect(gameState.runStats.bankedShare, 1.0);
    });
  });

  group('a wrecked shift is recorded', () {
    test('the entry knows it was forfeited and where each life went',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      deliverFare(game, game.course!.fare(0));
      final finalDistance = game.runDistance;

      game.onCrash();
      playOutStall(game);
      game.onCrash();
      playOutStall(game);
      game.onCrash(); // the third: shift over

      expect(gameState.runHistory.length, 1);
      final record = gameState.runHistory.single;
      expect(record.banked, isFalse,
          reason: 'a wreck forfeits — the ratio counts it against the bank');
      expect(record.score, greaterThan(0),
          reason: 'the forfeited score is still the shift\'s score');
      expect(record.livesLost, LivesTracker.maxLives);
      expect(record.lifeLossDistancesPx.length, 3);
      for (final px in record.lifeLossDistancesPx) {
        expect(px, greaterThan(0),
            reason: 'the fare delivery moved the taxi before any crash');
        expect(px, lessThanOrEqualTo(finalDistance));
      }
      // The distance never rewinds, so the losses must be non-decreasing.
      final ordered = List.of(record.lifeLossDistancesPx)..sort();
      expect(record.lifeLossDistancesPx, ordered);
    });
  });

  group('achievements ride the same pipe (issue #21)', () {
    /// Delivers [fare] by driving to its kerbs in steps. A stop's zones
    /// spawn only as the camera nears it, and a freshly added zone needs
    /// the microtask queue drained before its async `onLoad` finishes and
    /// its hitbox registers (the same headless-test reason [drain]
    /// exists) — so settle below the kerb until the zone is live, then
    /// step the last stretch in like a real approach.
    Future<void> deliverFareAhead(TaxiGame game, EndlessFare fare) async {
      for (var i = 0;
          i < 120 && game.fareController!.activeFareCount == 0;
          i++) {
        game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 200);
        game.update(1 / 60);
        await drain();
      }
      for (var i = 0; i < 120 && !game.player.hasPassenger; i++) {
        game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
        game.update(1 / 60);
        await drain();
      }
      expect(game.player.hasPassenger, isTrue, reason: 'passenger boarded');
      for (var i = 0; i < 120 && game.player.hasPassenger; i++) {
        game.player.position = Vector2(fare.dropoff.x, fare.dropoff.y + 30);
        game.update(1 / 60);
        await drain();
      }
      expect(game.player.hasPassenger, isFalse, reason: 'fare delivered');
    }

    test('the settled summary carries what the shift unlocked', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // Two on-time deliveries peak the chain at ×3 (1x → 2x → 3x).
      await deliverFareAhead(game, game.course!.fare(0));
      await deliverFareAhead(game, game.course!.fare(1));

      game.bankShift();

      // The bank is clean (no lives lost), so the shift earned the
      // first chain milestone and the first clean bank.
      final unlocked = game.lastRunSummary!.achievementsUnlocked;
      expect(unlocked.map((a) => a.id), containsAll(<String>[
        'chain_3',
        'bank_clean_1',
      ]));

      // Drained, not duplicated: the service queue is empty now, so a
      // second panel can never re-announce the same award.
      expect(gameState.takePendingAchievementUnlocks(), isEmpty);
    });

    test('a shift that earns nothing carries an empty list', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // No fares, no distance, and a wreck — no bank, no chain: nothing
      // in the catalog measures above its threshold.
      game.onCrash();
      playOutStall(game);
      game.onCrash();
      playOutStall(game);
      game.onCrash();

      expect(game.lastRunSummary!.achievementsUnlocked, isEmpty,
          reason: 'a wreck with no chain and no history earns nothing');
    });
  });

  group('a fresh shift starts a clean stats sheet', () {
    test('DRIVE AGAIN resets the run-local trackers', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      deliverFare(game, game.course!.fare(0));
      game.onCrash();
      playOutStall(game);
      game.onCrash();
      playOutStall(game);
      game.onCrash();
      expect(gameState.runHistory.single.livesLost, 3);

      game.retryShift();
      await drain();

      // Drive the fresh shift a little, then wreck it: the new record
      // must know nothing of the previous one.
      await tickAndSettle(game);
      game.onCrash();
      playOutStall(game);
      game.onCrash();
      playOutStall(game);
      game.onCrash();

      expect(gameState.runHistory.length, 2);
      final record = gameState.runHistory.last;
      expect(record.livesLost, 3,
          reason: 'the retry spent its own three lives, not the old ones');
      expect(record.faresDelivered, 0,
          reason: 'the delivered fare belonged to the previous shift');
      expect(record.durationSeconds, lessThan(1.0),
          reason: 'the driven clock restarted with the fresh shift');
    });
  });
}
