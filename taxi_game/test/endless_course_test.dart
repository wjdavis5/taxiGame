import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/endless_course.dart';

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
      for (var i = 1; i <= 5000; i++) {
        final fare = course.fare(i);

        expect(fare.pickup.y, lessThan(previous.pickup.y),
            reason: 'fare $i pickup above fare ${i - 1}');
        expect(fare.dropoff.y, lessThan(fare.pickup.y),
            reason: 'fare $i dropoff above its pickup');
        expect(fare.rideLength, greaterThanOrEqualTo(EndlessCourse.minRideLength),
            reason: 'fare $i ride length');
        expect(
          fare.rideLength,
          lessThanOrEqualTo(EndlessCourse.maxRideLength +
              EndlessCourse.rideGrowthMax +
              0.001),
          reason: 'fare $i ride length',
        );

        previous = fare;
      }
    });

    test('fares never overlap slot boundaries', () {
      final course = EndlessCourse(seed: 1234);

      for (var i = 0; i < 500; i++) {
        final fare = course.fare(i);
        final slotBottom = -(i * EndlessCourse.slotLength);
        final slotTop = -((i + 1) * EndlessCourse.slotLength);

        // The pickup lives in slot i...
        expect(fare.pickup.y, lessThanOrEqualTo(slotBottom));
        expect(fare.pickup.y, greaterThan(slotTop));
        // ...and the dropoff leaves the slot's tail margin free, so the
        // next fare's pickup can never crowd this dropoff.
        expect(
          fare.dropoff.y,
          greaterThanOrEqualTo(
              slotTop + EndlessCourse.slotTailMargin - 0.001),
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
        final reward = course.fare(i).reward;
        expect(reward, greaterThanOrEqualTo(20));
        expect(reward, lessThanOrEqualTo(70));
      }
    });

    test('negative and huge seeds work too', () {
      final a = EndlessCourse(seed: -987654321);
      final b = EndlessCourse(seed: -987654321);
      expectFaresEqual(a.fare(1000), b.fare(1000), 'fare 1000');

      final huge = EndlessCourse(seed: 0x7FFFFFFFFFFFFFFF);
      expect(huge.fare(0).reward, greaterThanOrEqualTo(20));
    });
  });
}

void expectFaresEqual(EndlessFare a, EndlessFare b, String label) {
  expect(a.index, b.index, reason: label);
  expect(a.pickup.x, closeTo(b.pickup.x, 1e-9), reason: '$label pickup x');
  expect(a.pickup.y, closeTo(b.pickup.y, 1e-9), reason: '$label pickup y');
  expect(a.dropoff.x, closeTo(b.dropoff.x, 1e-9), reason: '$label dropoff x');
  expect(a.dropoff.y, closeTo(b.dropoff.y, 1e-9), reason: '$label dropoff y');
  expect(a.reward, b.reward, reason: label);
}
