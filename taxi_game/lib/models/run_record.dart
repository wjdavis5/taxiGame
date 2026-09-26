import '../game/systems/run_summary.dart';

/// The on-device record of one ended endless shift (issue #17).
///
/// The game ships with no analytics — nothing networked exists to tune the
/// difficulty curve or the chain economy against — so every ended shift is
/// written to local storage instead, and [RunStats] aggregates the history
/// for the stats screen. One record is exactly the raw material of one data
/// point: what the run earned, how far it went, where its lives went, and
/// how it ended.
///
/// Pure data with a JSON round-trip, matching [SaveData]'s persistence
/// style. Fields are a superset-safe: reading a record written by an older
/// build defaults missing keys rather than throwing.
class RunRecord {
  const RunRecord({
    required this.endedAtMs,
    required this.distancePx,
    required this.score,
    required this.faresDelivered,
    required this.longestChain,
    required this.livesLost,
    required this.lifeLossDistancesPx,
    required this.banked,
    required this.durationSeconds,
  });

  /// When the shift ended, in epoch milliseconds. Not used by the
  /// aggregates; it orders the history and identifies records when
  /// debugging tuning data on a device.
  final int endedAtMs;

  /// How far the taxi drove, in world px — the HUD's distance scale.
  final double distancePx;

  /// The shift's final fare-chain score, banked or forfeited (the same
  /// number the run-summary panel shows).
  final int score;

  /// Fares delivered over the whole shift.
  final int faresDelivered;

  /// The highest the chain multiplier reached — the run's longest chain.
  final int longestChain;

  /// Lives the shift lost to crashes (0 for a clean bank, up to 3 for a
  /// wreck).
  final int livesLost;

  /// How far into the shift each life was lost, in world px, in the order
  /// they were lost — the "where" of [livesLost]. Length always equals
  /// [livesLost].
  final List<double> lifeLossDistancesPx;

  /// True when the shift ended in a bank at a dropoff; false when the
  /// third crash wrecked it and forfeited the unbanked score. The raw
  /// material of the bank-vs-push ratio.
  final bool banked;

  /// Seconds the shift was actually being driven: world-update time while
  /// the run was live. Crash hit-stops and stalls are excluded, so this
  /// measures driving, not dead time.
  final double durationSeconds;

  /// The run's distance in metres, on the same px scale
  /// [RunSummary.pixelsPerMetre] and the HUD's distance badge use — one
  /// constant referenced, never duplicated.
  double get distanceMetres => distancePx / RunSummary.pixelsPerMetre;

  /// The recorded life-loss positions in metres, in loss order.
  List<double> get lifeLossDistancesMetres => List.unmodifiable(
        lifeLossDistancesPx.map((px) => px / RunSummary.pixelsPerMetre),
      );

  /// Load from JSON. Missing keys — records written by an older build —
  /// fall back to the value that record would have had, never throw: one
  /// unreadable record must not lose the whole history.
  factory RunRecord.fromJson(Map<String, dynamic> json) {
    return RunRecord(
      endedAtMs: (json['endedAtMs'] as num?)?.toInt() ?? 0,
      distancePx: (json['distancePx'] as num?)?.toDouble() ?? 0.0,
      score: (json['score'] as num?)?.toInt() ?? 0,
      faresDelivered: (json['faresDelivered'] as num?)?.toInt() ?? 0,
      longestChain: (json['longestChain'] as num?)?.toInt() ?? 1,
      livesLost: (json['livesLost'] as num?)?.toInt() ?? 0,
      lifeLossDistancesPx: (json['lifeLossDistancesPx'] as List? ?? const [])
          .map((px) => (px as num).toDouble())
          .toList(),
      banked: (json['banked'] as bool?) ?? false,
      durationSeconds: (json['durationSeconds'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'endedAtMs': endedAtMs,
      'distancePx': distancePx,
      'score': score,
      'faresDelivered': faresDelivered,
      'longestChain': longestChain,
      'livesLost': livesLost,
      'lifeLossDistancesPx': lifeLossDistancesPx,
      'banked': banked,
      'durationSeconds': durationSeconds,
    };
  }
}
