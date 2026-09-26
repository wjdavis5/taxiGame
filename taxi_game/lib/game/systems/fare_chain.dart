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
/// back down to 1x. Score is run-local: it resets with every new run or
/// level (issue #13 adds the bank-or-push decision that makes it permanent).
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

  int score = 0;

  /// The multiplier the next delivery is scored at. Starts at 1x; grows by
  /// [multiplierStep] per on-time delivery; any expiry resets it to 1x.
  int multiplier = 1;

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

    return onTime ? FareSettlement.onTime : FareSettlement.late;
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

  /// Clears the chain: score, multiplier, and every live countdown. Called
  /// whenever a run or level (re)starts.
  void reset() {
    score = 0;
    multiplier = 1;
    _timers.clear();
  }
}
