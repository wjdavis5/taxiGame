import '../game/vehicle_sprites.dart';

/// The recorded position trace of the best Daily Shift run (issue #20).
///
/// With no leaderboards, the daily's competitive hook is the player's own
/// ghost: the best run on one day's shared course is recorded here and
/// replayed as a translucent car on later runs of the **same** course. A
/// ghost only means something on a deterministic course — the daily's
/// date-seeded course is the only one the game has (issue #19). Endless
/// free play is freshly seeded every shift, so a trace recorded there
/// would compare two different roads; it never records one and never
/// shows one.
///
/// Exactly one trace is stored, under its own prefs key. A trace from an
/// earlier day is permanently meaningless — that course never returns —
/// so the first trace recorded on a new day replaces it outright, which
/// also bounds the save payload at one trace forever.
///
/// Pure data with a JSON round-trip, matching [DailyResult]'s persistence
/// style. Fields are superset-safe: reading a trace written by an older
/// build defaults missing keys rather than throwing.
class GhostTrace {
  const GhostTrace({
    required this.dateKey,
    required this.score,
    required this.banked,
    required this.vehicleId,
    required this.samples,
    this.samplePeriodSeconds = samplePeriod,
  });

  /// Seconds of driven time between samples. Stored per trace so an
  /// older trace keeps replaying at its own grid if this constant ever
  /// changes.
  static const double samplePeriod = 0.2;

  /// Sample-pair cap (issue #20's "keep the trace small"): at
  /// [samplePeriod] this covers 8 minutes of driving — far past any
  /// daily shift — and bounds the stored payload at roughly 25 KB. The
  /// recorder simply stops past it; the ghost then stops where its
  /// recording did.
  static const int maxSamples = 2400;

  /// The day the run was played, as a 'yyyy-MM-dd' date key — the same
  /// key its shared course was seeded from. This is the trace's
  /// identity: the ghost is only ever shown on the course of this day.
  final String dateKey;

  /// The run's final fare-chain score — the bar a later run must clear
  /// to replace this trace as the ghost.
  final int score;

  /// True when the run ended in a bank; false when the third crash
  /// wrecked it. Informational, like [DailyResult.banked].
  final bool banked;

  /// Save-data id of the vehicle that set the trace, so the ghost
  /// renders the same car that drove it. Unknown ids fall back to the
  /// default sprite at render time, never an error.
  final String vehicleId;

  /// The path, as flat pairs `[x0, y0, x1, y1, ...]` in whole world px,
  /// sampled every [samplePeriodSeconds] of *driven* time — the clock
  /// that freezes through crash hit-stops and stalls, so the replay
  /// measures driving, not dead time. Whole-pixel precision is plenty
  /// for a translucent after-image; the replay interpolates between
  /// samples.
  final List<int> samples;

  /// The grid this trace was sampled on, in seconds. Defaults to
  /// [samplePeriod]; stored per trace so an older trace keeps replaying
  /// at its own grid if the default ever changes.
  final double samplePeriodSeconds;

  /// How many (x, y) pairs the trace holds. A trailing stray value from
  /// a corrupt write is ignored rather than thrown.
  int get sampleCount => samples.length ~/ 2;

  /// The driven time the trace covers, in seconds.
  double get coveredSeconds =>
      sampleCount > 0 ? (sampleCount - 1) * samplePeriodSeconds : 0.0;

  /// Load from JSON. Missing keys — traces written by an older build —
  /// fall back to the value that trace would have had, never throw: one
  /// unreadable trace must not break the save.
  factory GhostTrace.fromJson(Map<String, dynamic> json) {
    return GhostTrace(
      dateKey: (json['dateKey'] as String?) ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      banked: (json['banked'] as bool?) ?? false,
      vehicleId:
          (json['vehicleId'] as String?) ?? VehicleSprites.defaultVehicleId,
      samples: (json['samples'] as List? ?? const [])
          .map((px) => (px as num).toInt())
          .toList(),
      samplePeriodSeconds:
          (json['samplePeriodSeconds'] as num?)?.toDouble() ?? samplePeriod,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'dateKey': dateKey,
      'score': score,
      'banked': banked,
      'vehicleId': vehicleId,
      'samples': samples,
      'samplePeriodSeconds': samplePeriodSeconds,
    };
  }
}
