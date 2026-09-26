import 'dart:math' as math;

import '../../models/traffic_pattern.dart';

/// The traffic pressure in effect at one distance along an endless run.
///
/// Structurally identical to a level's [TrafficPattern] (one spawn interval
/// plus per-lane configs), so the spawner can consume either without
/// branching on the mode.
class TrafficProfile {
  final double spawnInterval; // Seconds between spawn attempts
  final List<TrafficLaneConfig> lanes;

  const TrafficProfile({
    required this.spawnInterval,
    required this.lanes,
  });
}

/// Continuous difficulty for endless runs (issue #11): traffic density and
/// speed are pure functions of distance travelled, replacing the per-level
/// [TrafficPattern] constants.
///
/// The curve has two phases:
///  - a ramp from the lightest level-1 pressure to beyond the old heavy
///    pattern over the first [fullRampDistance] px, and
///  - a slow creep past that, so a 30-minute run (~250,000 px at top speed)
///    never sits on a plateau.
///
/// Issue #18 will retune the anchors against playtest data and add pressure
/// waves; the shape (a continuous pure function of distance) is what this
/// issue locks in.
///
/// Pure logic — no Flame — so every number is unit testable.
class DifficultyCurve {
  DifficultyCurve._();

  /// Distance (px) at which the ramp to full pressure completes.
  static const double fullRampDistance = 40000.0;

  /// Distance (px) at which the slow post-ramp creep tops out.
  static const double creepEndDistance = 240000.0;

  // Lane geometry: the road spans x 100..300 with the centre line at 200,
  // so each half-lane is centred on these.
  static const double oncomingLaneX = 150.0;
  static const double sameDirectionLaneX = 250.0;

  // Anchor values. The distance-0 anchors match TrafficPattern.light so an
  // endless run starts as gentle as level 1; the end of the ramp sits
  // slightly past TrafficPattern.heavy.
  static const double _startInterval = 4.0;
  static const double _rampedInterval = 1.4;
  static const double _creepInterval = 1.0;

  static const double _startOncomingProbability = 0.30;
  static const double _rampedOncomingProbability = 0.85;
  static const double _creepOncomingProbability = 0.95;

  static const double _startSameDirProbability = 0.20;
  static const double _rampedSameDirProbability = 0.70;
  static const double _creepSameDirProbability = 0.85;

  static const double _startSpeedMin = 80.0;
  static const double _rampedSpeedMin = 160.0;
  static const double _creepSpeedMin = 180.0;

  static const double _startSpeedMax = 120.0;
  static const double _rampedSpeedMax = 240.0;
  static const double _creepSpeedMax = 260.0;

  /// Fraction (0..1) of the main ramp completed at [distance]. Exposed so
  /// other generators (e.g. fare spacing) can grow with the same pacing.
  static double rampFractionFor(double distance) =>
      _smoothstep(distance / fullRampDistance);

  /// The traffic profile in effect at [distance] px into the run.
  static TrafficProfile trafficForDistance(double distance) {
    // Phase 1: light → ramped over the first stretch...
    final ramp = rampFractionFor(distance);
    // ...phase 2: a slow creep beyond that, so long runs keep tightening.
    final creep = _smoothstep(
      (distance - fullRampDistance) /
          (creepEndDistance - fullRampDistance),
    );

    return TrafficProfile(
      spawnInterval: _lerp3(_startInterval, _rampedInterval, _creepInterval,
          ramp, creep),
      lanes: [
        TrafficLaneConfig(
          laneX: oncomingLaneX,
          speedRange: SpeedRange(
            min: _lerp3(_startSpeedMin, _rampedSpeedMin, _creepSpeedMin, ramp,
                creep),
            max: _lerp3(_startSpeedMax, _rampedSpeedMax, _creepSpeedMax, ramp,
                creep),
          ),
          spawnProbability: _lerp3(
              _startOncomingProbability,
              _rampedOncomingProbability,
              _creepOncomingProbability,
              ramp,
              creep),
          oncoming: true,
        ),
        TrafficLaneConfig(
          laneX: sameDirectionLaneX,
          speedRange: SpeedRange(
            min: _lerp3(_startSpeedMin, _rampedSpeedMin, _creepSpeedMin, ramp,
                creep),
            max: _lerp3(_startSpeedMax, _rampedSpeedMax, _creepSpeedMax, ramp,
                creep),
          ),
          spawnProbability: _lerp3(
              _startSameDirProbability,
              _rampedSameDirProbability,
              _creepSameDirProbability,
              ramp,
              creep),
          oncoming: false,
        ),
      ],
    );
  }

  static double _smoothstep(double t) {
    final c = t.clamp(0.0, 1.0).toDouble();
    return c * c * (3 - 2 * c);
  }

  /// Piecewise lerp: [a]→[b] over phase 1, then [b]→[c] over phase 2.
  static double _lerp3(double a, double b, double c, double t1, double t2) {
    if (t1 < 1.0) return a + (b - a) * t1;
    return b + (c - b) * math.min(t2, 1.0);
  }
}
