import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/fare_chain.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/passenger_data.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The fare chain (issue #12): the countdown each passenger carries, the
/// multiplier it feeds, and the score it accrues.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A 50-coin fare riding [pickupY] → [dropoffY] on the left kerb.
  PassengerData fareOf(String id, double pickupY, double dropoffY) =>
      PassengerData(
        id: id,
        pickupLocation: Vector2(85, pickupY),
        dropoffLocation: Vector2(85, dropoffY),
        reward: 50,
      );

  group('fare time budget', () {
    test('scales with ride distance around the tuned pace', () {
      // 6 s flat + 1 s per 75 px of ride, floored so no fare is free.
      expect(FareChain.secondsForRide(0), FareChain.minFareSeconds);
      expect(FareChain.secondsForRide(700),
          closeTo(FareChain.baseFareSeconds + 700 / 75, 1e-9));

      // Longer rides get more time than short ones.
      expect(FareChain.secondsForRide(900),
          greaterThan(FareChain.secondsForRide(500)));
    });

    test('clamps extreme rides into a playable window', () {
      // A hop across the road is not free, and no ride — however long —
      // gets an endless budget.
      expect(FareChain.secondsForRide(-50),
          FareChain.minFareSeconds); // defensive: never below the floor
      expect(FareChain.secondsForRide(60), FareChain.minFareSeconds);
      expect(FareChain.secondsForRide(6000), FareChain.maxFareSeconds);
    });
  });

  group('fare time budget under timer pressure (issue #18)', () {
    test('pressure 0 keeps the original, teaching-friendly budgets', () {
      expect(FareChain.secondsForRide(700),
          closeTo(FareChain.baseFareSeconds + 700 / 75, 1e-9));
    });

    test('pressure tightens every term of the budget', () {
      // The worst ride the course can draw: max length plus its full
      // wave-growth bonus (EndlessCourse maxRideLength + rideGrowthMax).
      const worstRide = 975.0;
      final loose = FareChain.secondsForRide(worstRide);
      final mid = FareChain.secondsForRide(worstRide, pressure: 0.5);
      final tight = FareChain.secondsForRide(worstRide, pressure: 1.0);

      expect(tight, lessThan(mid));
      expect(mid, lessThan(loose));
      expect(tight, greaterThan(0));
    });

    test('is continuous in pressure', () {
      var previous = FareChain.secondsForRide(700);
      for (var p = 0.05; p <= 1.0; p += 0.05) {
        final budget = FareChain.secondsForRide(700, pressure: p);
        expect(budget, lessThanOrEqualTo(previous + 1e-9),
            reason: 'monotone tightening at pressure $p');
        expect(previous - budget, lessThan(1.0),
            reason: 'no perceptible jumps at pressure $p');
        previous = budget;
      }
    });

    test('the tightest budget is still winnable at the worst ride',
        () {
      // Winnability floor: the budget must cover the worst ride the
      // course can draw (975 px) at a conservative deep-traffic pace of
      // 100 px/s, plus a flat two seconds of kerb manoeuvring. Below
      // this, deep-run fares become unwinnable and the chain economy
      // stops being about driving.
      const worstRide = 975.0;
      const conservativePace = 100.0;
      const kerbSeconds = 2.0;
      expect(FareChain.secondsForRide(worstRide, pressure: 1.0),
          greaterThanOrEqualTo(worstRide / conservativePace + kerbSeconds));
    });

    test('out-of-range pressure clamps instead of throwing', () {
      expect(FareChain.secondsForRide(700, pressure: -1),
          FareChain.secondsForRide(700));
      expect(FareChain.secondsForRide(700, pressure: 2),
          FareChain.secondsForRide(700, pressure: 1));
    });

    test('startFare passes the pressure through to the countdown', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300); // 700 px ride
      chain.startFare(passenger, pressure: 1.0);
      expect(chain.timerFor(passenger)!.totalSeconds,
          closeTo(FareChain.secondsForRide(700, pressure: 1.0), 1e-9));
    });
  });

  group('the chain', () {
    test('starts empty at 1x', () {
      final chain = FareChain();

      expect(chain.score, 0);
      expect(chain.multiplier, 1);
      expect(chain.isCarryingFare, isFalse);
      expect(chain.mostUrgentTimer, isNull);
    });

    test('an on-time delivery scores value x multiplier and extends the '
        'chain', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);

      expect(chain.isCarryingFare, isTrue);
      expect(chain.timerFor(passenger)!.totalSeconds,
          closeTo(FareChain.secondsForRide(700), 1e-9));

      // First delivery: paid at 1x, and the next fare rides at 2x.
      expect(chain.completeFare(passenger, fareValue: 50),
          FareSettlement.onTime);
      expect(chain.score, 50);
      expect(chain.multiplier, 2);
      expect(chain.isCarryingFare, isFalse);
    });

    test('long chains multiply linearly: each delivery pays value x its '
        'own multiplier', () {
      final chain = FareChain();

      var score = 0;
      for (var i = 0; i < 4; i++) {
        final passenger = fareOf('p$i', 0, -700);
        chain.startFare(passenger);
        chain.update(0.016); // a frame passes, the meter runs
        chain.completeFare(passenger, fareValue: 50);
        score += 50 * (i + 1); // 1x, 2x, 3x, 4x
      }

      expect(chain.score, score);
      expect(chain.multiplier, 5);
    });

    test('the countdown ticks in update and floors at zero', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);
      final timer = chain.timerFor(passenger)!;

      chain.update(1.0);
      expect(timer.remainingSeconds, closeTo(timer.totalSeconds - 1, 1e-9));
      expect(chain.multiplier, 1, reason: 'ticking alone breaks nothing');

      chain.update(timer.totalSeconds); // far past the window
      expect(timer.remainingSeconds, 0);
      expect(timer.isExpired, isTrue);
      expect(timer.fractionRemaining, 0);

      // The expiry broke the chain back to 1x the moment it happened.
      chain.update(1.0);
      expect(chain.multiplier, 1);
    });

    test('a late delivery pays 1x and does not extend the chain', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);
      chain.update(FareChain.secondsForRide(700) + 5);

      expect(chain.multiplier, 1, reason: 'expiry already reset the chain');
      expect(chain.completeFare(passenger, fareValue: 50),
          FareSettlement.late);
      expect(chain.score, 50, reason: 'the ride itself still pays');
      expect(chain.multiplier, 1);
    });

    test('update with no fares aboard changes nothing', () {
      final chain = FareChain();
      chain.update(100);
      expect(chain.multiplier, 1);
      expect(chain.score, 0);
    });

    test('pushing on steps the multiplier past the delivery step '
        '(issue #13)', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);

      chain.completeFare(passenger, fareValue: 50);
      expect(chain.multiplier, 2, reason: 'the delivery alone steps to 2x');

      chain.applyPushBonus();
      expect(chain.multiplier, 3,
          reason: 'the push bonus rides on top of the delivery step');
      expect(chain.score, 50, reason: 'pushing pays nothing by itself');

      // The boosted multiplier prices the next fare.
      final next = fareOf('b', 400, -300);
      chain.startFare(next);
      chain.completeFare(next, fareValue: 50);
      expect(chain.score, 50 + 150);
    });

    test('push bonuses stack across a pushed chain', () {
      final chain = FareChain();

      var multiplier = 1;
      for (var i = 0; i < 3; i++) {
        final passenger = fareOf('p$i', 400, -300);
        chain.startFare(passenger);
        chain.completeFare(passenger, fareValue: 10);
        multiplier += FareChain.multiplierStep;
        chain.applyPushBonus();
        multiplier += FareChain.pushBonusStep;
        expect(chain.multiplier, multiplier);
      }

      // Two steps a dropoff: 1x -> 3x -> 5x -> 7x.
      expect(chain.multiplier, 7);
    });

    test('an expiry wipes the push bonus with the rest of the chain', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);
      chain.completeFare(passenger, fareValue: 50);
      chain.applyPushBonus();
      expect(chain.multiplier, 3);

      chain.startFare(fareOf('b', 400, -300));
      chain.update(FareChain.maxFareSeconds + 2);
      expect(chain.multiplier, 1,
          reason: 'the reset is total — no pushed multiplier survives');
    });

    test('every passenger aboard carries their own countdown', () {
      final chain = FareChain();
      final short = fareOf('short', 400, 0); // 400 px
      final long = fareOf('long', 400, -600); // 1000 px
      chain.startFare(short);
      chain.startFare(long);

      expect(chain.activeFareCount, 2);
      expect(chain.timerFor(short)!.totalSeconds,
          lessThan(chain.timerFor(long)!.totalSeconds));

      // The HUD shows whichever runs out first.
      expect(chain.mostUrgentTimer, same(chain.timerFor(short)));

      // The short ride expires; the long one keeps ticking.
      chain.update(FareChain.secondsForRide(400) + 1);
      expect(chain.timerFor(short)!.isExpired, isTrue);
      expect(chain.timerFor(long)!.isExpired, isFalse);
      expect(chain.multiplier, 1, reason: 'one expiry breaks the chain');

      // The surviving fare still delivers on time and rebuilds the chain.
      expect(chain.completeFare(long, fareValue: 50), FareSettlement.onTime);
      expect(chain.multiplier, 2);
    });

    test('reset clears score, multiplier, and live countdowns', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);
      chain.completeFare(passenger, fareValue: 50);

      chain.reset();

      expect(chain.score, 0);
      expect(chain.multiplier, 1);
      expect(chain.bestMultiplier, 1, reason: 'the best chain resets too');
      expect(chain.isCarryingFare, isFalse);
    });

    test('best chain records the peak multiplier (issue #15)', () {
      final chain = FareChain();
      expect(chain.bestMultiplier, 1);

      // Two clean deliveries: 1x -> 2x -> 3x.
      for (var i = 0; i < 2; i++) {
        final passenger = fareOf('p$i', 400, -300);
        chain.startFare(passenger);
        chain.completeFare(passenger, fareValue: 50);
      }
      expect(chain.multiplier, 3);
      expect(chain.bestMultiplier, 3);
    });

    test('a break lowers the multiplier but never the recorded best '
        '(issue #15)', () {
      final chain = FareChain();
      for (var i = 0; i < 2; i++) {
        final passenger = fareOf('p$i', 400, -300);
        chain.startFare(passenger);
        chain.completeFare(passenger, fareValue: 50);
      }
      expect(chain.bestMultiplier, 3);

      // Let a meter run out: the chain collapses to 1x.
      chain.startFare(fareOf('late', 400, -300));
      chain.update(FareChain.maxFareSeconds + 2);

      expect(chain.multiplier, 1);
      expect(chain.bestMultiplier, 3,
          reason: 'the record of what the chain once was is the point');
    });

    test('a push bonus counts toward the best chain (issue #15)', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);
      chain.completeFare(passenger, fareValue: 50);
      chain.applyPushBonus();

      expect(chain.multiplier, 3);
      expect(chain.bestMultiplier, 3);
    });

    test('breakChain resets the multiplier and nothing else (issue #14)',
        () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);
      chain.completeFare(passenger, fareValue: 50);
      chain.applyPushBonus();
      expect(chain.multiplier, 3);

      // A passenger boards, then the crash lands.
      final aboard = fareOf('b', 300, -400);
      chain.startFare(aboard);

      chain.breakChain();

      expect(chain.multiplier, 1);
      expect(chain.score, 50, reason: 'the unbanked score survives');
      expect(chain.timerFor(aboard), isNotNull,
          reason: 'the passenger aboard keeps their countdown');
    });
  });

  group('a level run scores its fares', () {
    late GameStateService gameState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      gameState = GameStateService(storage);
      await gameState.loadSaveData();
    });

    /// Mounts [game] headlessly so component `onLoad` hooks and collision
    /// callbacks run (the pattern the endless-run tests use; [Game.mount]
    /// is what GameWidget calls in production). A headless game has no
    /// overlay builder map, so the level-complete path — which a delivered
    /// final fare triggers — needs a stand-in entry, as in
    /// `impact_fx_test.dart`.
    Future<TaxiGame> mountGame(TaxiGame game) async {
      game.onGameResize(Vector2(400, 800));
      game.overlays.addEntry(
          'levelComplete', (_, __) => const SizedBox.shrink());
      await game.onLoad();
      // ignore: invalid_use_of_internal_member
      game.mount();
      await game.ready();
      return game;
    }

    Future<void> drain() async {
      for (var i = 0; i < 8; i++) {
        await Future<void>.value();
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('pickup starts the meter sized to the ride; delivery banks it at '
        'the current multiplier', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));

      // Level 1: one fare, (315, 400) → (315, -300) for 50 coins.
      final level = game.currentLevel;
      final pickup = level.pickupPoints.first;
      final dropoff = level.dropoffPoints.first;
      final rideDistance = (dropoff.y - pickup.y).abs().toDouble();

      // Pull up to the kerb.
      game.player.position = Vector2(pickup.x, pickup.y + 30);
      game.update(1 / 60);

      expect(game.player.hasPassenger, isTrue);
      expect(game.fareChain.isCarryingFare, isTrue);
      // The meter starts inside the same frame that ticks it once, so it
      // sits one frame below the full budget.
      expect(
        game.fareChain.mostUrgentTimer!.remainingSeconds,
        closeTo(FareChain.secondsForRide(rideDistance), 1 / 30),
      );

      // Deliver inside the window.
      game.player.position = Vector2(dropoff.x, dropoff.y + 30);
      game.update(1 / 60);
      await drain();

      expect(game.score, 50, reason: 'first fare pays 1x');
      expect(game.fareChain.multiplier, 2);
      expect(game.fareChain.isCarryingFare, isFalse);
      expect(gameState.totalCoins, 50,
          reason: 'the coin economy is unchanged by scoring');
      // The bank-or-push offer is an endless-shift thing (issue #13):
      // levels settle at completion, so no choice is armed here.
      expect(game.bankPrompt.isActive, isFalse);
      expect(game.overlays.isActive('bankOrPush'), isFalse);
    });

    test('reloading a level resets the score with the run', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));

      final pickup = game.currentLevel.pickupPoints.first;
      game.player.position = Vector2(pickup.x, pickup.y + 30);
      game.update(1 / 60);
      expect(game.fareChain.isCarryingFare, isTrue);

      await game.loadLevel(1);

      expect(game.score, 0);
      expect(game.fareChain.multiplier, 1);
      expect(game.fareChain.isCarryingFare, isFalse);
    });
  });
}
