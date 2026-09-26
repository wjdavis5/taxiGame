import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/models/run_record.dart';

/// The per-shift record behind the on-device stats (issue #17): every
/// field survives its JSON round-trip into storage, and records written
/// by an older build — missing keys — load instead of throwing.
void main() {
  RunRecord record() => const RunRecord(
        endedAtMs: 1700000000000,
        distancePx: 12345.5,
        score: 480,
        faresDelivered: 7,
        longestChain: 5,
        livesLost: 2,
        lifeLossDistancesPx: [3000.0, 9800.25],
        banked: false,
        durationSeconds: 214.5,
      );

  group('RunRecord JSON round-trip', () {
    test('every field survives a write and a read', () {
      final json = record().toJson();
      final restored = RunRecord.fromJson(json);

      expect(restored.endedAtMs, 1700000000000);
      expect(restored.distancePx, 12345.5);
      expect(restored.score, 480);
      expect(restored.faresDelivered, 7);
      expect(restored.longestChain, 5);
      expect(restored.livesLost, 2);
      expect(restored.lifeLossDistancesPx, [3000.0, 9800.25]);
      expect(restored.banked, isFalse);
      expect(restored.durationSeconds, 214.5);
    });

    test('a clean banked run round-trips too', () {
      const banked = RunRecord(
        endedAtMs: 7,
        distancePx: 9000,
        score: 250,
        faresDelivered: 4,
        longestChain: 4,
        livesLost: 0,
        lifeLossDistancesPx: [],
        banked: true,
        durationSeconds: 180,
      );

      final restored = RunRecord.fromJson(banked.toJson());

      expect(restored.banked, isTrue);
      expect(restored.livesLost, 0);
      expect(restored.lifeLossDistancesPx, isEmpty);
    });

    test('life-loss distances convert px to metres on the HUD scale', () {
      expect(record().distanceMetres, closeTo(1234.55, 0.001));
      expect(record().lifeLossDistancesMetres, [300.0, 980.025]);
    });
  });

  group('a record written by an older build', () {
    test('loads with defaults instead of throwing', () {
      // A pre-issue-#17 shape: whatever fields exist later, a record that
      // predates them must still read.
      final record = RunRecord.fromJson({
        'score': 120,
      });

      expect(record.score, 120);
      expect(record.endedAtMs, 0);
      expect(record.distancePx, 0.0);
      expect(record.faresDelivered, 0);
      expect(record.longestChain, 1, reason: 'a chain record starts at 1x');
      expect(record.livesLost, 0);
      expect(record.lifeLossDistancesPx, isEmpty);
      expect(record.banked, isFalse);
      expect(record.durationSeconds, 0.0);
    });
  });
}
