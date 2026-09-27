import 'dart:math';

import 'package:flame/components.dart';

import '../../models/fare_type.dart';
import 'difficulty_curve.dart';
import 'run_environment.dart';
import 'world_origin.dart';

/// One procedurally generated fare: a pickup followed by a dropoff further
/// up the road.
class EndlessFare {
  const EndlessFare({
    required this.index,
    required this.pickup,
    required this.dropoff,
    required this.reward,
    required this.pickupDistance,
    required this.dropoffDistance,
    this.fareType = FareType.standard,
  });

  /// Position of this fare in the run's sequence (0-based).
  final int index;

  /// Sidewalk position where the passenger waits (world frame — see
  /// [WorldOrigin]).
  final Vector2 pickup;

  /// Sidewalk position further up the road (smaller y) to deliver to.
  final Vector2 dropoff;

  /// Coins paid on delivery.
  final int reward;

  /// What kind of fare this is (issue #25) — the deal the player weighs at
  /// the kerb. Standard fares are the everyday ride; the other kinds bend
  /// the geometry, the payout, or the clock (see [FareType]).
  final FareType fareType;

  /// True distance into the run of the pickup and the dropoff, in px —
  /// frame-independent, unlike [pickup]/[dropoff], whose world y folds
  /// back toward the origin every [WorldOrigin.period] px (issue #30).
  final double pickupDistance;
  final double dropoffDistance;

  /// Distance the ride covers, in px. The dropoff waits further up the
  /// road, so its true distance is the larger one.
  double get rideLength => dropoffDistance - pickupDistance;
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
  EndlessCourse({required this.seed, this.environment});

  /// The run seed. The same seed always yields the same course.
  final int seed;

  /// The run's living world (issue #24). When set, passengers wait on the
  /// kerbs the road *actually* has at their stop — wide avenues push the
  /// kerb out, narrow streets pull it in — instead of the standard road's
  /// fixed curbs below. Null keeps the classic fixed curbs, which is what
  /// the hand-made levels and every pre-#24 course mean.
  final RunEnvironment? environment;

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

  /// The long-haul fare's ride (issue #25): the longest ride the slot can
  /// legally hold — the pickup at the slot's earliest inset and the
  /// dropoff exactly at the slot's tail margin. Sits past the worst
  /// standard ride (maxRideLength + rideGrowthMax), which is the point: a
  /// long-haul is visibly, uncomfortably further.
  static const double longHaulRideLength =
      slotLength - slotTailMargin - minPickupInset;

  /// The awkward fare's ride (issue #25): the shortest crossing the course
  /// draws, so the forced lane change has to happen now. One px above
  /// [minRideLength] — not exactly on it — because the world's [Vector2]s
  /// store float32, and deep in a run the storage rounding can read a
  /// floor-pinned ride a few thousandths *under* the floor, which would
  /// quietly break the course's "every ride is at least [minRideLength]"
  /// invariant. One px is invisible; the invariant stays exact.
  static const double awkwardRideLength = minRideLength + 1.0;

  // --- Second chances (issue #28) -----------------------------------------

  /// How far ahead of a passed dropoff the relocated one waits, at least
  /// and at most. A rideable distance: long enough to read as a real ride
  /// and to land clearly beyond the kerb the player just missed, short
  /// enough that a driver who reacts promptly can still beat the meter.
  static const double minRelocationRide = 450.0;
  static const double maxRelocationRide = 750.0;

  /// Where fare [index]'s dropoff waits after the player has driven past
  /// it (issue #28): a fresh kerb spot further up the road. [attempt] 0 is
  /// the first pass; each further attempt chains another
  /// [minRelocationRide]..[maxRelocationRide] px past the previous spot,
  /// so the passenger always waits ahead, no matter how many times the
  /// taxi blows past.
  ///
  /// True distance of fare [index]'s relocated dropoff after [attempt] +
  /// 1 chained hops — the road term of what [relocatedDropoff] places,
  /// readable without pinning a world frame (issue #30: world y folds,
  /// the road does not). Each attempt's draw order matches
  /// [relocatedDropoff]'s: the extra ride is the first draw of the
  /// attempt's salted stream, the kerb side the second.
  double relocatedDropoffDistance(int index, {int attempt = 0}) {
    var distance = fare(index).dropoffDistance;
    for (var a = 0; a <= attempt; a++) {
      final random = Random(_slotSeed(index) ^ (0x51EC0DE * (a + 1)));
      distance += minRelocationRide +
          random.nextDouble() * (maxRelocationRide - minRelocationRide);
    }
    return distance;
  }

