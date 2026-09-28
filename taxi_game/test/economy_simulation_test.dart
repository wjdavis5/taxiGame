// The tuning table is the deliverable here: prints, not a logging
// framework.
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/run_length_simulator.dart';
import 'package:taxi_game/game/systems/shift_earnings.dart';

/// The endless-economy instrument behind the garage re-ladder (issue #34).
///
/// The game has no analytics, so "what does a shift earn" is answered the
/// way "how long does a shift last" is (see `run_length_simulation_test`):
/// by simulating the same 101-seed batch with the shipped simulator and
/// pricing each shift under the live payout rules ([ShiftEarnings] —
/// per-fare coins, chain multipliers, brink bank). The table it prints is
/// the number the garage ladder is priced against.
///
/// Run with the expanded reporter to see the table:
///
/// ```
/// flutter test test/economy_simulation_test.dart --reporter expanded
/// ```
///
/// The three profiles are uncalibrated skill stand-ins, not measured
/// players (nothing phones home; there is no history to calibrate
/// against). The median profile is the simulator's shipped defaults — the
/// driver the difficulty curve was tuned against; the other two widen
/// reaction lag, misjudgement, and planning horizon around it. Their only
/// job is to bracket the wallet: a first-session player earns like
/// "new", a competent one like "median" or better. The batch the current
/// ladder was priced from is quoted in the re-ladder commit message;
/// re-run this when payouts change.
void main() {
  // Same seed batch as the run-length test, so the two instruments
  // measure identical shifts.
  const firstSeed = 1000;
  const runCount = 101;

  final medians = <String, int>{};

  test('coins per shift, by skill level (the tuning table)', () {
    print('Endless coins per shift — $runCount seeds '
        '(seeds $firstSeed..${firstSeed + runCount - 1}), starter cab\n');

    for (final profile in const [
      ('new', reactionInterval: 0.40, misjudgeRate: 0.10, lookahead: 1.00),
      ('median', reactionInterval: 0.25, misjudgeRate: 0.03, lookahead: 1.25),
      ('good', reactionInterval: 0.16, misjudgeRate: 0.005, lookahead: 1.60),
    ]) {
      final label = profile.$1;
      final runs = <SimulatedRun>[];
      final earnings = <ShiftEarnings>[];
      var totalKm = 0.0;
      for (var seed = firstSeed; seed < firstSeed + runCount; seed++) {
        final run = RunLengthSimulator(
          seed: seed,
          reactionInterval: profile.reactionInterval,
          misjudgeRate: profile.misjudgeRate,
          lookaheadSeconds: profile.lookahead,
        ).run();
        runs.add(run);
        earnings.add(ShiftEarnings.forRun(run));
        totalKm += run.distancePx / 10000;
      }

      List<int> sorted(int Function(ShiftEarnings) of) =>
          earnings.map(of).toList()..sort();
      int pct(List<int> values, double p) =>
          values[((values.length - 1) * p).round()];

      final totals = sorted((e) => e.totalCoins);
      final floors = sorted((e) => e.wreckCoins);
      final banks = sorted((e) => e.bankedScore);
      final fares = sorted((e) => e.faresDelivered);
      final chains = sorted((e) => e.bestChain);

      final median = pct(totals, 0.5);
      medians[label] = median;

      print('$label driver '
          '(reaction ${profile.reactionInterval}s, '
          'misjudge ${profile.misjudgeRate}, '
          'lookahead ${profile.lookahead}s)');
      print('  median shift       : ${(totalKm / runCount).toStringAsFixed(1)} km, '
          '${pct(fares, 0.5)} fares delivered, best chain x${pct(chains, 0.5)}');
      print('  fares-only floor   : '
          'p25 ${pct(floors, 0.25)}  median ${pct(floors, 0.5)}  '
          'p75 ${pct(floors, 0.75)}');
      print('  brink-banked score : '
          'p25 ${pct(banks, 0.25)}  median ${pct(banks, 0.5)}  '
          'p75 ${pct(banks, 0.75)}');
      print('  shift total        : '
          'p25 ${pct(totals, 0.25)}  median $median  '
          'p75 ${pct(totals, 0.75)}');
      print('');
    }

    print('Shift total = fares-only floor + brink-banked chain score (1:1). '
        'Perfect-foresight banking is the ceiling; a real player\'s wallet '
        'lands between the floor and the ceiling.');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a first-session driver out-earns nothing: new < median', () {
    // Only the bottom of the ladder is pinned as an ordering. Median vs
    // good is deliberately not: banked scores are high-variance (the
    // chain is quadratic in the fares between breaks), and the good
    // driver trades chain score for survival — deeper runs ride tighter
    // fare budgets — so their medians can legitimately cross. The batch
    // that priced the current ladder measured median 8368 vs good 8077
    // with heavily overlapping spreads; the wallet grows with skill,
    // just not monotonically in these stand-ins.
    expect(
      medians,
      isNotEmpty,
      reason: 'the table above must run first',
    );
    expect(medians['new']!, lessThan(medians['median']!),
        reason: 'a first-session driver must out-earn nothing');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
