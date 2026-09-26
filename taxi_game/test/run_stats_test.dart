import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/models/run_stats.dart';

/// The aggregate over the shift history (issue #17): totals, medians, the
/// run-length distribution, and the bank-vs-push ratio — the numbers the
/// difficulty curve (#18) gets tuned from, since the offline game has no
/// other instrument.
void main() {
  /// A record with every knob settable, in px on the game's scale
  /// (10 px = 1 m).
  RunRecord rec({
    double distancePx = 0,
    int score = 0,
    int fares = 0,
    int chain = 1,
    List<double> lifeLossesPx = const [],
    bool banked = false,
    double durationSeconds = 0,
  }) {
    return RunRecord(
      endedAtMs: 0,
      distancePx: distancePx,
      score: score,
      faresDelivered: fares,
      longestChain: chain,
      livesLost: lifeLossesPx.length,
      lifeLossDistancesPx: lifeLossesPx,
      banked: banked,
      durationSeconds: durationSeconds,
    );
  }

  group('an empty history', () {
    test('is a valid all-zero result, not an error', () {
      final stats = RunStats.compute(const []);

      expect(stats.isEmpty, isTrue);
      expect(stats.runCount, 0);
      expect(stats.totalScore, 0);
      expect(stats.totalDistanceMetres, 0.0);
      expect(stats.totalFares, 0);
      expect(stats.totalLivesLost, 0);
      expect(stats.totalDurationSeconds, 0.0);
    });

    test('has no medians — the median of nothing is a question', () {
      final stats = RunStats.compute(const []);

      expect(stats.medianScore, isNull);
      expect(stats.medianDistanceMetres, isNull);
      expect(stats.medianDurationSeconds, isNull);
      expect(stats.medianLifeLossDistanceMetres, isNull);
    });

    test('has an all-zero distribution and a 0 share', () {
      final stats = RunStats.compute(const []);

      expect(stats.runLengthDistribution.map((b) => b.count),
          everyElement(0));
      expect(stats.runLengthDistribution.length,
          RunLengthBucket.bounds.length);
      expect(stats.bankedShare, 0.0);
    });
  });

  group('totals', () {
    test('sum every shift', () {
      final stats = RunStats.compute([
        rec(
            distancePx: 5000,
            score: 120,
            fares: 3,
            lifeLossesPx: [2000],
            durationSeconds: 60),
        rec(
            distancePx: 20000,
            score: 300,
            fares: 5,
            lifeLossesPx: [4000, 15000],
            durationSeconds: 200),
      ]);

      expect(stats.runCount, 2);
      expect(stats.totalScore, 420);
      expect(stats.totalDistanceMetres, closeTo(2500, 0.001));
      expect(stats.totalFares, 8);
      expect(stats.totalLivesLost, 3);
      expect(stats.totalDurationSeconds, 260.0);
    });
  });

  group('medians', () {
    test('an odd history picks the middle shift', () {
      final stats = RunStats.compute([
        rec(score: 10, distancePx: 1000, durationSeconds: 30),
        rec(score: 50, distancePx: 5000, durationSeconds: 90),
        rec(score: 100, distancePx: 9000, durationSeconds: 150),
      ]);

      expect(stats.medianScore, 50.0);
      expect(stats.medianDistanceMetres, 500.0);
      expect(stats.medianDurationSeconds, 90.0);
    });

    test('an even history takes the midpoint of the two middle shifts',
        () {
      final stats = RunStats.compute([
        rec(score: 10),
        rec(score: 20),
        rec(score: 30),
        rec(score: 100),
      ]);

      expect(stats.medianScore, 25.0);
    });

    test('are unfooled by one giant outlier', () {
      final stats = RunStats.compute([
        rec(score: 10),
        rec(score: 20),
        rec(score: 30),
        rec(score: 40),
        rec(score: 100000),
      ]);

      expect(stats.medianScore, 30.0,
          reason: 'the mean would read 20020 — the median reads the '
              'typical shift');
    });

    test('the median crash distance spans every life ever lost', () {
      final stats = RunStats.compute([
        rec(lifeLossesPx: [1000]), // 100 m
        rec(), // no crashes
        rec(lifeLossesPx: [3000, 5000, 11000]), // 300, 500, 1100 m
      ]);

      expect(stats.totalLivesLost, 4);
      expect(stats.medianLifeLossDistanceMetres, 400.0,
          reason: 'median of 100, 300, 500, 1100');
    });

    test('is null when no life was ever lost', () {
      final stats = RunStats.compute([rec(banked: true)]);

      expect(stats.medianLifeLossDistanceMetres, isNull);
    });
  });

  group('the run-length distribution', () {
    test('bands every shift by distance, edges inclusive-exclusive', () {
      final stats = RunStats.compute([
        rec(distancePx: 4999), // 499.9 m -> under 500
        rec(distancePx: 5000), // exactly 500 m -> next band
        rec(distancePx: 10000), // 1 km
        rec(distancePx: 20000), // 2 km
        rec(distancePx: 40000), // 4 km
        rec(distancePx: 80000), // 8 km -> open-ended top band
        rec(distancePx: 3000), // 300 m
      ]);

      final counts = stats.runLengthDistribution.map((b) => b.count).toList();

      expect(counts, [2, 1, 1, 1, 2],
          reason: 'under 500: 2 · 500–1k: 1 · 1–2k: 1 · 2–4k: 1 · '
              'over 4k: 4 km exactly and 8 km');
    });

    test('keeps the fixed band labels in display order', () {
      final stats = RunStats.compute(const []);

      expect(
        stats.runLengthDistribution.map((b) => b.label),
        ['Under 500 m', '500 m – 1 km', '1 – 2 km', '2 – 4 km', 'Over 4 km'],
      );
    });

    test('fractions read against the run count', () {
      final stats = RunStats.compute([rec(distancePx: 100), rec()]);

      expect(stats.runLengthDistribution.first.fractionOf(stats.runCount),
          1.0);
      expect(stats.runLengthDistribution.last.fractionOf(stats.runCount), 0.0);
    });
  });

  group('the bank-vs-push ratio', () {
    test('counts each ending once', () {
      final stats = RunStats.compute([
        rec(banked: true),
        rec(banked: true),
        rec(banked: false),
      ]);

      expect(stats.bankedCount, 2);
      expect(stats.forfeitedCount, 1);
      expect(stats.bankedShare, closeTo(2 / 3, 0.0001));
    });

    test('a clean sweep reads 100%', () {
      final stats =
          RunStats.compute([rec(banked: true), rec(banked: true)]);

      expect(stats.bankedShare, 1.0);
    });
  });

  group('formatting', () {
    test('distance reads in metres under a kilometre', () {
      expect(RunStats.formatDistance(123.4), '123 m');
      expect(RunStats.formatDistance(999.9), '1000 m',
          reason: 'rounding at the boundary is display-only');
    });

    test('distance reads in kilometres above one', () {
      expect(RunStats.formatDistance(1000), '1.0 km');
      expect(RunStats.formatDistance(2456), '2.5 km');
    });

    test('duration reads as a clock', () {
      expect(RunStats.formatDuration(0), '0:00');
      expect(RunStats.formatDuration(65), '1:05');
      expect(RunStats.formatDuration(600), '10:00');
      expect(RunStats.formatDuration(3725), '1:02:05');
    });
  });
}
