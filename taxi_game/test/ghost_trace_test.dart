import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/ghost_replay.dart';
import 'package:taxi_game/models/ghost_trace.dart';

/// The ghost trace's data and replay contracts (issue #20): the sampled
/// path stays small and self-describing, the recorder samples the
/// driven-time grid, and the playback interpolates (and clamps) along it.
void main() {
  GhostTrace traceOf(List<int> samples) => GhostTrace(
        dateKey: '2026-09-26',
        score: 1,
        banked: true,
        vehicleId: 'taxi_yellow',
        samples: samples,
      );

  group('GhostTrace', () {
    const trace = GhostTrace(
      dateKey: '2026-09-26',
      score: 480,
      banked: true,
      vehicleId: 'sedan_blue',
      samples: [200, 0, 205, -60, 210, -120],
    );

    test('JSON round-trips', () {
      final back = GhostTrace.fromJson(trace.toJson());
      expect(back.dateKey, trace.dateKey);
      expect(back.score, trace.score);
      expect(back.banked, trace.banked);
      expect(back.vehicleId, trace.vehicleId);
      expect(back.samples, trace.samples);
      expect(back.samplePeriodSeconds, GhostTrace.samplePeriod);
    });

    test('missing keys default instead of throwing (older builds)', () {
      final back = GhostTrace.fromJson(const {});
      expect(back.dateKey, '');
      expect(back.score, 0);
      expect(back.banked, isFalse);
      expect(back.vehicleId, 'taxi_yellow');
      expect(back.samples, isEmpty);
      expect(back.samplePeriodSeconds, GhostTrace.samplePeriod);
    });

    test('sampleCount and coveredSeconds describe the trace', () {
      expect(trace.sampleCount, 3);
      expect(trace.coveredSeconds, 2 * GhostTrace.samplePeriod);
      expect(traceOf(const []).coveredSeconds, 0.0);
    });

    test('the cap keeps the payload bounded', () {
      // 2400 samples at 0.2 s covers 8 minutes of driving — the cap is
      // the size guarantee, not a target.
      expect(GhostTrace.maxSamples * GhostTrace.samplePeriod, 480.0);
    });
  });

  group('GhostRecorder', () {
    test('the first tick records the starting position', () {
      final recorder = GhostRecorder();
      recorder.tick(1 / 60, 200, 0);
      expect(recorder.takeSamples(), [200, 0]);
    });

    test('samples land on the driven-time grid, positions quantized to px',
        () {
      final recorder = GhostRecorder();
      // Ticks of 0.1 s reach the 0.2 s grid points one at a time.
      recorder.tick(0.1, 199.4, -10.0);
      expect(recorder.takeSamples(), [199, -10],
          reason: 'sample 0 at t=0, x rounded to whole px');
      recorder.tick(0.1, 200.0, -30.0);
      expect(recorder.takeSamples(), [199, -10, 200, -30],
          reason: 'sample 1 at t=0.2');
      recorder.tick(0.1, 201.0, -50.0);
      expect(recorder.takeSamples().length, 4,
          reason: 't=0.3 is between grid points; no sample yet');
    });

    test('a long frame fills every grid point it spans', () {
      final recorder = GhostRecorder();
      recorder.tick(GhostTrace.samplePeriod * 3, 150, -5);
      expect(recorder.takeSamples(), [150, -5, 150, -5, 150, -5, 150, -5],
          reason: 't=0, 0.2, 0.4 and 0.6 all passed inside one frame');
    });

    test('recording stops at the cap, and takeSamples is a copy', () {
      final recorder = GhostRecorder();
      const bigFrame = GhostTrace.samplePeriod * 100;
      for (var i = 0; i < 30; i++) {
        recorder.tick(bigFrame, i.toDouble(), -i.toDouble());
      }
      expect(recorder.isFull, isTrue);
      expect(recorder.takeSamples().length, GhostTrace.maxSamples * 2);

      final snapshot = recorder.takeSamples();
      recorder.tick(1, 999, 999);
      expect(recorder.takeSamples(), snapshot,
          reason: 'a full recorder never grows, and never aliases');
    });
  });

  group('GhostPlayback', () {
    test('clamps to the recorded ends', () {
      final playback = GhostPlayback(traceOf([200, 0, 200, -100]));
      expect(playback.positionAt(-5).y, 0, reason: 'before the start');
      expect(playback.positionAt(-5).x, 200);
      expect(playback.positionAt(99).y, -100, reason: 'past the end');
    });

    test('interpolates linearly between samples', () {
      final playback =
          GhostPlayback(traceOf([200, 0, 210, -100, 220, -200]));
      final half = playback.positionAt(GhostTrace.samplePeriod / 2);
      expect(half.x, closeTo(205, 0.001));
      expect(half.y, closeTo(-50, 0.001));
      final late = playback.positionAt(GhostTrace.samplePeriod * 1.75);
      expect(late.x, closeTo(217.5, 0.001));
      expect(late.y, closeTo(-175, 0.001));
    });

    test('honours the trace\'s own sample period', () {
      const trace = GhostTrace(
        dateKey: '2026-09-26',
        score: 1,
        banked: true,
        vehicleId: 'taxi_yellow',
        samples: [200, 0, 200, -50],
        samplePeriodSeconds: 0.5,
      );
      expect(GhostPlayback(trace).positionAt(0.25).y, -25);
    });

    test('a single-sample trace is a fixed point; empty is the origin',
        () {
      final single = GhostPlayback(traceOf([200, -7])).positionAt(10);
      expect(single.x, 200);
      expect(single.y, -7);
      final empty = GhostPlayback(traceOf(const [])).positionAt(10);
      expect(empty.x, 0);
      expect(empty.y, 0);
    });
  });
}
