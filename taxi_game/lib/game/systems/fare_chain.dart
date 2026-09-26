import 'dart:math' as math;

import '../../models/passenger_data.dart';

/// How a delivered fare settled against its countdown (issue #12).
enum FareSettlement {
  /// Delivered inside the fare's time window: the chain extends.
  onTime,

  /// Delivered after the window closed (or with no window at all): the
  /// chain stays broken at 1x.
  late,
}

/// One passenger's countdown. Starts at pickup and ticks every frame the
/// passenger is aboard (issue #12).
class FareTimer {
  FareTimer({required this.passengerId, required this.totalSeconds})
      : remainingSeconds = totalSeconds;

  /// Identity of the passenger this countdown belongs to.
  final String passengerId;

  /// The budget the fare started with, in seconds.
  final double totalSeconds;

  /// Seconds left on the clock; floored at zero, never negative.
  double remainingSeconds;

  bool get isExpired => remainingSeconds <= 0.0;

  /// Fraction (0..1) of the budget still left — raw material for a bar.
  double get fractionRemaining =>
      totalSeconds <= 0 ? 0.0 : (remainingSeconds / totalSeconds).clamp(0, 1);
}

/// The fare chain — the game's scoring backbone (issue #12).
///
/// Every passenger picked up carries a countdown sized to their ride.
/// Delivering inside the window banks `fare value x current multiplier` and
/// steps the multiplier up; letting a countdown run out breaks the chain
/// back down to 1x. The score is run-local and at risk until the player
/// banks it at a dropoff (issue #13): banking converts it to coins and ends
/// the shift; crashing or losing the shift forfeits everything unbanked.
///
/// Several passengers can be aboard at once (a level can let the player
/// stack pickups), so each carries their own countdown and the chain breaks
/// if any of them runs out. The HUD shows the most urgent one.
///
/// Pure logic — no Flame state — so every rule is unit testable, matching
/// [DifficultyCurve] and [EndlessCourse].
class FareChain {
  // --- Tuning -------------------------------------------------------------
  // Issue #12 leaves the exact numbers to playtesting; these first-pass
  // values encode the shape (distance-scaled budget, linear multiplier
  // step) and live here so a retune is one place. The budget assumes the
  // player averages [paceForBudget] px/s — roughly half the starter cab's
  // top speed — plus a flat loading allowance, so early fares are forgiving
  // and deep-run traffic (which slows the average) tightens them naturally.

  /// Flat allowance on every fare, regardless of distance.
  static const double baseFareSeconds = 6.0;

  /// Extra budget per px of ride distance (1 s per 75 px of travel).
  static const double secondsPerPx = 1.0 / 75.0;

  /// Floor and ceiling on the computed budget, so no fare is unwinnable or
  /// free no matter how the generator draws its geometry.
  static const double minFareSeconds = 8.0;
  static const double maxFareSeconds = 25.0;

  /// Multiplier added per on-time delivery. 1 = a linear 1x, 2x, 3x...
  /// curve; raise to make long chains accelerate.
  static const int multiplierStep = 1;

  /// Extra multiplier granted for choosing to push on at a dropoff
  /// (issue #13) — the payout for refusing the bank. Stacks with
  /// [multiplierStep], so a pushed chain climbs a step a delivery faster
  /// than a banked-at-the-first-chance one ever sees.
  static const int pushBonusStep = 1;

  int score = 0;

  /// The multiplier the next delivery is scored at. Starts at 1x; grows by
  /// [multiplierStep] per on-time delivery and [pushBonusStep] per
  /// push-on; any expiry resets it to 1x.
  int multiplier = 1;

  /// The highest the multiplier reached this run (issue #15) — the "best
  /// chain" line on the run summary. A break lowers [multiplier] but never
  /// this: the record of what the chain once was is the whole point.
  int bestMultiplier = 1;

  final Map<String, FareTimer> _timers = {};

  /// The time budget for a ride of [rideDistance] px.
  static double secondsForRide(double rideDistance) {
    final raw = baseFareSeconds + rideDistance * secondsPerPx;
    return raw.clamp(minFareSeconds, maxFareSeconds).toDouble();
  }

  /// True while at least one passenger with a running countdown is aboard.
  bool get isCarryingFare => _timers.isNotEmpty;

  /// How many countdowns are live right now.
  int get activeFareCount => _timers.length;

  /// The countdown for [passenger], or null when they are not aboard.
  FareTimer? timerFor(PassengerData passenger) => _timers[passenger.id];

  /// The countdown that will run out first — the one the HUD shows. Null
  /// when no passenger is aboard.
  FareTimer? get mostUrgentTimer {
    FareTimer? urgent;
    for (final timer in _timers.values) {
      if (urgent == null || timer.remainingSeconds < urgent.remainingSeconds) {
        urgent = timer;
      }
    }
    return urgent;
  }

  /// Starts [passenger]'s countdown, sized to their ride.
  void startFare(PassengerData passenger) {
    final rideDistance =
        (passenger.dropoffLocation - passenger.pickupLocation).length;
    _timers[passenger.id] = FareTimer(
      passengerId: passenger.id,
      totalSeconds: secondsForRide(rideDistance),
    );
  }

  /// Settles [passenger]'s fare at [fareValue] coins. On-time deliveries
  /// score `fareValue x multiplier` and step the multiplier up; late ones
  /// score `fareValue x 1` (the expiry in [update] already reset it) and
  /// leave the chain broken. Returns how it settled so callers can react.
  FareSettlement completeFare(
    PassengerData passenger, {
    required int fareValue,
  }) {
    final timer = _timers.remove(passenger.id);
    final onTime = timer != null && !timer.isExpired;

    score += fareValue * multiplier;
    multiplier = onTime ? multiplier + multiplierStep : 1;
    _trackBest();

    return onTime ? FareSettlement.onTime : FareSettlement.late;
  }

  /// The reward for pushing on at a dropoff (issue #13): the multiplier
  /// the next fare rides at steps up once more. Applied whether the player
  /// chose to push or let the choice window run out — riding on is the
  /// default, and it must cost the same either way.
  void applyPushBonus() {
    multiplier += pushBonusStep;
    _trackBest();
  }

  /// Folds a multiplier increase into the run's best-chain record.
  void _trackBest() {
    if (multiplier > bestMultiplier) bestMultiplier = multiplier;
  }

  /// Breaks the chain back to 1x without touching the score or any live
  /// countdown — the price a crash charges (issue #14). The score itself
  /// survives the crash, still unbanked and at risk; only the chain
  /// progress is lost.
  void breakChain() {
    multiplier = 1;
  }

  /// Ticks every live countdown. Any that runs out breaks the chain back to
  /// 1x immediately, so the HUD shows the break the moment it happens.
  void update(double dt) {
    if (_timers.isEmpty) return;

    var expired = false;
    for (final timer in _timers.values) {
      timer.remainingSeconds =
          math.max(0.0, timer.remainingSeconds - dt);
      if (timer.isExpired) expired = true;
    }
    if (expired) multiplier = 1;
  }

  /// Clears the chain: score, multiplier, best chain, and every live
  /// countdown. Called whenever a run or level (re)starts.
  void reset() {
    score = 0;
    multiplier = 1;
    bestMultiplier = 1;
    _timers.clear();
  }
}
