import 'dart:math' as math;

import '../../models/fare_type.dart';
import '../../models/passenger_data.dart';

/// How a delivered fare settled against its countdown (issue #12).
enum FareOutcome {
  /// Delivered inside the fare's time window: the chain extends.
  onTime,

  /// Delivered after the window closed (or with no window at all): the
  /// chain stays broken at 1x.
  late,
}

/// What one fare settled at (issues #12, #270): the outcome plus the
/// numbers behind it, so the dropoff feedback can name the whole deal —
/// what the fare was worth, the multiplier it scored at, any chain bonus
/// its kind paid, what it awarded, the at-risk total it left standing,
/// and the tip the ride itself earned (issue #276).
class FareSettlement {
  const FareSettlement({
    required this.outcome,
    required this.fareValue,
    required this.multiplier,
    required this.chainStepBonus,
    required this.scoreAwarded,
    required this.scoreTotal,
    this.tipCoins = 0,
    this.thrillPasses = 0,
  });

  final FareOutcome outcome;

  /// The fare's coin value before the chain prices it.
  final int fareValue;

  /// The multiplier this fare actually scored at: the live chain for an
  /// on-time delivery, a flat 1x for a late one.
  final int multiplier;

  /// Extra chain steps the fare kind granted on time (a long-haul's
  /// payout, issue #25); zero when the fare was late or standard.
  final int chainStepBonus;

  /// The chain score this fare added: [fareValue] x [multiplier].
  final int scoreAwarded;

  /// The chain score standing after this fare — the at-risk total.
  final int scoreTotal;

  /// Coins this ride tipped at the kerb (issue #276), per [TipRule] —
  /// wallet money, never chain score, so the mastery economy is
  /// untouched. Zero for a ride no named skill event thrilled.
  final int tipCoins;

  /// How many of the fare's close calls landed while it rode — the
  /// THRILL PASS events behind [tipCoins].
  final int thrillPasses;

  bool get isLate => outcome == FareOutcome.late;
}

/// The passenger tip (issue #276): what a rider pays for a ride that
/// thrilled them, in the game's existing skill vocabulary. Two named
/// events earn it, both already ruled on elsewhere in the game:
///
///  - **THRILL PASS** — a qualifying close call (issue #23's ruling)
///    cleared while this fare is aboard with a live meter. The passenger
///    feels the shave the chain already pays for.
///  - **CLEAN CHAIN** — an on-time delivery at 2x or better: the fare
///    rode a live chain, so the smooth fast ride itself tips.
///
/// The tip is deterministic — a flat coin value per event, no draws —
/// and capped per fare, so a thrill spree can never outpay the fare
/// economy it sits beside. Late deliveries never tip the chain event,
/// but a fare keeps whatever thrill passes it earned while its meter
/// was live: the thrill was real; the chain break is a separate debt.
class TipRule {
  TipRule._();

  /// Coins one THRILL PASS adds to the fare's pending tip.
  static const int thrillPassCoins = 4;

  /// Coins one CLEAN CHAIN delivery adds to the tip.
  static const int cleanChainCoins = 4;

  /// Hard ceiling on one fare's tip, however many events landed: about
  /// a fifth of a standard fare, so tips season the wallet rather than
  /// replace the fare economy the garage ladder is priced against.
  static const int maxTipCoins = 12;

  /// [coins] under the per-fare ceiling.
  static int capped(int coins) =>
      coins > maxTipCoins ? maxTipCoins : coins;
}

/// One passenger's countdown. Starts at pickup and ticks every frame the
/// passenger is aboard (issue #12). It also carries the tip the ride has
/// earned so far (issue #276) — accrued per THRILL PASS while the meter
/// is live, paid and capped at the dropoff.
class FareTimer {
  FareTimer({required this.passengerId, required this.totalSeconds})
      : remainingSeconds = totalSeconds;

  /// Identity of the passenger this countdown belongs to.
  final String passengerId;

  /// The budget the fare started with, in seconds.
  final double totalSeconds;

  /// Seconds left on the clock; floored at zero, never negative.
  double remainingSeconds;

  /// Tip coins this ride has accrued (issue #276), uncapped until
  /// [FareChain.completeFare] pays it through [TipRule.maxTipCoins].
  int tipCoins = 0;

