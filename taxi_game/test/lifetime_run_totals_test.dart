import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/models/lifetime_run_totals.dart';
import 'package:taxi_game/models/run_record.dart';

/// The lifetime totals block (issue #183): six monotone counters stored
/// in the save, applied per shift, and seeded once from the history
/// window — the fix for Totals rows that froze at the window's 200 shifts
/// and then fell as old shifts aged out of it.
void main() {
  /// A record with the knobs the totals read, in px on the game's scale
  /// (10 px = 1 m).
  RunRecord rec({
    double distancePx = 0,
    int score = 0,
    int fares = 0,
    int livesLost = 0,
    double durationSeconds = 0,
    Map<String, int> acceptedByKind = const {},
    Map<String, int> declinedByKind = const {},
  }) {
    return RunRecord(
      endedAtMs: 0,
      distancePx: distancePx,
      score: score,
      faresDelivered: fares,
      longestChain: 1,
      livesLost: livesLost,
      lifeLossDistancesPx: List<double>.filled(livesLost, 100),
      banked: livesLost == 0,
      durationSeconds: durationSeconds,
      acceptedByKind: acceptedByKind,
      declinedByKind: declinedByKind,
    );
  }

  group('applyRun', () {
    test('folds one shift into all six counters', () {
      final totals = LifetimeRunTotals();
      totals.applyRun(rec(
        distancePx: 5000,
        score: 120,
        fares: 3,
        livesLost: 1,
        durationSeconds: 90,
      ));

      expect(totals.shiftsEnded, 1);
      expect(totals.totalScore, 120);
      expect(totals.totalDistancePx, 5000);
      expect(totals.totalDistanceMetres, 500);
      expect(totals.totalFares, 3);
      expect(totals.totalLivesLost, 1);
      expect(totals.totalDurationSeconds, 90);
    });

    test('accumulates shift over shift, in every counter', () {
      final totals = LifetimeRunTotals();
      totals.applyRun(
          rec(distancePx: 1000, score: 10, fares: 1, durationSeconds: 30));
      totals.applyRun(rec(
          distancePx: 2000,
          score: 20,
          fares: 2,
          livesLost: 3,
          durationSeconds: 40));

      expect(totals.shiftsEnded, 2);
      expect(totals.totalScore, 30);
      expect(totals.totalDistancePx, 3000);
      expect(totals.totalFares, 3);
      expect(totals.totalLivesLost, 3);
      expect(totals.totalDurationSeconds, 70);
    });

    test('folds the per-kind accepted and declined counts', () {
      final totals = LifetimeRunTotals();
      totals.applyRun(rec(
        acceptedByKind: {'vip': 2, 'standard': 3},
        declinedByKind: {'vip': 1},
      ));
      totals.applyRun(rec(
        acceptedByKind: {'vip': 1, 'awkward': 1},
        declinedByKind: {'vip': 2, 'longHaul': 1},
      ));

      expect(totals.acceptedFaresByKind,
          {'vip': 3, 'standard': 3, 'awkward': 1});
      expect(totals.declinedFaresByKind, {'vip': 3, 'longHaul': 1});
    });
  });

  group('seedFromWindow', () {
    test('a pre-fix save — all zeros — seeds the window\'s own sums',
        () {
      // The shape of a save written before issue #183 loading with a
      // full history: nothing stored, the window is everything.
      final totals = LifetimeRunTotals();
      final window = [
        rec(distancePx: 1000, score: 10, fares: 1, durationSeconds: 30),
        rec(
            distancePx: 2000,
            score: 20,
            fares: 2,
            livesLost: 2,
            durationSeconds: 40),
      ];

      expect(totals.seedFromWindow(window), isTrue,
          reason: 'counters moved, so the caller must persist the seed');
      expect(totals.shiftsEnded, 2);
      expect(totals.totalScore, 30);
      expect(totals.totalDistancePx, 3000);
      expect(totals.totalFares, 3);
      expect(totals.totalLivesLost, 2);
      expect(totals.totalDurationSeconds, 70);
    });

    test('a post-migration save keeps its larger numbers — nothing falls',
        () {
      // The lifetime counted 350 shifts; the window can only hold 200 of
      // them, so its sums are strictly smaller per field and the seed
      // must leave every counter alone.
      final totals = LifetimeRunTotals(
        shiftsEnded: 350,
        totalScore: 35000,
        totalDistancePx: 350000,
        totalFares: 700,
        totalLivesLost: 210,
        totalDurationSeconds: 35000,
      );
      final window = List.generate(
        200,
        (i) => rec(
            distancePx: 100, score: 10, fares: 1, durationSeconds: 10),
      );

      expect(totals.seedFromWindow(window), isFalse,
          reason: 'nothing moved — no save needed');
      expect(totals.shiftsEnded, 350);
      expect(totals.totalScore, 35000);
      expect(totals.totalDistancePx, 350000);
      expect(totals.totalFares, 700);
      expect(totals.totalLivesLost, 210);
      expect(totals.totalDurationSeconds, 35000);
    });

    test('the max is per field: a save ahead on one counter takes the window\'s larger on another',
        () {
      // A save whose lifetime count is right but one sum is behind (say
      // a partially-written block) still takes the window's larger sum —
      // per-field max, never all-or-nothing.
      final totals = LifetimeRunTotals(shiftsEnded: 350, totalScore: 100);
      final window = List.generate(200, (i) => rec(score: 10));

      expect(totals.seedFromWindow(window), isTrue);
      expect(totals.shiftsEnded, 350,
          reason: 'already ahead — untouched');
      expect(totals.totalScore, 2000,
          reason: 'behind — takes the window sum');
    });

    test('an empty window seeds nothing', () {
      final totals = LifetimeRunTotals();
      expect(totals.seedFromWindow(const []), isFalse);
      expect(totals.shiftsEnded, 0);
    });

    test('seeds the per-kind counts per key, never down', () {
      final totals = LifetimeRunTotals(acceptedFaresByKind: {'vip': 5});
      final window = [
        rec(
          acceptedByKind: {'vip': 2, 'awkward': 4},
          declinedByKind: {'vip': 1},
        ),
      ];

      expect(totals.seedFromWindow(window), isTrue);
      expect(totals.acceptedFaresByKind['vip'], 5,
          reason: 'stored wins while it is the larger number');
      expect(totals.acceptedFaresByKind['awkward'], 4,
          reason: 'a key the save lacks takes the window count');
      expect(totals.declinedFaresByKind['vip'], 1);
    });
  });

  group('persistence', () {
    test('round-trips through JSON', () {
      final totals = LifetimeRunTotals(
        shiftsEnded: 7,
        totalScore: 900,
        totalDistancePx: 12345.5,
        totalFares: 42,
        totalLivesLost: 9,
        totalDurationSeconds: 4567.5,
        acceptedFaresByKind: {'vip': 3, 'standard': 12},
        declinedFaresByKind: {'longHaul': 2},
      );

      final restored =
          LifetimeRunTotals.fromJson(totals.toJson());

      expect(restored.shiftsEnded, 7);
      expect(restored.totalScore, 900);
      expect(restored.totalDistancePx, 12345.5);
      expect(restored.totalFares, 42);
      expect(restored.totalLivesLost, 9);
      expect(restored.totalDurationSeconds, 4567.5);
      expect(restored.acceptedFaresByKind, {'vip': 3, 'standard': 12},
          reason: 'the per-kind counts survive (issue #279)');
      expect(restored.declinedFaresByKind, {'longHaul': 2});
    });

    test('a missing block reads as zeros — the pre-fix save', () {
      // issue #183's own migration case: the block does not exist yet.
      final totals = LifetimeRunTotals.fromJson({});

      expect(totals.shiftsEnded, 0);
      expect(totals.totalScore, 0);
      expect(totals.totalDistancePx, 0.0);
      expect(totals.totalFares, 0);
      expect(totals.totalLivesLost, 0);
      expect(totals.totalDurationSeconds, 0.0);
      expect(totals.acceptedFaresByKind, isEmpty);
      expect(totals.declinedFaresByKind, isEmpty);
    });
  });
}
