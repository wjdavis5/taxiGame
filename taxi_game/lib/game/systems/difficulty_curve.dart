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

/// The curve's raw pressure read at one distance, before it is laid out
/// onto any particular road geometry: one spawn interval, one traffic
/// speed (mean plus half-spread), and one probability per traffic side.
///
/// [DifficultyCurve.trafficForDistance] lays a core onto the classic
/// two-lane street; [RunEnvironment.trafficAt] lays the same core onto
/// whatever width and lane count the road has there (issue #24) — same
/// pressure, different street.
class TrafficCore {
  const TrafficCore({
    required this.spawnInterval,
    required this.meanSpeed,
    required this.halfSpread,
    required this.oncomingProbability,
    required this.sameDirectionProbability,
  });

  final double spawnInterval;
  final double meanSpeed;
  final double halfSpread;
  final double oncomingProbability;
  final double sameDirectionProbability;
}

/// Continuous difficulty for endless runs (issue #18).
///
/// Four knobs — traffic density, traffic speed, speed variance, and fare
/// timer pressure — are pure continuous functions of distance, and the whole
/// thing *breathes*: a pressure wave rides on top of the slow climb so a run
/// has rhythm instead of an endless tightening ratchet.
///
/// The shape, in one formula:
///
///     pressure(d) = phase(d) * (1 - relief(d))
///
///  - `phase(d)` is the slow climb: a smoothstep ramp from the lightest
///    level-1 pressure to the old heavy pattern over [fullRampDistance], then
///    a slow creep beyond it so even a 30-minute run never sits on a plateau.
///  - `relief(d)` is the rhythm: a brief Gaussian pulse every [waveLength]
///    px that dips the pressure to about (1 - [reliefDepth]) of the climb —
///    a few seconds of lighter street after each sustained crest. The pulse
///    comes online over the first [reliefOnlineDistance] so a run's opening
///    kilometre stays flat and learnable, then breathes at full depth for
///    the rest of the shift.
///
/// The anchors at pressure 1.0 (the crest values at the end of the ramp) are
/// the ones issue #11 shipped; they are kept so the curve's hardest regular
/// moments still match what the tutorial ladder graduates players from.
/// Issue #18 adds the wave, an explicit speed-variance ramp, and fare timer
/// pressure, and tunes the whole thing against the headless Monte-Carlo run
/// simulator in `run_length_simulator.dart` — the stand-in for the on-device
/// stats (issue #17) until TestFlight players generate a real history.
///
/// **The deliberate target the tuning aimed at:** the median shift lands in
/// the 2-4 km band — the middle bucket of the stats screen's run-length
/// distribution, and roughly three to six minutes of driving. The opening
/// kilometre must be nearly death-free (deaths there are luck, not
/// failure), the deep game must catch everyone by ~5 km for a
/// fixed-skill driver (deaths late are the curve working), and the wave
/// gives strong play room to stretch a run past the median. The simulator
/// batch in `test/run_length_simulation_test.dart` pins this; once
/// TestFlight players fill the on-device history, the real median is the
/// ground truth this estimate is re-checked against.
///
/// Pure logic — no Flame — so every number is unit testable.
class DifficultyCurve {
  DifficultyCurve._();

  /// Distance (px) at which the ramp to full pressure completes. Stretched
  /// from issue #11's 40,000 px by the run simulator (issue #18): the
  /// pressure a median shift must survive at its deepest lives here, and
  /// the simulator's driver only stayed ahead of the tightening when the
  /// half-pressure point moved out of the first two kilometres. Pulled back
  /// in to 52,000 px when issue #58's fault gate arrived: contacts the
  /// traffic vehicle initiated no longer cost lives (they are scrapes at
  /// most), the boxed-in-and-rammed death left the simulator's deaths, and
  /// the median shift stretched to 4.3 km — past the target band. The ramp
  /// completing 1.8 km sooner restores the 2-4 km median with the fairness
  /// profile centred (past-4 km survival back to ~one shift in six).
  static const double fullRampDistance = 52000.0;

  /// Distance (px) at which the slow post-ramp creep tops out.
  static const double creepEndDistance = 240000.0;

  /// Distance (px) between relief pulses — one pressure wave. At the
  /// starter cab's realistic pace (~110-130 px/s under traffic) a wave
  /// lasts roughly 35-45 s, so even a median-length run rides several.
  static const double waveLength = 4200.0;

