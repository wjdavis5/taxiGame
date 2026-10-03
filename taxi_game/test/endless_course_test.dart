import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/run_environment.dart';
import 'package:taxi_game/models/fare_type.dart';

/// The seeded course generator (issue #11): the same seed must reproduce
/// the same course exactly, whatever order fares are queried in.
void main() {
  group('EndlessCourse', () {
    test('same seed reproduces the same fares, in any query order', () {
      final a = EndlessCourse(seed: 42);
      final b = EndlessCourse(seed: 42);

      const count = 200;
      // Course b is queried back to front; the fares must still match
      // course a's index for index.
      final bQueriedBackwards = [
        for (var i = count - 1; i >= 0; i--) b.fare(i),
      ];
      for (var i = 0; i < count; i++) {
        expectFaresEqual(a.fare(i), bQueriedBackwards[count - 1 - i],
            'fare $i');
      }

      // And a third pass on the same instance is stable too.
      for (var i = 0; i < count; i++) {
        expectFaresEqual(a.fare(i), a.fare(i), 'fare $i (re-query)');
      }
    });

    test('different seeds produce different courses', () {
      final a = EndlessCourse(seed: 1);
      final b = EndlessCourse(seed: 2);

      var differing = 0;
      for (var i = 0; i < 20; i++) {
        final fa = a.fare(i);
        final fb = b.fare(i);
        if (fa.pickup != fb.pickup || fa.dropoff != fb.dropoff) differing++;
      }
      expect(differing, greaterThan(0), reason: 'seeds 1 and 2 diverge');
    });

    test('fares advance up the road forever, spaced like real rides', () {
      final course = EndlessCourse(seed: 7);
      EndlessFare previous = course.fare(0);

      // The far, far end of a 30-minute run must still generate cleanly.
      // Advance is judged in true distance (issue #30): world y folds
      // back toward the origin every period, the road does not.
      for (var i = 1; i <= 5000; i++) {
        final fare = course.fare(i);

        expect(fare.pickupDistance, greaterThan(previous.pickupDistance),
            reason: 'fare $i pickup above fare ${i - 1}');
        expect(fare.dropoff.y, lessThan(fare.pickup.y),
            reason: 'fare $i dropoff above its pickup');
        // Long-hauls take the whole slot (issue #25); every other kind
        // rides inside the standard band. A slot hosting a junction may
        // bend a long-haul (issue #189): the pickup moves clear of the
        // band and the ride shortens to the room the slot has left.
        // (closeTo, not equals: the world stores float32, and deep slots
        // read the ride a few thousandths off its true length.)
        if (fare.fareType == FareType.longHaul) {
          if (slotHostsJunction(i)) {
            expect(
              fare.rideLength,
              greaterThanOrEqualTo(EndlessCourse.minRideLength - 0.01),
              reason: 'fare $i long-haul ride stays rideable (junction slot)',
            );
            expect(
              fare.rideLength,
              lessThanOrEqualTo(EndlessCourse.longHaulRideLength + 0.01),
              reason: 'fare $i long-haul ride never exceeds its slot '
                  '(junction slot)',
            );
          } else {
            expect(fare.rideLength,
                closeTo(EndlessCourse.longHaulRideLength, 0.01),
                reason: 'fare $i long-haul ride length');
          }
        } else {
          expect(fare.rideLength,
              greaterThanOrEqualTo(EndlessCourse.minRideLength),
              reason: 'fare $i ride length');
          // A junction slot can also *stretch* a ride (issue #189): a
          // dropoff pushed to the band's far edge rides past the drawn
          // ceiling, though never past the room the slot itself has —
          // the earliest pickup to the last legal band edge.
          final rideCeiling = slotHostsJunction(i)
              ? EndlessCourse.longHaulRideLength
              : EndlessCourse.maxRideLength + EndlessCourse.rideGrowthMax;
          expect(
            fare.rideLength,
            lessThanOrEqualTo(rideCeiling + 0.001),
            reason: 'fare $i ride length',
          );
        }

        previous = fare;
      }
    });

    test('fares never overlap slot boundaries', () {
      final course = EndlessCourse(seed: 1234);

      // Slot packing is a fact about the road, not a world frame (issue
      // #30), so it is judged in true distance.
      for (var i = 0; i < 500; i++) {
        final fare = course.fare(i);
        final slotBottom = i * EndlessCourse.slotLength;
        final slotTop = (i + 1) * EndlessCourse.slotLength;

        // The pickup lives in slot i...
        expect(fare.pickupDistance, greaterThanOrEqualTo(slotBottom));
        expect(fare.pickupDistance, lessThan(slotTop));
        // ...and the dropoff leaves the slot's tail margin free, so the
        // next fare's pickup can never crowd this dropoff.
        expect(
          fare.dropoffDistance,
          lessThanOrEqualTo(slotTop - EndlessCourse.slotTailMargin + 0.001),
          reason: 'fare $i dropoff clears the slot tail',
        );
      }
    });

    test('passengers wait on the sidewalks the levels use', () {
      final course = EndlessCourse(seed: 99);

      for (var i = 0; i < 300; i++) {
        final fare = course.fare(i);
        const curbs = [EndlessCourse.leftCurbX, EndlessCourse.rightCurbX];
        expect(curbs, contains(fare.pickup.x), reason: 'fare $i pickup x');
        expect(curbs, contains(fare.dropoff.x), reason: 'fare $i dropoff x');
      }
    });

    test('rewards stay in band with the level economy', () {
      final course = EndlessCourse(seed: 5);

      for (var i = 0; i < 300; i++) {
        final fare = course.fare(i);
        expectRewardInBand(fare, 'fare $i');
      }
    });

    test('negative and huge seeds work too', () {
      final a = EndlessCourse(seed: -987654321);
      final b = EndlessCourse(seed: -987654321);
      expectFaresEqual(a.fare(1000), b.fare(1000), 'fare 1000');

      final huge = EndlessCourse(seed: 0x7FFFFFFFFFFFFFFF);
      expectRewardInBand(huge.fare(0), 'fare 0 (huge seed)');
    });
  });

  group('relocated dropoffs (issue #28)', () {
    test('relocation is a pure function of (seed, index, attempt)', () {
      final a = EndlessCourse(seed: 42);
      final b = EndlessCourse(seed: 42);

      for (var i = 0; i < 50; i++) {
        for (var attempt = 0; attempt < 3; attempt++) {
          final pa = a.relocatedDropoff(i, attempt: attempt);
          final pb = b.relocatedDropoff(i, attempt: attempt);
          expect(pa.x, closeTo(pb.x, 1e-9),
              reason: 'fare $i attempt $attempt x');
          expect(pa.y, closeTo(pb.y, 1e-9),
              reason: 'fare $i attempt $attempt y');
        }
      }
    });

    test('the relocated spot waits a rideable distance ahead, on a curb', () {
      final course = EndlessCourse(seed: 42);
      const curbs = [EndlessCourse.leftCurbX, EndlessCourse.rightCurbX];

      // Measured in true distance (issue #30): the hop can cross a world
      // fold, where the world-y reading would jump by a whole period.
      for (var i = 0; i < 200; i++) {
        final fare = course.fare(i);
        final spotDistance = course.relocatedDropoffDistance(i);

        expect(spotDistance, greaterThan(fare.dropoffDistance),
            reason: 'fare $i relocates ahead of the passed kerb');
        final extraRide = spotDistance - fare.dropoffDistance;
        expect(extraRide,
            greaterThanOrEqualTo(EndlessCourse.minRelocationRide - 0.001),
            reason: 'fare $i relocation ride lower bound');
        // A hop that lands in a junction band runs on to the band's far
        // edge (issue #189), so it may overshoot the ordinary hop ceiling
        // by up to the cleared zone's full width — but only when a zone
        // actually lay across the hop.
        expect(
          extraRide,
          lessThanOrEqualTo(
            EndlessCourse.maxRelocationRide +
                (junctionZoneOverlaps(fare.dropoffDistance, spotDistance)
                    ? 2 *
                        (RunEnvironment.intersectionHalfBand +
                            EndlessCourse.junctionStopClearance)
                    : 0.0) +
                0.001,
          ),
          reason: 'fare $i relocation ride upper bound',
        );
        final spot = course.relocatedDropoff(i);
        expect(curbs, contains(spot.x), reason: 'fare $i relocation curb x');
      }
    });

    test('relocation follows the kerbs the environment draws (issue #24)', () {
      final env = RunEnvironment(seed: 4242);
      final course = EndlessCourse(seed: 4242, environment: env);

      for (var i = 0; i < 100; i++) {
        final spot = course.relocatedDropoff(i);
        final spotDistance = course.relocatedDropoffDistance(i);
        expect(
          spot.x,
          anyOf(
            closeTo(env.leftCurbXAt(spotDistance), 0.01),
            closeTo(env.rightCurbXAt(spotDistance), 0.01),
          ),
          reason: 'fare $i relocation sits on a real kerb at its distance',
        );
      }
    });

    test('each attempt chains further up the road', () {
      final course = EndlessCourse(seed: 7);

      // Chaining is judged in true distance (issue #30): a hop across a
      // world fold would read backwards in world y.
      for (var i = 0; i < 50; i++) {
        final first = course.relocatedDropoffDistance(i, attempt: 0);
        final second = course.relocatedDropoffDistance(i, attempt: 1);

        expect(second, greaterThan(first),
            reason: 'fare $i second relocation above the first');
        expect(second - first,
            greaterThanOrEqualTo(EndlessCourse.minRelocationRide - 0.001),
            reason: 'fare $i second relocation is a rideable hop, so the '
                'taxi can never be past it the moment it lands');
      }
    });

    test('relocating never perturbs the course draw itself', () {
      final a = EndlessCourse(seed: 99);
      final b = EndlessCourse(seed: 99);

      for (var i = 0; i < 20; i++) {
        a.relocatedDropoff(i, attempt: 2);
      }
      for (var i = 0; i < 20; i++) {
        expectFaresEqual(a.fare(i), b.fare(i), 'fare $i');
      }
    });
  });

  group('junctions are not addresses (issue #189)', () {
    // The band grid is a fact about the road, not the seed, so one
    // environment answers the band question for every course below.
    final env = RunEnvironment(seed: 0);

    test('no stop of any kind waits inside a junction band', () {
      // The issue's repro territory: fares past the 45,000 px junction,
      // across hundreds of seeds. Every pickup, dropoff, and chained
      // relocation attempt must sit clear of every junction band — and
      // the nudges must not trade that for a broken ride: the pickup
      // never drops under its inset floor (it only ever moves forward),
      // and the ride never goes unrideable or spills past its slot.
      for (var seed = 0; seed < 250; seed++) {
        final course = EndlessCourse(seed: seed);
        for (var i = 32; i <= 96; i++) {
          final fare = course.fare(i);
          final slotTop = (i + 1) * EndlessCourse.slotLength;

          expect(env.isIntersectionAt(fare.pickupDistance), isFalse,
              reason: 'seed $seed fare $i pickup at '
                  '${fare.pickupDistance} waits in a junction');
          expect(env.isIntersectionAt(fare.dropoffDistance), isFalse,
              reason: 'seed $seed fare $i dropoff at '
                  '${fare.dropoffDistance} waits in a junction');
          expect(
            fare.pickupDistance,
            greaterThanOrEqualTo(
                i * EndlessCourse.slotLength + EndlessCourse.minPickupInset),
            reason: 'seed $seed fare $i pickup keeps its inset floor',
          );
          expect(fare.rideLength,
              greaterThanOrEqualTo(EndlessCourse.minRideLength - 0.001),
              reason: 'seed $seed fare $i ride stays rideable');
          expect(
            fare.dropoffDistance,
            lessThanOrEqualTo(
                slotTop - EndlessCourse.slotTailMargin + 0.001),
            reason: 'seed $seed fare $i dropoff clears the slot tail',
          );

          // Relocations wander outside the slot arithmetic that places
          // first stops, so they get their own sweep — every attempt.
          for (var attempt = 0; attempt <= 2; attempt++) {
            final spot = course.relocatedDropoffDistance(i, attempt: attempt);
            expect(env.isIntersectionAt(spot), isFalse,
                reason: 'seed $seed fare $i relocation $attempt at $spot '
                    'waits in a junction');
          }
        }
      }
    });

    test("fare #33's pickup clears the 45,000 px junction on every seed", () {
      // The issue's named repro: fare #33 (index 32) spans true distance
      // 32*1400 + inset[150, 275] = [44,950, 45,075] — the *entire*
      // drawn inset range sits inside the 45,000 junction's band
      // [44,840, 45,160], so before the nudge every seed on earth
      // planted that passenger mid-cross-street. The nudge deals every
      // seed the same forward kerb: the band's far edge plus the stop
      // clearance.
      const nudgedTo = 45000.0 +
          RunEnvironment.intersectionHalfBand +
          EndlessCourse.junctionStopClearance;
      for (var seed = 0; seed < 250; seed++) {
        final fare = EndlessCourse(seed: seed).fare(32);
        expect(fare.pickupDistance, closeTo(nudgedTo, 0.001),
            reason: 'seed $seed fare #33 pickup sits at the junction\'s '
                'far edge');
        expect(env.isIntersectionAt(fare.pickupDistance), isFalse,
            reason: 'seed $seed fare #33 waits clear of the junction');
      }
    });
  });
}

