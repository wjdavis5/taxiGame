import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/difficulty_curve.dart';

/// The continuous difficulty curve for endless runs (issue #11): traffic
/// density and speed must be pure continuous functions of distance, not
/// the per-level TrafficPattern constants.
void main() {
  group('DifficultyCurve', () {
    test('starts at the light level-1 pressure', () {
      final profile = DifficultyCurve.trafficForDistance(0);

      // The anchors TrafficPattern.light was tuned to.
      expect(profile.spawnInterval, 4.0);
      final oncoming = profile.lanes.firstWhere((l) => l.oncoming);
      final withFlow = profile.lanes.firstWhere((l) => !l.oncoming);
      expect(oncoming.spawnProbability, closeTo(0.30, 0.0001));
      expect(withFlow.spawnProbability, closeTo(0.20, 0.0001));
      expect(oncoming.speedRange.min, 80.0);
      expect(oncoming.speedRange.max, 120.0);
    });

    test('reaches heavy pressure by the end of the ramp', () {
      final profile =
          DifficultyCurve.trafficForDistance(DifficultyCurve.fullRampDistance);

      // At least as hard as the old TrafficPattern.heavy anchors.
      expect(profile.spawnInterval, lessThanOrEqualTo(1.5));
      final oncoming = profile.lanes.firstWhere((l) => l.oncoming);
      final withFlow = profile.lanes.firstWhere((l) => !l.oncoming);
      expect(oncoming.spawnProbability, greaterThanOrEqualTo(0.85));
      expect(withFlow.spawnProbability, greaterThanOrEqualTo(0.70));
      expect(oncoming.speedRange.max, greaterThanOrEqualTo(220.0));
    });

    test('keeps tightening slowly after the ramp (no 30-minute plateau)', () {
      final atRampEnd =
          DifficultyCurve.trafficForDistance(DifficultyCurve.fullRampDistance);
      final late =
          DifficultyCurve.trafficForDistance(DifficultyCurve.creepEndDistance);

      expect(late.spawnInterval, lessThan(atRampEnd.spawnInterval));
      final lateOncoming = late.lanes.firstWhere((l) => l.oncoming);
      final rampedOncoming =
          atRampEnd.lanes.firstWhere((l) => l.oncoming);
      expect(
        lateOncoming.spawnProbability,
        greaterThan(rampedOncoming.spawnProbability),
      );
      expect(lateOncoming.speedRange.max,
          greaterThan(rampedOncoming.speedRange.max));
    });

    test('density and speed rise monotonically with distance', () {
      var previous = DifficultyCurve.trafficForDistance(0);
      for (var d = 250.0; d <= 300000; d += 250) {
        final profile = DifficultyCurve.trafficForDistance(d);

        expect(profile.spawnInterval, lessThanOrEqualTo(previous.spawnInterval),
            reason: 'spawn interval at $d px');
        for (var lane = 0; lane < 2; lane++) {
          expect(
            profile.lanes[lane].spawnProbability,
            greaterThanOrEqualTo(previous.lanes[lane].spawnProbability),
            reason: 'lane $lane probability at $d px',
          );
          expect(
            profile.lanes[lane].speedRange.min,
            greaterThanOrEqualTo(previous.lanes[lane].speedRange.min),
            reason: 'lane $lane min speed at $d px',
          );
          expect(
            profile.lanes[lane].speedRange.max,
            greaterThanOrEqualTo(previous.lanes[lane].speedRange.max),
            reason: 'lane $lane max speed at $d px',
          );
        }
        previous = profile;
      }
    });

    test('is continuous: no perceptible jumps between nearby distances', () {
      var previous = DifficultyCurve.trafficForDistance(0);
      for (var d = 100.0; d <= 300000; d += 100) {
        final profile = DifficultyCurve.trafficForDistance(d);

        expect(profile.spawnInterval - previous.spawnInterval,
            lessThanOrEqualTo(0.01),
            reason: 'interval step at $d px');
        for (final lane in profile.lanes) {
          expect(lane.spawnProbability, lessThanOrEqualTo(1.0));
          expect(lane.spawnProbability, greaterThanOrEqualTo(0.0));
        }
        expect(
          profile.lanes.first.speedRange.max - previous.lanes.first.speedRange.max,
          lessThanOrEqualTo(0.5),
          reason: 'speed step at $d px',
        );
        previous = profile;
      }
    });

    test('is a pure function: same distance, same profile', () {
      for (final d in [0.0, 12345.6, DifficultyCurve.fullRampDistance, 999999.0]) {
        final a = DifficultyCurve.trafficForDistance(d);
        final b = DifficultyCurve.trafficForDistance(d);
        expect(b.spawnInterval, a.spawnInterval);
        for (var lane = 0; lane < 2; lane++) {
          expect(b.lanes[lane].laneX, a.lanes[lane].laneX);
          expect(b.lanes[lane].spawnProbability, a.lanes[lane].spawnProbability);
          expect(b.lanes[lane].speedRange.min, a.lanes[lane].speedRange.min);
          expect(b.lanes[lane].speedRange.max, a.lanes[lane].speedRange.max);
        }
      }
    });

    test('keeps the two-lane road geometry', () {
      for (final d in [0.0, 5000.0, 150000.0]) {
        final profile = DifficultyCurve.trafficForDistance(d);
        expect(profile.lanes, hasLength(2));
        expect(
          profile.lanes.where((l) => l.oncoming).single.laneX,
          DifficultyCurve.oncomingLaneX,
        );
        expect(
          profile.lanes.where((l) => !l.oncoming).single.laneX,
          DifficultyCurve.sameDirectionLaneX,
        );
        // Every TrafficLaneConfig defaults oncoming from laneX <= 200, the
        // road's centre line — the curve's lanes must sit on the right
        // sides of it.
        expect(DifficultyCurve.oncomingLaneX, lessThanOrEqualTo(200));
        expect(DifficultyCurve.sameDirectionLaneX, greaterThan(200));
      }
    });
  });
}