  /// How deep the relief pulse dips the pressure, as a fraction of the
  /// climb: at 0.42 a trough sits at ~58% of the crest pressure at the
  /// same distance. Deep enough to feel like an exhale, shallow enough that
  /// the street is never *safe* — oncoming traffic still closes hard.
  static const double reliefDepth = 0.42;

  /// Width of the relief pulse, as a fraction of [waveLength]. The pulse is
  /// Gaussian; this is its sigma, so a pulse is half-strength (or deeper)
  /// for roughly 12% of the wavelength — about 5 s of relief, then the
  /// pressure climbs back onto the crest. Brief, by design.
  static const double reliefWidthFraction = 0.095;

  /// Distance over which the relief pulse fades in. Before this the run is
  /// a flat, gentle ramp — the opening kilometre is learnable; the rhythm
  /// is fully online well inside the target shift band, so the waves are
  /// something a normal run rides, not a veteran-only texture.
  static const double reliefOnlineDistance = 6000.0;

  // Lane geometry: the road spans x 100..300 with the centre line at 200,
  // so each half-lane is centred on these.
  static const double oncomingLaneX = 150.0;
  static const double sameDirectionLaneX = 250.0;

  // Anchor values at pressure 1.0 — issue #11's ramped and crept anchors,
  // kept as the crest targets. The distance-0 anchors match
  // TrafficPattern.light so an endless run starts as gentle as level 1.
  static const double _startInterval = 4.0;
  static const double _rampedInterval = 1.4;
  static const double _creepInterval = 1.0;

  static const double _startOncomingProbability = 0.30;
  static const double _rampedOncomingProbability = 0.85;
  static const double _creepOncomingProbability = 0.95;

  static const double _startSameDirProbability = 0.20;
  static const double _rampedSameDirProbability = 0.70;
  static const double _creepSameDirProbability = 0.85;

  // Speed is anchored as a mean plus a half-spread. Splitting the range
  // this way is what makes speed variance an explicit knob (issue #18):
  // the mean climbs with pressure (so it breathes with the wave), while the
  // spread — how unpredictable a car's speed is — climbs only with
  // distance, so deep runs stay readable but never memorisable.
  static const double _startSpeedMean = 100.0;
  static const double _rampedSpeedMean = 200.0;
  static const double _creepSpeedMean = 220.0;

  static const double _startSpeedSpread = 20.0;
  static const double _rampedSpeedSpread = 40.0;
  static const double _creepSpeedSpread = 45.0;

  /// The slow climb, without the wave: 0 at the start line, 1 at the end of
  /// the main ramp, then 1..2 over the creep. Exposed for callers that need
  /// the *envelope* rather than the lived pressure — e.g. anything that
  /// should grow monotonically and not breathe.
  static double phaseFor(double distance) {
    final ramp = rampFractionFor(distance);
    if (ramp < 1.0) return ramp;
    return 1.0 + creepFractionFor(distance);
  }

  /// Fraction (0..1) of the main ramp completed at [distance]. Exposed so
  /// other generators (e.g. fare spacing in [EndlessCourse]) can grow with
  /// the same pacing — monotonically, never breathing.
  static double rampFractionFor(double distance) =>
      _smoothstep(distance / fullRampDistance);

  /// Fraction (0..1) of the post-ramp creep completed at [distance].
  static double creepFractionFor(double distance) =>
      _smoothstep((distance - fullRampDistance) /
          (creepEndDistance - fullRampDistance));

  /// The relief pulse at [distance], 0 (no relief) to [reliefDepth] (full
  /// trough). Gaussian bumps centred every [waveLength], faded in over
  /// [reliefOnlineDistance]; smooth and periodic everywhere.
  static double reliefFor(double distance) {
    final online = _smoothstep(distance / reliefOnlineDistance);
    if (online <= 0.0) return 0.0;
    final r = distance % waveLength;
    final dr = math.min(r, waveLength - r); // wrapped distance to the pulse
    const sigma = reliefWidthFraction * waveLength;
    final pulse = math.exp(-(dr / sigma) * (dr / sigma));
    return reliefDepth * online * pulse;
  }