  /// THRILL PASS close calls this ride's meter was live for.
  int thrillPasses = 0;

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
/// if any of them runs out. The HUD shows the most urgent still-live one —
/// an expired rider surfaces only when nothing live is left (issue #126).
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
  //
  // Issue #18 makes that deep-run tightening explicit: budgets now scale
  // with a timer pressure in 0..1 (endless runs pass
  // [DifficultyCurve.farePressureFor] at pickup; level mode passes nothing
  // and keeps the original, teaching-friendly budgets). The pressure-1
  // anchors below are the deep-run values the run simulator validated as
  // still winnable at the worst ride the course can draw.

  /// Flat allowance on every fare, regardless of distance.
  static const double baseFareSeconds = 6.0;

  /// Extra budget per px of ride distance (1 s per 75 px of travel).
  static const double secondsPerPx = 1.0 / 75.0;

  /// Floor and ceiling on the computed budget, so no fare is unwinnable or
  /// free no matter how the generator draws its geometry.
  static const double minFareSeconds = 8.0;
  static const double maxFareSeconds = 25.0;

  // Pressure-1 (fully tightened) anchors. Each budget term lerps from its
  // pressure-0 value above to its pressure-1 value here.
  static const double _tightBaseFareSeconds = 4.0;
  static const double _tightSecondsPerPx = 1.0 / 85.0;
  static const double _tightMinFareSeconds = 7.0;
  static const double _tightMaxFareSeconds = 18.0;

  /// Multiplier added per on-time delivery. 1 = a linear 1x, 2x, 3x...
  /// curve; raise to make long chains accelerate.
  static const int multiplierStep = 1;

  /// Extra multiplier granted for choosing to push on at a dropoff
  /// (issue #13) — the payout for refusing the bank. Stacks with
  /// [multiplierStep], so a pushed chain climbs a step a delivery faster
  /// than a banked-at-the-first-chance one ever sees.
  static const int pushBonusStep = 1;

  /// Base points for one close call (issue #23): a pass cleared within a
  /// car-third of traffic at speed. Deliberately well under a typical
  /// fare's payout — close calls are the seasoning on the delivery
  /// chain, never a replacement for it — and they only get interesting
  /// when the multiplier is live, which is the point: shaving traffic
  /// pays best exactly when keeping the chain alive matters most.
  static const int nearMissScore = 15;

  int score = 0;

  /// The multiplier the next delivery is scored at. Starts at 1x; grows by
  /// [multiplierStep] per on-time delivery and [pushBonusStep] per
  /// push-on; any expiry resets it to 1x.
  int multiplier = 1;

  /// The highest the multiplier reached this run (issue #15) — the "best
  /// chain" line on the run summary. A break lowers [multiplier] but never
  /// this: the record of what the chain once was is the whole point.
  int bestMultiplier = 1;

  /// Close calls cleared this run (issue #23). Recorded per run like the
  /// score, and surfaced on the run summary — the count is the raw
  /// material for the issue's kill criterion, judging from the on-device
  /// history whether near-misses read as skill or as luck.
  int nearMisses = 0;

  /// Close calls that landed while a live fare was aboard (issue #276) —
  /// the THRILL PASS events behind the run's tips, named on the run
  /// summary beside the tip coins they paid.
  int thrillPasses = 0;

  final Map<String, FareTimer> _timers = {};

  /// The time budget for a ride of [rideDistance] px under fare timer
  /// [pressure] (0..1, from [DifficultyCurve.farePressureFor]). Pressure 0 —
  /// the default, and all of level mode — gives the original issue #12
  /// budgets; pressure 1 gives the fully tightened deep-run budget. The
  /// floor still clamps, so the tightest budget never dips under what the
  /// worst ride needs at a conservative pace: no fare is unwinnable at any
  /// distance.
  ///
  /// [fareType] (issue #25) scales every term by the kind's
  /// [FareType.timeScale]: a VIP runs the whole budget — flat allowance,
  /// per-px rate, floor, and ceiling — at 60%, which is what "much tighter
  /// timer" means here. The scale stays inside the course's ride domain:
  /// at the realistic deep-traffic cruise (~110 px/s) even the tightest
  /// VIP budget covers its ride, and the fares that trade that slack for
  /// triple coins are exactly the ones the player can see and decline.
  static double secondsForRide(
    double rideDistance, {
    double pressure = 0.0,
    FareType fareType = FareType.standard,
  }) {
    final p = pressure.clamp(0.0, 1.0).toDouble();
    final scale = fareType.timeScale;
    final base =
        (baseFareSeconds + (_tightBaseFareSeconds - baseFareSeconds) * p) *
            scale;
    final rate =
        (secondsPerPx + (_tightSecondsPerPx - secondsPerPx) * p) * scale;
    final floor =
        (minFareSeconds + (_tightMinFareSeconds - minFareSeconds) * p) * scale;
    final ceiling =
        (maxFareSeconds + (_tightMaxFareSeconds - maxFareSeconds) * p) * scale;
    final raw = base + rideDistance * rate;
    return raw.clamp(floor, ceiling).toDouble();
  }