/// The reward must sit in its fare kind's band: the distance-scaled base
/// (20 coins + 1 per 30 px + a 0-15 slot bonus) times the kind's
/// [FareType.rewardMultiplier], with rounding slop on each edge. The slot
/// bonus scales with the multiplier, so it is added before scaling.
void expectRewardInBand(EndlessFare fare, String label) {
  final base = 20 + (fare.rideLength / 30).round();
  final mult = fare.fareType.rewardMultiplier;
  expect(fare.reward, greaterThanOrEqualTo((base * mult).round() - 1),
      reason: '$label reward lower bound');
  expect(fare.reward,
      lessThanOrEqualTo(((base + 15) * mult).round() + 1),
      reason: '$label reward upper bound (incl. slot bonus)');
}

void expectFaresEqual(EndlessFare a, EndlessFare b, String label) {
  expect(a.index, b.index, reason: label);
  expect(a.pickup.x, closeTo(b.pickup.x, 1e-9), reason: '$label pickup x');
  expect(a.pickup.y, closeTo(b.pickup.y, 1e-9), reason: '$label pickup y');
  expect(a.dropoff.x, closeTo(b.dropoff.x, 1e-9), reason: '$label dropoff x');
  expect(a.dropoff.y, closeTo(b.dropoff.y, 1e-9), reason: '$label dropoff y');
  expect(a.reward, b.reward, reason: label);
  expect(a.fareType, b.fareType, reason: '$label fare type');
}

/// Whether any junction's stop-keeping zone (band widened by the course's
/// stop clearance) overlaps the road interval (from, to] — i.e. whether a
/// distance-based stop, hop, or draw living anywhere in that interval
/// could have been bent by the junction nudge (issue #189).
bool junctionZoneOverlaps(double from, double to) {
  const reach = RunEnvironment.intersectionHalfBand +
      EndlessCourse.junctionStopClearance;
  const spacing = RunEnvironment.intersectionSpacing;
  final first = math.max(1, (from / spacing).floor());
  final last = (to / spacing).ceil();
  for (var k = first; k <= last; k++) {
    final center = k * spacing;
    if (center + reach > from && center - reach < to) return true;
  }
  return false;
}

/// Whether slot [index] hosts (or borders) a junction's stop-keeping
/// zone — the slots whose fares the nudge may legitimately bend, and the
/// only slots whose exact-geometry pins are relaxed below.
bool slotHostsJunction(int index) => junctionZoneOverlaps(
      index * EndlessCourse.slotLength,
      (index + 1) * EndlessCourse.slotLength,
    );