  /// The lived difficulty driver at [distance]: the slow climb multiplied
  /// down by the relief wave. Ranges 0 (the start line) to just under 2
  /// (the end of the creep at a wave crest); brief dips to ~65% of the
  /// local crest are the rhythm.
  ///
  /// [environmentModifier] (issue #24) is a fraction — typically
  /// [RunEnvironment.difficultyModifierAt] — by which the world at this
  /// distance (rain, fog, night) pushes the lived pressure up the *same*
  /// curve, so weather and darkness ride the one ramp instead of forming a
  /// parallel difficulty system. Zero (the default) is the bare curve.
  static double pressureFor(double distance,
          {double environmentModifier = 0.0}) =>
      phaseFor(distance) *
      (1.0 - reliefFor(distance)) *
      (1.0 + environmentModifier);

  /// Fare timer pressure at [distance], 0..1 — the input
  /// [FareChain.startFare] tightens its countdown budgets by. 0 is the
  /// forgiving level-1 budget; 1 is the fully tightened deep-run budget.
  /// It reaches 1 at the end of the main ramp (crest) and breathes back to
  /// ~0.65 in each relief trough, so the meter eases off in the lulls too.
  /// [environmentModifier] folds the world's mood (issue #24) into the
  /// meter: rain, fog, and night all shorten the countdown the same way
  /// they thicken the traffic.
  static double farePressureFor(double distance,
          {double environmentModifier = 0.0}) =>
      pressureFor(distance, environmentModifier: environmentModifier)
          .clamp(0.0, 1.0);

  /// The curve's raw pressure read at [distance]: interval, speeds, and
  /// per-side probabilities, before any road geometry is applied.
  static TrafficCore trafficCoreFor(double distance,
      {double environmentModifier = 0.0}) {
    // The lived pressure breathes density and mean speed together...
    final pressure =
        pressureFor(distance, environmentModifier: environmentModifier);
    // ...while speed variance climbs only with distance, so deep traffic
    // stays unpredictable through the lulls as well as the crests. The
    // environment modifier pushes variance too — foul weather and night
    // make traffic less predictable, not just denser.
    final variance =
        phaseFor(distance) * (1.0 + environmentModifier);

    final meanSpeed = _lerpAnchors(
        _startSpeedMean, _rampedSpeedMean, _creepSpeedMean, pressure);
    final halfSpread = _lerpAnchors(
        _startSpeedSpread, _rampedSpeedSpread, _creepSpeedSpread, variance);

    return TrafficCore(
      spawnInterval: _lerpAnchors(
          _startInterval, _rampedInterval, _creepInterval, pressure),
      meanSpeed: meanSpeed,
      halfSpread: halfSpread,
      oncomingProbability: _lerpAnchors(
          _startOncomingProbability,
          _rampedOncomingProbability,
          _creepOncomingProbability,
          pressure),
      sameDirectionProbability: _lerpAnchors(
          _startSameDirProbability,
          _rampedSameDirProbability,
          _creepSameDirProbability,
          pressure),
    );
  }

  /// The traffic profile in effect at [distance] px into the run, laid out
  /// on the classic two-lane street. The environment-aware layer
  /// ([RunEnvironment.trafficAt]) lays the same read onto whatever road is
  /// actually there.
  static TrafficProfile trafficForDistance(double distance,
      {double environmentModifier = 0.0}) {
    final core = trafficCoreFor(distance,
        environmentModifier: environmentModifier);
    final speedRange = SpeedRange(
      min: core.meanSpeed - core.halfSpread,
      max: core.meanSpeed + core.halfSpread,
    );

    return TrafficProfile(
      spawnInterval: core.spawnInterval,
      lanes: [
        TrafficLaneConfig(
          laneX: oncomingLaneX,
          speedRange: speedRange,
          spawnProbability: core.oncomingProbability,
          oncoming: true,
        ),
        TrafficLaneConfig(
          laneX: sameDirectionLaneX,
          speedRange: speedRange,
          spawnProbability: core.sameDirectionProbability,
          oncoming: false,
        ),
      ],
    );
  }

  static double _smoothstep(double t) {
    final c = t.clamp(0.0, 1.0).toDouble();
    return c * c * (3 - 2 * c);
  }

  /// Anchor interpolation along the climb: [a] at pressure 0, [b] at
  /// pressure 1 (end of the main ramp), [c] at pressure 2 (end of the
  /// creep). [t] may breathe below its un-waved phase — the whole point of
  /// issue #18 — and the result stays inside the anchor bounds.
  static double _lerpAnchors(double a, double b, double c, double t) {
    final ramp = t.clamp(0.0, 1.0).toDouble();
    final creep = (t - 1.0).clamp(0.0, 1.0).toDouble();
    return a + (b - a) * ramp + (c - b) * creep;
  }
}