  /// True while at least one passenger with a running countdown is aboard.
  bool get isCarryingFare => _timers.isNotEmpty;

  /// How many countdowns are live right now.
  int get activeFareCount => _timers.length;

  /// The countdown for [passenger], or null when they are not aboard.
  FareTimer? timerFor(PassengerData passenger) => _timers[passenger.id];

  /// The live countdown that will run out first — the one the HUD shows.
  /// Null when no passenger is aboard.
  ///
  /// Expired riders are invisible to the pick until nothing live is left
  /// (issue #126): a meter floored at zero always wins a plain min, so
  /// once any passenger rode late the badge parked on LATE and every
  /// other countdown aboard ticked to zero unseen — its expiry, the one
  /// event the badge exists to warn about, landing with no warning at
  /// all. A late rider is still returned, but only when every timer
  /// aboard is expired, keeping the lone-late LATE read; and that LATE
  /// no longer claims the chain is broken *now* — #120 breaks it once at
  /// the crossing, so a delivery since may have rebuilt it while the
  /// late rider sat on.
  FareTimer? get mostUrgentTimer {
    FareTimer? urgent;
    FareTimer? expired;
    for (final timer in _timers.values) {
      if (timer.isExpired) {
        expired ??= timer;
      } else if (urgent == null ||
          timer.remainingSeconds < urgent.remainingSeconds) {
        urgent = timer;
      }
    }
    return urgent ?? expired;
  }

  /// Starts [passenger]'s countdown, sized to their ride and to their fare
  /// kind (issue #25) — a VIP boards onto a much tighter meter than the
  /// same ride would get as a standard fare. Endless runs pass the fare
  /// timer pressure at the pickup point (issue #18); level mode omits it
  /// and keeps the original budgets.
  void startFare(PassengerData passenger, {double pressure = 0.0}) {
    final rideDistance =
        (passenger.dropoffLocation - passenger.pickupLocation).length;
    _timers[passenger.id] = FareTimer(
      passengerId: passenger.id,
      totalSeconds: secondsForRide(
        rideDistance,
        pressure: pressure,
        fareType: passenger.fareType,
      ),
    );
  }

  /// Settles [passenger]'s fare at [fareValue] coins. On-time deliveries
  /// score `fareValue x multiplier` and step the multiplier up — by
  /// [multiplierStep] for an ordinary fare, and by
  /// [FareType.chainStepBonus] extra for the kinds that boost the chain
  /// (issue #25): a delivered long-haul jumps the multiplier three steps
  /// at once, which is its payout. Late ones score `fareValue x 1` and
  /// leave the chain broken — a flat rate that holds even when the chain
  /// rebuilt while this rider sat expired aboard (issue #120: the break
  /// now fires once, at the crossing, so the multiplier standing at a
  /// late dropoff is whatever the deliveries since then earned).
  ///
  /// The tip (issue #276) is priced here too: the fare's accrued THRILL
  /// PASS coins plus the CLEAN CHAIN award for an on-time delivery at 2x
  /// or better, capped by [TipRule.maxTipCoins]. Coins, never score —
  /// the chain's at-risk total is untouched. [tipsEnabled] gates it at
  /// the call site: an endless shift pays the tip, while the tutorial
  /// ladder's authored payout — exactly max(score, reward), once —
  /// stays untouched, so its rungs teach their lessons without a
  /// second income.
  /// Returns the full [FareSettlement] — outcome and numbers — so callers
  /// can react and say what happened (issue #270).
  FareSettlement completeFare(
    PassengerData passenger, {
    required int fareValue,
    bool tipsEnabled = true,
  }) {
    final timer = _timers.remove(passenger.id);
    final onTime = timer != null && !timer.isExpired;

    final appliedMultiplier = onTime ? multiplier : 1;
    final chainStepBonus = onTime ? passenger.fareType.chainStepBonus : 0;
    final awarded = fareValue * appliedMultiplier;
    score += awarded;
    multiplier = onTime
        ? multiplier + multiplierStep + chainStepBonus
        : 1;
    _trackBest();

    final pendingTip = timer?.tipCoins ?? 0;
    final cleanChain = onTime && appliedMultiplier >= 2;
    final tip = tipsEnabled
        ? TipRule.capped(
            pendingTip + (cleanChain ? TipRule.cleanChainCoins : 0),
          )
        : 0;

    return FareSettlement(
      outcome: onTime ? FareOutcome.onTime : FareOutcome.late,
      fareValue: fareValue,
      multiplier: appliedMultiplier,
      chainStepBonus: chainStepBonus,
      scoreAwarded: awarded,
      scoreTotal: score,
      tipCoins: tip,
      thrillPasses: timer?.thrillPasses ?? 0,
    );
  }

