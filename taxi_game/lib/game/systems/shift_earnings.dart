import 'endless_course.dart';
import 'fare_chain.dart';
import 'difficulty_curve.dart';
import 'run_environment.dart';
import 'run_length_simulator.dart';

/// What one simulated shift would have paid under the live endless payout
/// rules (issues #11-#14, #25) — the economy instrument behind the garage
/// re-ladder (issue #34).
///
/// The game ships with no analytics, so "what does a shift earn" is
/// answered the same way "how long does a shift last" is (issue #18): by
/// composing the pure pieces the live game runs and simulating many seeds.
/// The payout rules applied here, straight from [TaxiGame] and [FareChain]:
///
///  - every delivered fare pays its coin reward into the wallet on the
///    spot, and `reward x multiplier` into the at-risk chain score;
///  - an on-time delivery steps the multiplier up ([FareChain.multiplierStep],
///    plus a fare kind's [FareType.chainStepBonus]), a late one breaks the
///    chain back to 1x;
///  - every dropoff arms the bank-or-push prompt whose default is push
///    ([BankDecision.pushed] — issue #13), so a shift that keeps driving
///    collects [FareChain.pushBonusStep] on every fare but the last;
///  - a crash breaks the chain ([FareChain.breakChain] — issue #14) without
///    touching the score;
///  - banking converts the chain score to coins 1:1 and ends the shift.
///
/// **How the simulated shift is read:** the course for the run's own seed
/// deals one fare per slot, so ledger stop *k* is the delivery of course
/// fare *k* — the driver always pulls over and never misses or declines
/// one. Two deliberate biases pull against each other and are why both
/// bounds below are reported:
///
///  - *optimistic:* no fare is ever declined (a careful player refuses
///    VIPs on a busy screen) and near-miss points are never scored;
///  - *conservative:* the meter is read over the whole stop-to-stop cycle
///    — kerb approach, boarding, and merge included — not just the ride,
///    so a fare only counts as on time when the entire cycle beat it.
///
/// **The bank:** a simulation only ever dies — it never chooses. A real
/// player banks at a dropoff, so the shift's banked payout is modelled at
/// the brink: the chain score at the last stop before the shift's end
/// (the third crash, or the harness cap), everything after forfeit. That
/// is perfect foresight — the most any one shift could pay — and
/// [faresCoins] is the floor of a shift that never banked at all. A real
/// player's wallet lands between the two; the ladder is priced off the
/// midpoint, with the spread stated in the tool output.
class ShiftEarnings {
  ShiftEarnings._({
    required this.faresDelivered,
    required this.faresCoins,
    required this.bankedScore,
    required this.chainBreaks,
    required this.bestChain,
  });

  /// Fares delivered before the shift ended.
  final int faresDelivered;

  /// Coins paid on the spot, per delivery. Earned however the shift ends.
  final int faresCoins;

  /// The chain score at the brink bank — what banking 1:1 would have paid
  /// on top of [faresCoins]. Zero only for a shift whose every delivery
  /// preceded its first recorded crash.
  final int bankedScore;

  /// Times the chain broke: late deliveries and crashes. The shape of the
  /// shift's risk, for the tuning table.
  final int chainBreaks;

  /// The highest multiplier the chain reached — the best chain the shift
  /// once held.
  final int bestChain;

  /// The shift's ceiling: fares plus the brink bank. What a player with
  /// perfect timing takes from this seed.
  int get totalCoins => faresCoins + bankedScore;

  /// The shift's floor: fares only, if the score was never banked.
  int get wreckCoins => faresCoins;

  /// Prices the fare stops of [run] against the course [run]'s own seed
  /// deals, under the world that seed draws.
  static ShiftEarnings forRun(SimulatedRun run) {
    final course = EndlessCourse(seed: run.seed, environment: null);
    final env = RunEnvironment(seed: run.seed);

    // Fares the shift could have met: one per slot, up to where the shift
    // ended. A stop past the last dealt fare stopped for an empty slot.
    var faresMet = 0;
    while (true) {
      final fare = course.fare(faresMet);
      if (fare.pickupDistance > run.distancePx) break;
      faresMet++;
    }

    var multiplier = 1;
    var score = 0;
    var faresCoins = 0;
    var chainBreaks = 0;
    var bestChain = 1;
    var crashIndex = 0;

    var priced = 0;
    for (final stop in run.fareStops) {
      if (priced >= faresMet) break; // an empty slot: nothing to deliver

      // Crashes landed before this boarding broke the chain already.
      while (crashIndex < run.crashDistancesPx.length &&
          run.crashDistancesPx[crashIndex] < stop.distancePx) {
        if (multiplier > 1) chainBreaks++;
        multiplier = 1; // FareChain.breakChain
        crashIndex++;
      }

      final fare = course.fare(priced);
      final pressure = DifficultyCurve.farePressureFor(
        fare.pickupDistance,
        environmentModifier: env.difficultyModifierAt(fare.pickupDistance),
      );
      final budget = FareChain.secondsForRide(
        fare.rideLength,
        pressure: pressure,
        fareType: fare.fareType,
      );
      final onTime = stop.cycleSeconds <= budget;

      // FareChain.completeFare, verbatim.
      if (onTime) {
        score += fare.reward * multiplier;
        multiplier += FareChain.multiplierStep + fare.fareType.chainStepBonus;
      } else {
        score += fare.reward; // a late fare still pays, at 1x
        multiplier = 1;
        chainBreaks++;
      }
      faresCoins += fare.reward;
      if (multiplier > bestChain) bestChain = multiplier;
      priced++;

      // The bank-or-push prompt's default resolution (issue #13): every
      // dropoff the player does not bank at pushes, stepping the chain
      // once more. The brink bank is the one dropoff that ends the
      // shift instead — the last stop the ledger recorded, whether the
      // shift ran on past the last dealt fare or died just after it.
      if (priced < run.fareStops.length) {
        multiplier += FareChain.pushBonusStep;
        if (multiplier > bestChain) bestChain = multiplier;
      }
    }

    return ShiftEarnings._(
      faresDelivered: priced,
      faresCoins: faresCoins,
      bankedScore: score,
      chainBreaks: chainBreaks,
      bestChain: bestChain,
    );
  }
}
