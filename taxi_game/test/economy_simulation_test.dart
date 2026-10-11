// The tuning table is the deliverable here: prints, not a logging
// framework.
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/fare_chain.dart';
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
/// The distance line reports both the batch mean and the true median
/// (with the median driven time): the mean is pulled by both tails —
/// early wrecks below, the safety-capped survivors above — so the median
/// is what a typical shift looks like.
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
  final shiftStats = <String,
      ({double meanKm, double medianKm, double medianDrivenMinutes})>{};
  final profileRuns = <String, List<SimulatedRun>>{};
  final tableLines = <String>[];

  test('coins per shift, by skill level (the tuning table)', () {
    void emit(String line) {
      print(line);
      tableLines.add(line);
    }

    emit('Endless coins per shift — $runCount seeds '
        '(seeds $firstSeed..${firstSeed + runCount - 1}), starter cab\n');

    for (final profile in const [
      ('new', reactionInterval: 0.40, misjudgeRate: 0.10, lookahead: 1.00),
      ('median', reactionInterval: 0.25, misjudgeRate: 0.03, lookahead: 1.25),
      ('good', reactionInterval: 0.16, misjudgeRate: 0.005, lookahead: 1.60),
    ]) {
      final label = profile.$1;
      final runs = <SimulatedRun>[];
      final earnings = <ShiftEarnings>[];
      for (var seed = firstSeed; seed < firstSeed + runCount; seed++) {
        final run = RunLengthSimulator(
          seed: seed,
          reactionInterval: profile.reactionInterval,
          misjudgeRate: profile.misjudgeRate,
          lookaheadSeconds: profile.lookahead,
        ).run();
        runs.add(run);
        earnings.add(ShiftEarnings.forRun(run));
      }

      final estimate = RunLengthEstimate.compute(runs);
      final meanKm = runs.fold(0.0, (sum, run) => sum + run.distancePx) /
          runs.length /
          10000;
      final medianKm = estimate.medianDistancePx / 10000;
      final medianDrivenMinutes = estimate.medianDrivenSeconds / 60;

      List<int> sorted(int Function(ShiftEarnings) of) =>
          earnings.map(of).toList()..sort();
      int pct(List<int> values, double p) =>
          values[((values.length - 1) * p).round()];

      final totals = sorted((e) => e.totalCoins);
      final floors = sorted((e) => e.wreckCoins);
      final banks = sorted((e) => e.bankedScore);
      final fares = sorted((e) => e.faresDelivered);
      final chains = sorted((e) => e.bestChain);
      final tips = sorted((e) => e.tipsCoins);

      final median = pct(totals, 0.5);
      medians[label] = median;
      profileRuns[label] = runs;
      shiftStats[label] = (
        meanKm: meanKm,
        medianKm: medianKm,
        medianDrivenMinutes: medianDrivenMinutes,
      );

      emit('$label driver '
          '(reaction ${profile.reactionInterval}s, '
          'misjudge ${profile.misjudgeRate}, '
          'lookahead ${profile.lookahead}s)');
      emit('  median shift       : ${medianKm.toStringAsFixed(1)} km, '
          '${medianDrivenMinutes.toStringAsFixed(1)} min driven, '
          '${pct(fares, 0.5)} fares delivered, best chain x${pct(chains, 0.5)}');
      emit('  mean shift         : ${meanKm.toStringAsFixed(1)} km');
      emit('  fares-only floor   : '
          'p25 ${pct(floors, 0.25)}  median ${pct(floors, 0.5)}  '
          'p75 ${pct(floors, 0.75)}');
      emit('  ride tips          : '
          'p25 ${pct(tips, 0.25)}  median ${pct(tips, 0.5)}  '
          'p75 ${pct(tips, 0.75)}  '
          '(capped at ${TipRule.maxTipCoins} per fare)');
      emit('  brink-banked score : '
          'p25 ${pct(banks, 0.25)}  median ${pct(banks, 0.5)}  '
          'p75 ${pct(banks, 0.75)}');
      emit('  shift total        : '
          'p25 ${pct(totals, 0.25)}  median $median  '
          'p75 ${pct(totals, 0.75)}');
      emit('');
    }

    emit('Shift total = fares + ride tips + brink-banked chain score (1:1). '
        'Perfect-foresight banking is the ceiling; a real player\'s wallet '
        'lands between the floor and the ceiling.');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('the table reports a labelled mean and true medians per profile', () {
    expect(shiftStats.keys, containsAll(['new', 'median', 'good']));
    expect(profileRuns.keys, containsAll(['new', 'median', 'good']));

    // The reported values must equal an independent recomputation from
    // the raw runs — sorting and taking the middle is the definition — so
    // a mean, max, min, or unsorted statistic fails here, for distance
    // and driven time alike. medianDrivenMinutes is the sorted middle of
    // drivenSeconds, not the mean.
    for (final label in ['new', 'median', 'good']) {
      final runs = profileRuns[label]!;
      final stats = shiftStats[label]!;
      final distances = [for (final run in runs) run.distancePx]..sort();
      final driven = [for (final run in runs) run.drivenSeconds]..sort();
      final mid = runs.length ~/ 2;
      double middle(List<double> sorted) => sorted.length.isOdd
          ? sorted[mid]
          : (sorted[mid - 1] + sorted[mid]) / 2;

      expect(stats.medianKm, middle(distances) / 10000, reason: label);
      expect(
        stats.meanKm,
        runs.fold(0.0, (sum, run) => sum + run.distancePx) /
            runs.length /
            10000,
        reason: label,
      );
      expect(stats.medianDrivenMinutes, middle(driven) / 60, reason: label);
    }

    // Mean and median genuinely differ for these profiles, so swapping
    // the two statistics or reporting one as the other cannot pass.
    expect(shiftStats['new']!.medianKm, isNot(shiftStats['new']!.meanKm));
    expect(shiftStats['good']!.medianKm, isNot(shiftStats['good']!.meanKm));

    // The emitted table itself, pinned: labels and the deterministic
    // 101-seed batch's values. Re-measure these literals when the
    // simulator is retuned.
    final table = tableLines.join('\n');
    expect(
      table,
      contains('  median shift       : 3.0 km, 3.9 min driven, '
          '19 fares delivered, best chain x17'),
    );
    expect(table, contains('  mean shift         : 2.9 km'));
    expect(
      table,
      contains('  median shift       : 5.7 km, 11.4 min driven, '
          '35 fares delivered, best chain x16'),
    );
    expect(table, contains('  mean shift         : 6.2 km'));
  });

  test('a first-session driver out-earns nothing: new < median', () {
    // Only the bottom of the ladder is pinned as an ordering. Median vs
    // good is deliberately not: banked scores are high-variance (the
    // chain is quadratic in the fares between breaks), and the good
    // driver trades chain score for survival — deeper runs ride tighter
    // fare budgets — so their medians can legitimately cross. The batch
    // that priced the current ladder measured median 8368 vs good 8077
    // with heavily overlapping spreads; the wallet grows with skill,
    // just not monotonically in these stand-ins. The new-vs-median gap
    // is not free of history either: the first cut of issue #87's
    // traffic containment gated every spawn on the widest body, which
    // emptied ~2.5 km of same-direction traffic before every road
    // narrowing and flipped this ordering (new 7136 vs median 6919).
    // That was a difficulty regression, not a legitimate crossing, and
    // was fixed by gating on the body each spawn rolls; the batch after
    // that fix re-measured new 6001 / median 7134 / good 7697.
    expect(
      medians,
      isNotEmpty,
      reason: 'the table above must run first',
    );
    expect(medians['new']!, lessThan(medians['median']!),
        reason: 'a first-session driver must out-earn nothing');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('ride tips are included and bounded (issue #276)', () {
    // The same rule the live dropoff pays, priced from the simulator's
    // own close-call ledger: recomputing each run's earnings must carry
    // tip coins, and no shift may ever tip past the per-fare cap.
    final earnings = [
      for (final label in ['new', 'median', 'good'])
        for (final run in profileRuns[label]!) ShiftEarnings.forRun(run),
    ];
    expect(earnings, isNotEmpty, reason: 'the table above must run first');

    for (final e in earnings) {
      expect(e.tipsCoins, greaterThanOrEqualTo(0));
      expect(e.tipsCoins,
          lessThanOrEqualTo(e.faresDelivered * TipRule.maxTipCoins),
          reason: 'tips are capped per fare — the bound is structural');
      expect(e.totalCoins, e.faresCoins + e.tipsCoins + e.bankedScore,
          reason: 'the shift total must include the tip, not hide it');
      expect(e.wreckCoins, e.faresCoins + e.tipsCoins,
          reason: 'the never-banked floor takes its tips too');
    }

    // The effect is included, not zeroed out: the batch's drivers do
    // clear close calls with fares aboard (and clean chain deliveries),
    // so the instrument would catch a tip rule that paid nothing.
    final tipped = earnings.where((e) => e.tipsCoins > 0).length;
    expect(tipped, greaterThan(0),
        reason: 'at least some simulated shifts must earn a tip');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
