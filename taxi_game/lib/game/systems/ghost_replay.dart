import 'dart:math' as math;

import 'package:flame/components.dart';

import '../../models/ghost_trace.dart';

/// Records the player's path during a run on the daily course (issue
/// #20), as the sample grid a [GhostPlayback] replays.
///
/// [tick] is driven by the run's *driven-time* clock — the same beats
/// [GhostTrace] documents: world-update time while the shift is live,
/// frozen through crash hit-stops and stalls. Recording on any other
/// clock would desync the ghost from the run it replays against.
///
/// Pure logic — positions in, samples out — so the cadence and the cap
/// are unit testable like the course itself.
class GhostRecorder {
  final List<int> _samples = <int>[];
  double _elapsed = 0;

  /// True once the trace hit [GhostTrace.maxSamples]: recording stops,
  /// and the ghost will stop where the recording did.
  bool get isFull => _samples.length >= GhostTrace.maxSamples * 2;

  /// One frame of the run: advance the driven clock and take any sample
  /// whose grid time has arrived. Sample *k* is the position at driven
  /// time k · [GhostTrace.samplePeriod]; a long frame simply records the
  /// current position for each grid point it spans.
  void tick(double dt, double x, double y) {
    if (isFull) return;
    _elapsed += dt;
    const period = GhostTrace.samplePeriod;
    while (!isFull && _elapsed >= (_samples.length ~/ 2) * period) {
      _samples
        ..add(x.round())
        ..add(y.round());
    }
  }

  /// The samples taken so far, as a flat `[x0, y0, x1, y1, ...]` list —
  /// a copy, so later ticks never mutate what a finished run stored.
  List<int> takeSamples() => List.of(_samples);
}

/// Replays a [GhostTrace]: the ghost's position at driven time [t],
/// linear between neighbouring samples and clamped at both ends. Random
/// access is safe — there is no cursor to corrupt.
class GhostPlayback {
  GhostPlayback(this.trace);

  final GhostTrace trace;

  /// Position at driven time [t]. Negative times clamp to the start;
  /// times past the trace's end hold its last recorded position — the
  /// ghost finishes its run and parks there.
  Vector2 positionAt(double t) {
    final count = trace.sampleCount;
    if (count == 0) return Vector2.zero();
    if (count == 1) return Vector2(_x(0), _y(0));

    final progress =
        (t / trace.samplePeriodSeconds).clamp(0.0, (count - 1).toDouble());
    final i = math.min(progress.floor(), count - 2);
    final f = progress - i;
    return Vector2(
      _x(i) + (_x(i + 1) - _x(i)) * f,
      _y(i) + (_y(i + 1) - _y(i)) * f,
    );
  }

  double _x(int sample) => trace.samples[sample * 2].toDouble();

  double _y(int sample) => trace.samples[sample * 2 + 1].toDouble();
}
