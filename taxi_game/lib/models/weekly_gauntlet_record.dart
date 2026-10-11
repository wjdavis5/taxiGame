import 'dart:math' as math;

/// The on-device best of one Weekly Gauntlet week (issue #288).
///
/// One record, holding the current week's best per measured surface. The
/// week key is the record's identity: a run from a later week replaces
/// the whole record — a new week starts over — while a run from an older
/// week is ignored, so a clock walked backward cannot overwrite the
/// current week's best with a stale run. Inside one week each field is a
/// stored maximum, never lowered.
///
/// Pure data with a JSON round-trip, matching [DailyStreak]'s persistence
/// style. Fields are superset-safe: reading a record written by an older
/// build defaults missing keys rather than throwing.
class WeeklyGauntletRecord {
  const WeeklyGauntletRecord({
    this.weekKey = '',
    this.bestScore = 0,
    this.bestFares = 0,
    this.bestChain = 0,
    this.bestDistanceMetres = 0,
  });

  /// The 'yyyy-Www' week these bests belong to. Empty until the first
  /// gauntlet run is ever recorded — the shape a save written before the
  /// gauntlet existed loads with.
  final String weekKey;

  /// The best fare-chain score of the week, banked or forfeited.
  final int bestScore;

  /// The most fares delivered in one run of the week.
  final int bestFares;

  /// The best chain multiplier reached in one run of the week.
  final int bestChain;

  /// The furthest one run of the week drove, in metres.
  final int bestDistanceMetres;

  /// The record after a run on [weekKey]. A run for the record's own week
  /// folds in per field, keeping each maximum; a run for a later week
  /// replaces the record outright; a run for an earlier week is ignored
  /// and the identical instance is returned, so callers can skip a save.
  WeeklyGauntletRecord afterRun({
    required String weekKey,
    required int score,
    required int fares,
    required int bestChain,
    required int distanceMetres,
  }) {
    final comparison = weekKey.compareTo(this.weekKey);
    if (this.weekKey.isNotEmpty && comparison < 0) return this;
    if (comparison > 0) {
      return WeeklyGauntletRecord(
        weekKey: weekKey,
        bestScore: score,
        bestFares: fares,
        bestChain: bestChain,
        bestDistanceMetres: distanceMetres,
      );
    }
    final next = WeeklyGauntletRecord(
      weekKey: weekKey,
      bestScore: math.max(bestScore, score),
      bestFares: math.max(bestFares, fares),
      bestChain: math.max(this.bestChain, bestChain),
      bestDistanceMetres:
          math.max(bestDistanceMetres, distanceMetres),
    );
    return next == this ? this : next;
  }

  /// Load from JSON. Missing keys — a block written by an older build —
  /// fall back to the value a fresh record would have, never throw: one
  /// unreadable block must not lose the whole save.
  factory WeeklyGauntletRecord.fromJson(Map<String, dynamic> json) {
    return WeeklyGauntletRecord(
      weekKey: (json['weekKey'] as String?) ?? '',
      bestScore: (json['bestScore'] as num?)?.toInt() ?? 0,
      bestFares: (json['bestFares'] as num?)?.toInt() ?? 0,
      bestChain: (json['bestChain'] as num?)?.toInt() ?? 0,
      bestDistanceMetres:
          (json['bestDistanceMetres'] as num?)?.toInt() ?? 0,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'weekKey': weekKey,
      'bestScore': bestScore,
      'bestFares': bestFares,
      'bestChain': bestChain,
      'bestDistanceMetres': bestDistanceMetres,
    };
  }

  /// Field-wise equality, so [afterRun] can report "nothing changed" by
  /// returning the same instance.
  @override
  bool operator ==(Object other) =>
      other is WeeklyGauntletRecord &&
      other.weekKey == weekKey &&
      other.bestScore == bestScore &&
      other.bestFares == bestFares &&
      other.bestChain == bestChain &&
      other.bestDistanceMetres == bestDistanceMetres;

  @override
  int get hashCode => Object.hash(
        weekKey,
        bestScore,
        bestFares,
        bestChain,
        bestDistanceMetres,
      );
}
