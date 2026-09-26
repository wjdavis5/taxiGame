import 'dart:math';

import 'package:flame/components.dart';

import 'difficulty_curve.dart';

/// One procedurally generated fare: a pickup followed by a dropoff further
/// up the road.
class EndlessFare {
  const EndlessFare({
    required this.index,
    required this.pickup,
    required this.dropoff,
    required this.reward,
  });

  /// Position of this fare in the run's sequence (0-based).
  final int index;

  /// Sidewalk position where the passenger waits.
  final Vector2 pickup;

  /// Sidewalk position further up the road (smaller y) to deliver to.
  final Vector2 dropoff;

  /// Coins paid on delivery.
  final int reward;

  /// Distance the ride covers, in px.
  double get rideLength => pickup.y - dropoff.y;
}

/// The deterministic course of an endless run (issue #11).
///
/// Every fare is a pure function of (seed, index): fare *i* always lives in
/// slot *i*, a fixed [slotLength] band of road, with its geometry drawn from
/// a private RNG seeded by a hash of (seed, index). Nothing is consumed in
/// sequence, so the same seed reproduces the identical course no matter
/// what order fares are queried in — the property issue #19 (Daily Shift)
/// depends on.
///
/// Pure logic — no Flame state — so determinism is unit testable.
class EndlessCourse {
  EndlessCourse({required this.seed});

  /// The run seed. The same seed always yields the same course.
  final int seed;

  /// Height (px) of the road band each fare occupies. Fares never overlap
  /// because every position drawn for fare *i* stays inside its slot.
  static const double slotLength = 1400.0;

  // Sidewalk x positions (road spans 100..300; sidewalks 70..100 and
  // 300..330 — the same curbs the hand-made levels place passengers on).
  static const double leftCurbX = 85.0;
  static const double rightCurbX = 315.0;

  // Per-fare random ranges. The pickup sits [minPickupInset,
  // maxPickupInset] below the slot's bottom edge (travel order), then the
  // dropoff [minRideLength, maxRideLength] further up. The worst case must
  // fit the slot: maxPickupInset + maxRideLength + rideGrowthMax
  // + slotTailMargin <= slotLength.
  static const double minPickupInset = 150.0;
  static const double maxPickupInset = 275.0;
  static const double minRideLength = 550.0;
  static const double maxRideLength = 850.0;
  static const double rideGrowthMax = 125.0;
  static const double slotTailMargin = 150.0;

  /// Generates fare [index]. Deterministic and order-independent.
  EndlessFare fare(int index) {
    final random = Random(_slotSeed(index));

    // Draw in a fixed order — reordering these lines changes the course.
    final pickupOnLeft = random.nextBool();
    final dropoffOnLeft = random.nextBool();
    final pickupInset = minPickupInset +
        random.nextDouble() * (maxPickupInset - minPickupInset);
    var rideLength = minRideLength +
        random.nextDouble() * (maxRideLength - minRideLength);
    final rewardBonus = random.nextInt(16);

    // Rides stretch a little as the run deepens, in step with the traffic
    // ramp, but never far enough to spill into the next slot.
    rideLength += DifficultyCurve.rampFractionFor(index * slotLength) *
        rideGrowthMax;

    final pickupY = -(index * slotLength) - pickupInset;
    final dropoffY = pickupY - rideLength;

    // ~40–70 coins a fare: in band with the 50-coin level rewards the
    // economy was tuned around.
    final reward = 20 + (rideLength / 30).round() + rewardBonus;

    return EndlessFare(
      index: index,
      pickup: Vector2(pickupOnLeft ? leftCurbX : rightCurbX, pickupY),
      dropoff: Vector2(dropoffOnLeft ? leftCurbX : rightCurbX, dropoffY),
      reward: reward,
    );
  }

  /// SplitMix64-style mixing so (seed, index) pairs land on independent,
  /// uniformly spread RNG seeds. Dart VM ints are 64-bit and wrap on
  /// overflow, so this is fully deterministic.
  int _mix64(int x) {
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EB;
    return x ^ (x >> 31);
  }

  int _slotSeed(int index) =>
      _mix64(seed * 0x9E3779B97F4A7C15 + index) & 0x7FFFFFFFFFFFFFFF;
}
