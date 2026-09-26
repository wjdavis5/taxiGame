import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/difficulty_curve.dart';

/// The continuous difficulty curve for endless runs (issue #18): traffic
/// density, speed, and speed variance are pure continuous functions of
/// distance, the whole thing rides a pressure wave so runs have rhythm,
/// and fare timer pressure tightens with the same breath.
void main() {
  group('DifficultyCurve — anchors', () {
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

    test('reaches heavy pressure by the end of the ramp (at a wave crest)',
        () {
      // The ramp-end distance sits mid-wave, so take the best the first
      // full wave past it offers — the crest must reach the old
      // TrafficPattern.heavy anchors.
      var interval = 99.0;
      var oncomingP = 0.0;
      var withFlowP = 0.0;
      var topSpeed = 0.0;
      for (var d = DifficultyCurve.fullRampDistance;
          d <
              DifficultyCurve.fullRampDistance +
                  DifficultyCurve.waveLength;
          d += 50) {
        final profile = DifficultyCurve.trafficForDistance(d);
        interval = math.min(interval, profile.spawnInterval);
        oncomingP = math.max(
            oncomingP, profile.lanes.firstWhere((l) => l.oncoming).spawnProbability);
        withFlowP = math.max(withFlowP,
            profile.lanes.firstWhere((l) => !l.oncoming).spawnProbability);
        topSpeed = math.max(
            topSpeed, profile.lanes.first.speedRange.max);
      }

      expect(interval, lessThanOrEqualTo(1.5));
      expect(oncomingP, greaterThanOrEqualTo(0.85));
      expect(withFlowP, greaterThanOrEqualTo(0.70));
      expect(topSpeed, greaterThanOrEqualTo(220.0));
    });

    test('keeps tightening slowly after the ramp (no 30-minute plateau)', () {
      final atRampEnd = DifficultyCurve.trafficForDistance(
          DifficultyCurve.fullRampDistance);
      final late = DifficultyCurve.trafficForDistance(
          DifficultyCurve.creepEndDistance);

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
  });

  group('DifficultyCurve — the pressure wave (issue #18 rhythm)', () {
    // Post-ramp distance where the wave is fully online.
    const base = DifficultyCurve.fullRampDistance * 1.5;

    test('pressure breathes: crests and troughs alternate forever', () {
      var crossings = 0;
      var lastAbove = DifficultyCurve.pressureFor(base) >=
          DifficultyCurve.phaseFor(base) * (1 - DifficultyCurve.reliefDepth / 2);
      for (var d = base; d <= base + DifficultyCurve.waveLength * 4;
          d += 50) {
        final w = DifficultyCurve.reliefFor(d) /
            DifficultyCurve.reliefDepth; // 0 crest .. 1 trough
        final above = w < 0.5;
        if (above != lastAbove) crossings++;
        lastAbove = above;
      }
      // Four wavelengths must contain at least four crest/trough
      // transitions — the rhythm never dies out.
      expect(crossings, greaterThanOrEqualTo(4));
    });

    test('troughs are materially lighter than crests at the same distance',
        () {
      var crest = 0.0;
      var trough = double.infinity;
      for (var d = base;
          d <= base + DifficultyCurve.waveLength;
          d += 25) {
        final p = DifficultyCurve.pressureFor(d);
        crest = math.max(crest, p);
        trough = math.min(trough, p);
      }
      // The dip must be a real exhale, not a rounding error.
      expect(trough / crest, lessThanOrEqualTo(0.65));
    });

    test('relief is brief: most of each wavelength rides near the crest',
        () {
      var nearCrestPx = 0;
      var totalPx = 0;
      for (var d = base;
          d <= base + DifficultyCurve.waveLength;
          d += 25) {
        totalPx++;
        final relief = DifficultyCurve.reliefFor(d);
        if (relief < DifficultyCurve.reliefDepth * 0.25) nearCrestPx++;
      }
      // At least 70% of every wave rides at three-quarters pressure or
      // higher — brief relief, not a safe zone.
      expect(nearCrestPx / totalPx, greaterThanOrEqualTo(0.70));
    });

    test('relief never becomes a safe zone', () {
      for (var d = DifficultyCurve.reliefOnlineDistance;
          d <= DifficultyCurve.creepEndDistance;
          d += 500) {
        final pressure = DifficultyCurve.pressureFor(d);
        final envelope = DifficultyCurve.phaseFor(d);
        // Even in the deepest dip the street keeps at least 55% of the
        // local pressure.
        expect(pressure, greaterThanOrEqualTo(envelope * 0.55),
            reason: 'pressure floor at $d px');
      }
    });

    test('the wave fades in over the opening, then holds full depth', () {
      expect(DifficultyCurve.reliefFor(0), 0.0);

      double deepestAfter(double from, [double? to]) {
        var best = 0.0;
        final end = to ?? from + DifficultyCurve.waveLength;
        for (var d = from; d <= end; d += 25) {
          best = math.max(best, DifficultyCurve.reliefFor(d));
        }
        return best;
      }

      expect(deepestAfter(DifficultyCurve.reliefOnlineDistance),
          closeTo(DifficultyCurve.reliefDepth, 0.001),
          reason: 'fully online past the fade-in distance');
      expect(deepestAfter(0, 1000), lessThan(DifficultyCurve.reliefDepth * 0.25),
          reason: 'the opening kilometre rides the flat, gentle ramp');
    });

    test('wave crests still climb: no plateau, pressure maxima rise', () {
      // Max pressure within each successive wavelength must never fall as
      // the run deepens — the rhythm sits on top of a climb.
      double crestAt(double from) {
        var best = 0.0;
        for (var d = from; d < from + DifficultyCurve.waveLength; d += 50) {
          best = math.max(best, DifficultyCurve.pressureFor(d));
        }
        return best;
      }

      for (var d = 0.0;
          d < DifficultyCurve.creepEndDistance - DifficultyCurve.waveLength;
          d += DifficultyCurve.waveLength) {
        expect(crestAt(d + DifficultyCurve.waveLength),
            greaterThanOrEqualTo(crestAt(d) - 1e-9),
            reason: 'crest climbing at $d px');
      }
    });
  });

  group('DifficultyCurve — speed variance (issue #18 knob)', () {
    double spreadAt(double d) {
      final lane = DifficultyCurve.trafficForDistance(d).lanes.first;
      return lane.speedRange.max - lane.speedRange.min;
    }

    test('spread widens with distance: deep traffic is less predictable',
        () {
      expect(spreadAt(0), 40.0); // the level-1 80..120 range
      expect(spreadAt(DifficultyCurve.fullRampDistance * 0.5),
          greaterThan(spreadAt(0)));
      expect(spreadAt(DifficultyCurve.fullRampDistance),
          greaterThan(spreadAt(DifficultyCurve.fullRampDistance * 0.5)));
      expect(spreadAt(DifficultyCurve.creepEndDistance),
          greaterThan(spreadAt(DifficultyCurve.fullRampDistance)));
    });

    test('variance is monotone in distance: it does not breathe', () {
      // Unlike density and mean speed, the spread must never oscillate —
      // across three full wavelengths it may only creep upward.
      const base = DifficultyCurve.fullRampDistance * 1.5;
      var previous = spreadAt(base);
      for (var d = base + 50.0;
          d <= base + DifficultyCurve.waveLength * 3;
          d += 50) {
        expect(spreadAt(d), greaterThanOrEqualTo(previous - 1e-9),
            reason: 'variance oscillated at $d px');
        previous = spreadAt(d);
      }
    });

    test('speed ranges stay sane at every distance', () {
      for (var d = 0.0; d <= 300000; d += 500) {
        final profile = DifficultyCurve.trafficForDistance(d);
        for (final lane in profile.lanes) {
          expect(lane.speedRange.min, greaterThanOrEqualTo(0.0));
          expect(lane.speedRange.max, greaterThan(lane.speedRange.min));
        }
      }
    });
  });

  group('DifficultyCurve — fare timer pressure (issue #18)', () {
    test('starts at zero and reaches full pressure by the ramp end', () {
      expect(DifficultyCurve.farePressureFor(0), 0.0);
      // The ramp-end distance sits mid-wave, so the meter arrives at full
      // pressure within a hair of the ramp completing.
      expect(DifficultyCurve.farePressureFor(DifficultyCurve.fullRampDistance),
          closeTo(1.0, 0.001));
    });

    test('stays bounded and breathes with the wave', () {
      var sawDip = false;
      for (var d = 0.0; d <= DifficultyCurve.creepEndDistance; d += 250) {
        final p = DifficultyCurve.farePressureFor(d);
        expect(p, inInclusiveRange(0.0, 1.0), reason: 'at $d px');
        if (d > DifficultyCurve.fullRampDistance &&
            p < 0.75 &&
            !sawDip) {
          sawDip = true;
        }
      }
      expect(sawDip, isTrue,
          reason: 'the meter eases off in the relief lulls too');
    });
  });

  group('DifficultyCurve — continuity and purity', () {
    test('is continuous: no perceptible jumps between nearby distances', () {
      var previous = DifficultyCurve.trafficForDistance(0);
      for (var d = 100.0; d <= 300000; d += 100) {
        final profile = DifficultyCurve.trafficForDistance(d);

        expect(profile.spawnInterval - previous.spawnInterval,
            lessThanOrEqualTo(0.30),
            reason: 'interval step at $d px');
        for (final lane in profile.lanes) {
          expect(lane.spawnProbability, inInclusiveRange(0.0, 1.0));
        }
        expect(
          profile.lanes.first.speedRange.max -
              previous.lanes.first.speedRange.max,
          lessThanOrEqualTo(12.0),
          reason: 'speed step at $d px',
        );
        previous = profile;
      }
    });

    test('is a pure function: same distance, same profile', () {
      for (final d in [
        0.0,
        12345.6,
        DifficultyCurve.fullRampDistance,
        999999.0
      ]) {
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
