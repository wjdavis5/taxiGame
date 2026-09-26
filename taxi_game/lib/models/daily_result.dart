/// The on-device record of one completed Daily Shift (issue #19).
///
/// The daily's comparison is social — players screenshot their score — so
/// this record exists for the player: it is what today's result and the
/// daily history on the menu show. One entry per calendar day, written
/// when that day's shift ends; the first result for a day is the one that
/// counts, and the data layer enforces it (see
/// `GameStateService.recordDailyResult`).
///
/// Pure data with a JSON round-trip, matching [RunRecord]'s persistence
/// style. Fields are superset-safe: reading a result written by an older
/// build defaults missing keys rather than throwing.
class DailyResult {
  const DailyResult({
    required this.dateKey,
    required this.score,
    required this.banked,
    required this.completedAtMs,
  });

  /// The day the shift was played, as a 'yyyy-MM-dd' date key — the same
  /// key the shared course was seeded from. This is the record's identity:
  /// one result per key, ever.
  final String dateKey;

  /// The shift's final fare-chain score — the number a screenshot shares.
  /// The same number whether the shift banked its payout or died trying.
  final int score;

  /// True when the shift ended in a bank at a dropoff; false when the
  /// third crash wrecked it and the score went unbanked to the grave.
  final bool banked;

  /// When the shift ended, in epoch milliseconds. Purely informational —
  /// orders same-day replays in debugging the way [RunRecord.endedAtMs]
  /// does for the shift history.
  final int completedAtMs;

  /// Load from JSON. Missing keys — results written by an older build —
  /// fall back to the value that result would have had, never throw: one
  /// unreadable result must not lose the whole daily history.
  factory DailyResult.fromJson(Map<String, dynamic> json) {
    return DailyResult(
      dateKey: (json['dateKey'] as String?) ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      banked: (json['banked'] as bool?) ?? false,
      completedAtMs: (json['completedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'dateKey': dateKey,
      'score': score,
      'banked': banked,
      'completedAtMs': completedAtMs,
    };
  }
}
