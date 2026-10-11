import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/coin_pop.dart';
import 'package:taxi_game/game/components/economy_pops.dart';
import 'package:taxi_game/game/systems/fare_chain.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/fare_type.dart';
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
      expect(chain.completeFare(passenger, fareValue: 50).outcome,
          FareOutcome.onTime);
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
      expect(chain.completeFare(passenger, fareValue: 50).outcome,
          FareOutcome.late);
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
      expect(chain.completeFare(long, fareValue: 50).outcome,
          FareOutcome.onTime);
      expect(chain.multiplier, 2);
    });

    test('a late rider no longer wins the urgency pick over a live '
        'countdown (issue #126)', () {
      final chain = FareChain();
      final stale = fareOf('stale', 400, -300); // 700 px ride
      final fresh = fareOf('fresh', 400, -600); // 1000 px: the longer clock
      chain.startFare(stale);
      chain.startFare(fresh);

      // Stale's meter runs out while both ride; fresh's keeps ticking.
      chain.update(FareChain.secondsForRide(700) + 1);
      expect(chain.timerFor(stale)!.isExpired, isTrue);
      expect(chain.timerFor(fresh)!.isExpired, isFalse);

      // The live clock is the urgent one. A meter floored at zero always
      // won the old plain min, parking the badge on LATE while fresh's
      // countdown ran out unseen — the one warning the badge exists for.
      expect(chain.mostUrgentTimer, same(chain.timerFor(fresh)));

      // Once every rider aboard is expired, LATE is all there is to
      // show: the fallback still surfaces a spent meter rather than
      // nothing. (Which one is unspecified — any expired rider reads
      // the same.)
      chain.update(FareChain.maxFareSeconds);
      expect(chain.mostUrgentTimer, isNotNull);
      expect(chain.mostUrgentTimer!.isExpired, isTrue);
    });

    test('a lone expired rider still surfaces for the LATE read (issue '
        '#126)', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);
      chain.update(FareChain.secondsForRide(700) + 5);

      expect(chain.mostUrgentTimer, same(chain.timerFor(passenger)),
          reason: 'nothing live is aboard — the late read is the read');
    });

    test('a stale expired rider no longer re-breaks the chain every '
        'frame (issue #120)', () {
      final chain = FareChain();

      // Fare A's meter runs out while they are still aboard: the chain
      // breaks on that crossing frame, and A rides on expired until the
      // dropoff finally settles them late.
      final stale = fareOf('stale', 400, -300);
      chain.startFare(stale);
      chain.update(FareChain.secondsForRide(700) + 5);
      expect(chain.multiplier, 1, reason: 'the crossing frame broke it');

      // Fare B, delivered on time while A rides: the delivery rebuilds
      // the chain — and the rebuild must survive the frames after it.
      // Before issue #120 those frames re-checked "is any timer
      // expired", found A's floored clock, and wiped the x2 one tick
      // after the delivery paid it.
      final fresh = fareOf('fresh', 400, -300);
      chain.startFare(fresh);
      expect(chain.completeFare(fresh, fareValue: 50).outcome,
          FareOutcome.onTime);
      expect(chain.multiplier, 2);
      chain.update(1 / 60);
      expect(chain.multiplier, 2,
          reason: 'the rebuild must hold the frame after it is paid');

      // Same for the push at the dropoff: the prompt promised PUSH ON
      // at the stepped multiplier, so the push must be worth that much
      // on the frames that follow it, not for exactly one tick.
      chain.applyPushBonus();
      expect(chain.multiplier, 3);
      chain.update(1 / 60);
      expect(chain.multiplier, 3,
          reason: 'a push bonus that survives one frame earns nothing');
      expect(chain.bestMultiplier, 3,
          reason: 'the record now describes a chain that actually held');

      // The stale passenger's own dropoff still settles late — and that
      // settlement is still the break it always was: riding expired
      // re-broke nothing, but delivering late does.
      expect(chain.completeFare(stale, fareValue: 50).outcome,
          FareOutcome.late);
      expect(chain.score, 100,
          reason: 'B paid 50 x1 then the delivery stepped to 2x; A pays '
              '50 x1 late');
      expect(chain.multiplier, 1);
      expect(chain.isCarryingFare, isFalse);
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

  group('the settlement breakdown (issue #270)', () {
    test('an on-time fare reports its value, multiplier, award, and the '
        'at-risk total it left', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);

      final settlement = chain.completeFare(passenger, fareValue: 50);

      expect(settlement.outcome, FareOutcome.onTime);
      expect(settlement.isLate, isFalse);
      expect(settlement.fareValue, 50);
      expect(settlement.multiplier, 1,
          reason: 'the first fare of a run rides at 1x');
      expect(settlement.chainStepBonus, 0, reason: 'a standard fare');
      expect(settlement.scoreAwarded, 50);
      expect(settlement.scoreTotal, 50);
    });

    test('a late fare reports a flat 1x, no bonus, and the total it holds',
        () {
      final chain = FareChain();
      final first = fareOf('first', 400, -300);
      chain.startFare(first);
      chain.completeFare(first, fareValue: 50);

      final late = fareOf('late', 400, -300);
      chain.startFare(late);
      chain.update(FareChain.secondsForRide(700) + 5);

      final settlement = chain.completeFare(late, fareValue: 50);

      expect(settlement.outcome, FareOutcome.late);
      expect(settlement.isLate, isTrue);
      expect(settlement.multiplier, 1, reason: 'late pays a flat rate');
      expect(settlement.chainStepBonus, 0);
      expect(settlement.scoreAwarded, 50);
      expect(settlement.scoreTotal, 100,
          reason: 'the late fare still adds to the at-risk total');
    });

    test('a delivered long-haul names the chain bonus it paid', () {
      final chain = FareChain();
      final longHaul = PassengerData(
        id: 'long',
        pickupLocation: Vector2(400, 400),
        dropoffLocation: Vector2(400, -300),
        reward: 60,
        fareType: FareType.longHaul,
      );
      chain.startFare(longHaul);

      final settlement = chain.completeFare(longHaul, fareValue: 60);

      expect(settlement.chainStepBonus, FareType.longHaul.chainStepBonus);
      expect(settlement.multiplier, 1);
      expect(settlement.scoreAwarded, 60);
      expect(settlement.scoreTotal, 60);
      expect(chain.multiplier,
          1 + FareChain.multiplierStep + FareType.longHaul.chainStepBonus);
    });

    test('update reports the crossing that broke the chain (issue #273)',
        () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);

      expect(chain.update(0.5), isFalse, reason: 'a live meter breaks nothing');

      final timer = chain.timerFor(passenger)!;
      expect(chain.update(timer.totalSeconds), isTrue,
          reason: 'the crossing frame is the chain-breaking one');
      expect(chain.multiplier, 1);
      expect(chain.update(1.0), isFalse,
          reason: 'riding expired is not a second break (issue #120)');
    });
  });

  group('the passenger tip (issue #276)', () {
    test('the tip contract is literally 4 coins an event, 12 a fare', () {
      // The PR states these numbers as the rule, so they are pinned
      // literally here: a silent retune (4 to 3, 12 to 15) must go red,
      // not hide behind the constants every other assertion references.
      expect(TipRule.thrillPassCoins, 4);
      expect(TipRule.cleanChainCoins, 4);
      expect(TipRule.maxTipCoins, 12);

      // And once through the rule itself, not just the constants: one
      // THRILL PASS pays the literal 4; a spree pays the literal 12.
      final single = FareChain();
      final passenger = fareOf('single', 400, -300);
      single.startFare(passenger);
      single.awardNearMiss();
      expect(single.completeFare(passenger, fareValue: 50).tipCoins, 4);

      final spree = FareChain();
      final spreeRider = fareOf('spree', 400, -300);
      spree.startFare(spreeRider);
      for (var i = 0; i < 4; i++) {
        spree.awardNearMiss();
      }
      expect(spree.completeFare(spreeRider, fareValue: 50).tipCoins, 12);
    });

    test('a THRILL PASS with a fare aboard pays at the dropoff', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);

      // The pass pays the chain exactly as it always did...
      final points = chain.awardNearMiss();
      expect(points, FareChain.nearMissScore, reason: 'the live chain is 1x');
      expect(chain.nearMisses, 1);
      expect(chain.thrillPasses, 1,
          reason: 'the pass landed with a live fare aboard');

      // ...and the ride tips the flat THRILL PASS coins at the kerb.
      final settlement = chain.completeFare(passenger, fareValue: 50);
      expect(settlement.tipCoins, TipRule.thrillPassCoins);
      expect(settlement.thrillPasses, 1);
      expect(settlement.scoreAwarded, 50,
          reason: 'the tip is wallet coins, never chain score');
      expect(settlement.scoreTotal, 50 + FareChain.nearMissScore);
      expect(chain.score, 50 + FareChain.nearMissScore,
          reason: 'the tip never entered the at-risk total');
    });

    test('a close call with nobody aboard pays no tip', () {
      final chain = FareChain();
      chain.awardNearMiss();
      expect(chain.nearMisses, 1, reason: 'the chain still pays for it');
      expect(chain.thrillPasses, 0, reason: 'no passenger felt it');

      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);
      final settlement = chain.completeFare(passenger, fareValue: 50);
      expect(settlement.tipCoins, 0);
      expect(settlement.thrillPasses, 0);
    });

    test('the tip is deterministic: the same ride, the same coins', () {
      int tipFor() {
        final chain = FareChain();
        final passenger = fareOf('a', 400, -300);
        chain.startFare(passenger);
        chain.awardNearMiss();
        chain.update(0.5); // a frame passes; the meter still runs
        chain.awardNearMiss();
        return chain.completeFare(passenger, fareValue: 50).tipCoins;
      }

      expect(tipFor(), 2 * TipRule.thrillPassCoins);
      expect(tipFor(), tipFor(),
          reason: 'no draws, no clock: the same script pays the same tip');
    });

    test('the tip is capped per fare however many passes land', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);
      for (var i = 0; i < 5; i++) {
        chain.awardNearMiss();
      }

      final settlement = chain.completeFare(passenger, fareValue: 50);
      expect(5 * TipRule.thrillPassCoins, greaterThan(TipRule.maxTipCoins),
          reason: 'the fixture must out-earn the cap for the test to bite');
      expect(settlement.tipCoins, TipRule.maxTipCoins);
      expect(settlement.thrillPasses, 5,
          reason: 'every pass is still recorded, only the coins are capped');
    });

    test('a CLEAN CHAIN delivery at 2x or better tips', () {
      final chain = FareChain();
      final first = fareOf('first', 400, -300);
      chain.startFare(first);
      final firstSettlement = chain.completeFare(first, fareValue: 50);
      expect(firstSettlement.multiplier, 1);
      expect(firstSettlement.tipCoins, 0,
          reason: 'the first fare of a run rides at 1x — no chain to clean');

      final second = fareOf('second', 400, -300);
      chain.startFare(second);
      final secondSettlement = chain.completeFare(second, fareValue: 50);
      expect(secondSettlement.multiplier, 2);
      expect(secondSettlement.tipCoins, TipRule.cleanChainCoins);
    });

    test('a late delivery never tips the clean chain', () {
      final chain = FareChain();
      final first = fareOf('first', 400, -300);
      chain.startFare(first);
      chain.completeFare(first, fareValue: 50); // the chain rides at 2x

      final late = fareOf('late', 400, -300);
      chain.startFare(late);
      chain.update(FareChain.secondsForRide(700) + 5);
      final settlement = chain.completeFare(late, fareValue: 50);

      expect(settlement.outcome, FareOutcome.late);
      expect(settlement.tipCoins, 0,
          reason: 'a late ride is no clean chain, whatever it rode past');
    });

    test('the thrill tip and the clean chain share the one cap', () {
      final chain = FareChain();
      final first = fareOf('first', 400, -300);
      chain.startFare(first);
      chain.completeFare(first, fareValue: 50); // the chain rides at 2x

      final second = fareOf('second', 400, -300);
      chain.startFare(second);
      for (var i = 0; i < 3; i++) {
        chain.awardNearMiss(); // 3 x 4 = 12: already at the ceiling
      }
      final settlement = chain.completeFare(second, fareValue: 50);

      expect(3 * TipRule.thrillPassCoins + TipRule.cleanChainCoins,
          greaterThan(TipRule.maxTipCoins),
          reason: 'the fixture must exceed the cap through both events');
      expect(settlement.tipCoins, TipRule.maxTipCoins);
    });

    test('an expired rider keeps the thrill it earned while live and '
        'tips nothing more', () {
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);
      chain.awardNearMiss();
      expect(chain.timerFor(passenger)!.tipCoins, TipRule.thrillPassCoins);

      // The meter runs out; a later pass is no longer this ride's thrill.
      chain.update(FareChain.secondsForRide(700) + 5);
      chain.awardNearMiss();
      expect(chain.timerFor(passenger)!.tipCoins, TipRule.thrillPassCoins);
      expect(chain.thrillPasses, 1);

      final settlement = chain.completeFare(passenger, fareValue: 50);
      expect(settlement.outcome, FareOutcome.late);
      expect(settlement.tipCoins, TipRule.thrillPassCoins,
          reason: 'the thrill was real; the late chain adds no clean tip');
    });

    test('every live fare aboard rides the same thrill pass', () {
      final chain = FareChain();
      final first = fareOf('first', 400, -300);
      final second = fareOf('second', 400, -600);
      chain.startFare(first);
      chain.startFare(second);
      chain.awardNearMiss();

      final firstSettlement = chain.completeFare(first, fareValue: 50);
      expect(firstSettlement.tipCoins, TipRule.thrillPassCoins);

      final secondSettlement = chain.completeFare(second, fareValue: 50);
      expect(secondSettlement.tipCoins,
          TipRule.thrillPassCoins + TipRule.cleanChainCoins,
          reason: 'its own thrill pass, plus the clean chain it rode at 2x');
    });

    test('reset clears the thrill pass record with the rest', () {
      final chain = FareChain();
      chain.startFare(fareOf('a', 400, -300));
      chain.awardNearMiss();
      expect(chain.thrillPasses, 1);

      chain.reset();
      expect(chain.thrillPasses, 0);
      expect(chain.nearMisses, 0);
    });

    test('the tutorial ladder pays no tip (tipsEnabled: false)', () {
      // The ladder's authored payout is exactly max(score, reward), once
      // — its rungs teach their lessons without a second income — so the
      // level dropoff gates the tip off while the ride still accrues it.
      final chain = FareChain();
      final passenger = fareOf('a', 400, -300);
      chain.startFare(passenger);
      chain.awardNearMiss();

      final settlement = chain.completeFare(
        passenger,
        fareValue: 50,
        tipsEnabled: false,
      );
      expect(settlement.tipCoins, 0);
      expect(settlement.thrillPasses, 1,
          reason: 'the record of the pass survives; only the coins gate');
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

      // Level 1: one fare, (240, 400) → (315, -300) for 50 coins.
      final level = game.currentLevel;
      final pickup = level.pickupPoints.first;
      final dropoff = level.dropoffPoints.first;
      final rideDistance = (dropoff - pickup).length;

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
      // The completion panel's payout line and the wallet reconcile
      // (issue #284): the credited amount is exactly what the panel
      // names, never the pop's earlier claim.
      expect(game.lastCompletionPayout, 50);
      expect(gameState.totalCoins, game.lastCompletionPayout,
          reason: 'the visible payout is the credited payout, to the coin');
      // And the pop count pins *when* the claim plays (issue #284): the
      // kerb names its settlement, and the only coins in the air are the
      // completion volley's six — the frame that credited them. The old
      // dropoff popped three before the wallet moved, making nine here.
      // The delivery frame queues its adds; one tick mounts them.
      game.update(1 / 60);
      await drain();
      expect(game.world.children.whereType<FareSettlementPop>().length, 1,
          reason: 'the dropoff explains the settlement instead of popping '
              'coins the wallet has not received');
      expect(game.world.children.whereType<CoinPop>().length, 6,
          reason: 'six completion coins, no dropoff coins: the pops and '
              'the credit land on the same frame');
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
