import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/run_length_simulator.dart';
import 'package:taxi_game/game/systems/shift_earnings.dart';

/// The payout wiring of the earnings harness (issue #34): every rule
/// [ShiftEarnings] applies must be the live game's rule, so each one is
/// pinned here against a hand-built shift whose deliveries, crashes, and
/// meters are known. The course is read in the tests so the expected
/// chain arithmetic rides the real rewards, never copies of them.
void main() {
  const seed = 4242;
  final course = EndlessCourse(seed: seed);

  SimulatedRun runWith({
    required double distancePx,
    List<double> crashDistancesPx = const [],
    required List<FareStop> fareStops,
  }) =>
      SimulatedRun(
        seed: seed,
        distancePx: distancePx,
        drivenSeconds: 1,
        crashDistancesPx: crashDistancesPx,
        survived: crashDistancesPx.isEmpty,
        fareStops: fareStops,
      );

  FareStop stop(double distancePx, {double cyclePx = 1000, double cycleSeconds = 1.0}) =>
      FareStop(
          distancePx: distancePx, cyclePx: cyclePx, cycleSeconds: cycleSeconds);

  test('every on-time delivery pays reward x multiplier, and the '
      'default push steps the chain once more', () {
    // Three flawless, instant cycles. The chain rides 1x, 3x, 5x — each
    // delivery steps once, and the dropoff prompt's default (push) steps
    // again, except after the bank itself.
    final earnings = ShiftEarnings.forRun(runWith(
      distancePx: 5000,
      fareStops: [
        stop(1000, cycleSeconds: 1),
        stop(2400, cycleSeconds: 1),
        stop(3800, cycleSeconds: 1),
      ],
    ));

    expect(earnings.faresDelivered, 3);
    final rewards = [
      course.fare(0).reward,
      course.fare(1).reward,
      course.fare(2).reward,
    ];
    final expectedScore = rewards[0] * 1 + rewards[1] * 3 + rewards[2] * 5;
    expect(earnings.faresCoins, rewards.fold(0, (a, b) => a + b));
    expect(earnings.bankedScore, expectedScore);
    expect(earnings.bestChain, 6, reason: '1x, then +2 per fare');
    expect(earnings.totalCoins, earnings.faresCoins + expectedScore);
  });

  test('a crash breaks the chain: the next fare scores at 1x again', () {
    final earnings = ShiftEarnings.forRun(runWith(
      distancePx: 5000,
      crashDistancesPx: [2000],
      fareStops: [
        stop(1000, cycleSeconds: 1),
        stop(3000, cycleSeconds: 1),
        stop(4400, cycleSeconds: 1),
      ],
    ));

    // Fare 0 rides the fresh 1x. The crash lands before fare 1, so fare
    // 1 scores at 1x, and the chain rebuilds 1x, 3x from there.
    final expectedScore = course.fare(0).reward * 1 +
        course.fare(1).reward * 1 +
        course.fare(2).reward * 3;
    expect(earnings.bankedScore, expectedScore);
    expect(earnings.chainBreaks, 1, reason: 'the crash');
  });

  test('a late delivery still pays the fare, at 1x, and breaks the chain',
      () {
    // Every cycle far over its meter: nothing scores on the chain.
    final earnings = ShiftEarnings.forRun(runWith(
      distancePx: 5000,
      fareStops: [
        stop(1000, cycleSeconds: 999),
        stop(2400, cycleSeconds: 999),
        stop(3800, cycleSeconds: 999),
      ],
    ));

    final rewards = [
      course.fare(0).reward,
      course.fare(1).reward,
      course.fare(2).reward,
    ];
    expect(earnings.faresCoins, rewards.fold(0, (a, b) => a + b),
        reason: 'a late fare is still a delivered fare');
    expect(earnings.bankedScore, earnings.faresCoins,
        reason: 'every fare scored at 1x');
    expect(earnings.chainBreaks, 3);
    expect(earnings.bestChain, 2,
        reason: 'only the default push ever lifts it, and only mid-shift');
  });

  test('the shift never out-earns the fares it actually met', () {
    // Stops recorded past the shift's end distance are empty slots: the
    // course dealt no fare there, so none is priced.
    final earnings = ShiftEarnings.forRun(runWith(
      distancePx: 1500, // fare 0 only: fare 1's pickup is past the end
      fareStops: [
        stop(1000, cycleSeconds: 1),
        stop(1450, cycleSeconds: 1),
      ],
    ));

    expect(earnings.faresDelivered, 1);
    expect(earnings.faresCoins, course.fare(0).reward);
  });

  test('a shift that ends before any fare records no earnings', () {
    final earnings = ShiftEarnings.forRun(runWith(
      distancePx: 100,
      fareStops: [],
    ));

    expect(earnings.faresDelivered, 0);
    expect(earnings.totalCoins, 0);
    expect(earnings.wreckCoins, 0);
  });
}