  /// The reward for pushing on at a dropoff (issue #13): the multiplier
  /// the next fare rides at steps up once more. Applied whether the player
  /// chose to push or let the choice window run out — riding on is the
  /// default, and it must cost the same either way.
  void applyPushBonus() {
    multiplier += pushBonusStep;
    _trackBest();
  }

  /// Awards one close call (issue #23). Near-misses ride the existing
  /// chain rather than a second parallel score: the payout is
  /// [nearMissScore] × the live [multiplier], into the same run-local,
  /// at-risk-until-banked [score] every fare pays into — so a close call
  /// banked at a dropoff is worth exactly what it would have paid the
  /// moment it happened, and one made on a broken chain pays 1x until
  /// deliveries rebuild the multiplier.
  ///
  /// The multiplier itself is untouched: only deliveries and pushes step
  /// it (issues #12, #13), so the chain economy issue #18 tuned is
  /// undisturbed — defensive players build the same chains they always
  /// did, and shaving traffic monetises risk the chain already prices.
  ///
  /// The pass is also a THRILL PASS for every fare aboard with a live
  /// meter (issue #276): each accrues [TipRule.thrillPassCoins] on its
  /// own countdown, paid at that fare's dropoff. An expired rider
  /// accrues nothing — the thrill is the live ride's — and a pass with
  /// nobody live aboard still pays the chain score and counts only as a
  /// near-miss.
  ///
  /// Returns the points awarded, so the on-road feedback can name them.
  int awardNearMiss() {
    nearMisses++;
    final points = nearMissScore * multiplier;
    score += points;
    var thrilled = false;
    for (final timer in _timers.values) {
      if (timer.isExpired) continue;
      timer.tipCoins += TipRule.thrillPassCoins;
      timer.thrillPasses++;
      thrilled = true;
    }
    if (thrilled) thrillPasses++;
    return points;
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
  /// 1x — once, on the frame the countdown crosses zero (issue #120), so
  /// the HUD shows the break the moment it happens. An expired passenger
  /// stays aboard until [completeFare] settles them late, and treating
  /// "expired" as a state re-broke the chain on every frame they rode:
  /// an on-time delivery or push bonus earned while they sat in the cab
  /// held for exactly one tick before being quietly reset to 1x. Only
  /// the crossing is the chain-breaking event; riding expired is not.
  ///
  /// Returns whether this tick's crossing broke the chain, so the caller
  /// can give the loss its own cue (issue #273) — the multiplier is
  /// already 1x by the time it reads it.
  bool update(double dt) {
    if (_timers.isEmpty) return false;

    var crossedZero = false;
    for (final timer in _timers.values) {
      final wasExpired = timer.isExpired;
      timer.remainingSeconds =
          math.max(0.0, timer.remainingSeconds - dt);
      if (!wasExpired && timer.isExpired) crossedZero = true;
    }
    if (crossedZero) multiplier = 1;
    return crossedZero;
  }

  /// Clears the chain: score, multiplier, best chain, close calls,
  /// thrill passes, and every live countdown. Called whenever a run or
  /// level (re)starts.
  void reset() {
    score = 0;
    multiplier = 1;
    bestMultiplier = 1;
    nearMisses = 0;
    thrillPasses = 0;
    _timers.clear();
  }
}