  /// Pure in (seed, index, attempt) — never in where the taxi happens to
  /// be — so every run of the same course relocates identically, and a
  /// ghost race relocates with you. The draws come from a salted stream
  /// per attempt, never from [fare]'s: relocating a fare can never rewrite
  /// the road a seed already dealt. The chain runs in true distance (issue
  /// #30) — relocations can cross a world fold, where raw world y would
  /// jump the spot a whole [WorldOrigin.period] away. [worldShift] is the
  /// live fold, with the same window rule [fare] applies.
  Vector2 relocatedDropoff(
    int index, {
    int attempt = 0,
    double? worldShift,
  }) {
    var distance = relocatedDropoffDistance(index, attempt: attempt);
    var x = fare(index).dropoff.x;
    for (var a = 0; a <= attempt; a++) {
      final random = Random(_slotSeed(index) ^ (0x51EC0DE * (a + 1)));
      random.nextDouble(); // the extra ride, already folded into [distance]
      final onLeft = random.nextBool();
      // The kerb the road actually has at the new stop (issue #24), the
      // same rule [fare] itself places passengers by.
      x = onLeft
          ? (environment?.leftCurbXAt(distance) ?? leftCurbX)
          : (environment?.rightCurbXAt(distance) ?? rightCurbX);
    }
    final shift =
        max(WorldOrigin.shiftForDistance(distance), worldShift ?? 0.0);
    return Vector2(x, shift - distance);
  }

  /// Generates fare [index]. Deterministic and order-independent.
  ///
  /// [worldShift] is the live world fold (issue #30) when the fare is
  /// being placed into a running world. A slot just *behind* a fresh fold
  /// boundary canonically lives in the previous window — without the live
  /// shift it would be placed a whole period away from the road it
  /// belongs to. With it, such a slot lands just below the start line of
  /// the live frame, exactly where that stretch of road is. Null (the
  /// default) keeps the pure canonical mapping, which is what the
  /// determinism tests and any out-of-run query want.
  EndlessFare fare(int index, {double? worldShift}) {
    final random = Random(_slotSeed(index));

    // Draw in a fixed order — reordering these lines changes the course.
    final pickupOnLeft = random.nextBool();
    var dropoffOnLeft = random.nextBool();
    var pickupInset = minPickupInset +
        random.nextDouble() * (maxPickupInset - minPickupInset);
    var rideLength = minRideLength +
        random.nextDouble() * (maxRideLength - minRideLength);
    final rewardBonus = random.nextInt(16);

    // Rides stretch a little as the run deepens, in step with the traffic
    // ramp, but never far enough to spill into the next slot.
    rideLength += DifficultyCurve.rampFractionFor(index * slotLength) *
        rideGrowthMax;

    // The fare's kind (issue #25), drawn *after* every geometry draw so
    // the seven-in-ten standard slots keep byte-identical geometry to the
    // pre-variety courses — adding the types never rewrites the road a
    // seed already knew, it only decorates some of its slots.
    final fareType = FareType.draw(random);
    switch (fareType) {
      case FareType.longHaul:
        // The distant dropoff: earliest possible pickup, longest possible
        // ride — the whole slot, tail margin respected.
        pickupInset = minPickupInset;
        rideLength = longHaulRideLength;
      case FareType.awkward:
        // The far-side crossing: the dropoff waits on the opposite kerb,
        // and the ride is the shortest the course draws so the lane
        // change has to happen now, under the clock.
        dropoffOnLeft = !pickupOnLeft;
        rideLength = awkwardRideLength;
      case FareType.vip:
      case FareType.standard:
        break; // Standard geometry; the VIP's deal is payout and clock.
    }

    // True distances into the run (issue #30): fares are placed at the
    // canonical world y for their distance — or the live fold's frame
    // when the slot sits behind it — so a fare generated past a world
    // fold lands in the frame the camera is actually in. Pickup and
    // dropoff share one slot, and a slot never straddles a fold boundary
    // (the period is a whole number of slots), so one shift covers both.
    final pickupDistance = index * slotLength + pickupInset;
    final dropoffDistance = pickupDistance + rideLength;
    final shift =
        max(WorldOrigin.shiftForDistance(pickupDistance), worldShift ?? 0.0);
    final pickupY = shift - pickupDistance;
    final dropoffY = shift - dropoffDistance;

    // Kerbs follow the road (issue #24): the passenger waits just past
    // the road edge that exists at *their* stop, so a fare is always
    // reachable from the clamp the taxi is actually held by. Each stop
    // samples its own distance — pickup and dropoff can sit on different
    // streets. Without an environment this is the standard road's fixed
    // curbs, as always.
    final pickupLeft = environment?.leftCurbXAt(pickupDistance) ?? leftCurbX;
    final pickupRight =
        environment?.rightCurbXAt(pickupDistance) ?? rightCurbX;
    final dropoffLeft = environment?.leftCurbXAt(dropoffDistance) ?? leftCurbX;
    final dropoffRight =
        environment?.rightCurbXAt(dropoffDistance) ?? rightCurbX;

    // ~40–70 coins a standard fare: in band with the 50-coin level
    // rewards the economy was tuned around. Special kinds scale that base
    // by their [FareType.rewardMultiplier] — the VIP's tripled fare is
    // what the tight clock is bought with.
    final baseReward = 20 + (rideLength / 30).round() + rewardBonus;
    final reward = (baseReward * fareType.rewardMultiplier).round();

    return EndlessFare(
      index: index,
      pickup: Vector2(pickupOnLeft ? pickupLeft : pickupRight, pickupY),
      dropoff: Vector2(dropoffOnLeft ? dropoffLeft : dropoffRight, dropoffY),
      reward: reward,
      fareType: fareType,
      pickupDistance: pickupDistance,
      dropoffDistance: dropoffDistance,
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
