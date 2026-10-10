import '../game/systems/run_summary.dart';
import 'run_record.dart';

/// The player's lifetime shift totals (issue #183): the six numbers the
/// stats screen's "Totals" card shows — shifts ended, total score,
/// distance driven, fares delivered, lives lost, time driven — counted
/// over *every* shift that has ever ended, not over the shift history.
///
/// The history is a fixed window ([GameStateService.maxRecordedRuns]
/// trims it at 200 shifts), and the Totals used to be folded straight
/// over it: past 200 shifts "Shifts ended" froze at the window size, and
/// the summed rows could even fall — a big old shift aging out while a
/// small new one arrived took the "Fares delivered" and "Time driven"
/// numbers *down*. These counters are the fix, in the same shape as the
/// clean-bank counter before them (issue #55): *stored*, not queried over
/// the window, and monotone — each counter only ever moves up, one
/// shift's non-negative contribution at a time, so no trim can take a
/// shift back out of them. They never go down except through an explicit
/// [GameStateService.resetProgress].
///
/// Pure data with a JSON round-trip, matching [SaveData]'s persistence
/// style. Fields are superset-safe: reading a save written by an older
/// build defaults missing keys rather than throwing.
class LifetimeRunTotals {
  /// Every shift that has ever ended, banked or wrecked.
  int shiftsEnded;

  /// Every shift's final score added up, banked or forfeited.
  int totalScore;

  /// Every shift's distance added up, in world px — the same scale
  /// [RunRecord.distancePx] and the HUD's distance badge use.
  double totalDistancePx;

  /// Fares delivered across every shift.
  int totalFares;

  /// Lives lost across every shift.
  int totalLivesLost;

  /// Drive time across every shift, in seconds.
  double totalDurationSeconds;

  /// Accepted and declined fare counts by kind (issue #279), keyed by
  /// `FareType.name` — the same keys [RunRecord] stores. Folded like the
  /// six counters above, so the per-kind answer history survives the
  /// window trim exactly as the totals do.
  Map<String, int> acceptedFaresByKind;
  Map<String, int> declinedFaresByKind;

  LifetimeRunTotals({
    this.shiftsEnded = 0,
    this.totalScore = 0,
    this.totalDistancePx = 0.0,
    this.totalFares = 0,
    this.totalLivesLost = 0,
    this.totalDurationSeconds = 0.0,
    Map<String, int>? acceptedFaresByKind,
    Map<String, int>? declinedFaresByKind,
  })  : acceptedFaresByKind = acceptedFaresByKind ?? <String, int>{},
        declinedFaresByKind = declinedFaresByKind ?? <String, int>{};

  /// The lifetime distance in metres, on the same px scale
  /// [RunSummary.pixelsPerMetre] and the HUD's distance badge use — one
  /// constant referenced, never duplicated.
  double get totalDistanceMetres =>
      totalDistancePx / RunSummary.pixelsPerMetre;

  /// Folds one ended shift into the counters (issue #183). Every
  /// contribution is non-negative, so every counter only ever moves up —
  /// the property that makes the totals immune to the history window's
  /// trim, which is the whole point of them.
  void applyRun(RunRecord record) {
    shiftsEnded++;
    totalScore += record.score;
    totalDistancePx += record.distancePx;
    totalFares += record.faresDelivered;
    totalLivesLost += record.livesLost;
    totalDurationSeconds += record.durationSeconds;
    _foldCounts(acceptedFaresByKind, record.acceptedByKind);
    _foldCounts(declinedFaresByKind, record.declinedByKind);
  }

  /// The one-time migration seed (issue #183), in the clean-bank
  /// counter's shape (issue #55): saves written before these totals
  /// existed store nothing, and their only record of anything is the
  /// history window. Each counter takes the larger of what is stored and
  /// what the window holds — per field, so a save that somehow holds a
  /// *smaller* number than its window still keeps everything the window
  /// shows, and a save that holds more (post-migration: the window only
  /// ever holds a subset of a lifetime) keeps its own number. Returns
  /// true when any counter moved, so the caller persists the seed before
  /// the window can trim a shift out from under it.
  bool seedFromWindow(List<RunRecord> window) {
    var seeded = false;
    if (window.length > shiftsEnded) {
      shiftsEnded = window.length;
      seeded = true;
    }
    final windowScore = window.fold(0, (sum, r) => sum + r.score);
    if (windowScore > totalScore) {
      totalScore = windowScore;
      seeded = true;
    }
    final windowDistancePx = window.fold(0.0, (sum, r) => sum + r.distancePx);
    if (windowDistancePx > totalDistancePx) {
      totalDistancePx = windowDistancePx;
      seeded = true;
    }
    final windowFares = window.fold(0, (sum, r) => sum + r.faresDelivered);
    if (windowFares > totalFares) {
      totalFares = windowFares;
      seeded = true;
    }
    final windowLivesLost = window.fold(0, (sum, r) => sum + r.livesLost);
    if (windowLivesLost > totalLivesLost) {
      totalLivesLost = windowLivesLost;
      seeded = true;
    }
    final windowDurationSeconds =
        window.fold(0.0, (sum, r) => sum + r.durationSeconds);
    if (windowDurationSeconds > totalDurationSeconds) {
      totalDurationSeconds = windowDurationSeconds;
      seeded = true;
    }
    if (_seedCounts(acceptedFaresByKind, window, (r) => r.acceptedByKind)) {
      seeded = true;
    }
    if (_seedCounts(declinedFaresByKind, window, (r) => r.declinedByKind)) {
      seeded = true;
    }
    return seeded;
  }

  /// Load from JSON. Missing keys — saves written before issue #183 —
  /// fall back to "no shift has ever ended", never throw.
  factory LifetimeRunTotals.fromJson(Map<String, dynamic> json) {
    return LifetimeRunTotals(
      shiftsEnded: (json['shiftsEnded'] as num?)?.toInt() ?? 0,
      totalScore: (json['totalScore'] as num?)?.toInt() ?? 0,
      totalDistancePx: (json['totalDistancePx'] as num?)?.toDouble() ?? 0.0,
      totalFares: (json['totalFares'] as num?)?.toInt() ?? 0,
      totalLivesLost: (json['totalLivesLost'] as num?)?.toInt() ?? 0,
      totalDurationSeconds:
          (json['totalDurationSeconds'] as num?)?.toDouble() ?? 0.0,
      acceptedFaresByKind: _countsFromJson(json['acceptedFaresByKind']),
      declinedFaresByKind: _countsFromJson(json['declinedFaresByKind']),
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'shiftsEnded': shiftsEnded,
      'totalScore': totalScore,
      'totalDistancePx': totalDistancePx,
      'totalFares': totalFares,
      'totalLivesLost': totalLivesLost,
      'totalDurationSeconds': totalDurationSeconds,
      'acceptedFaresByKind': acceptedFaresByKind,
      'declinedFaresByKind': declinedFaresByKind,
    };
  }

  /// Adds one record's per-kind counts into [into] (issue #279).
  static void _foldCounts(Map<String, int> into, Map<String, int> from) {
    from.forEach((kind, count) {
      into[kind] = (into[kind] ?? 0) + count;
    });
  }

  /// Seeds one per-kind count map from the window, per key: the stored
  /// number wins unless the window holds a larger one — the same
  /// "nothing falls" rule as every counter above. Returns true when any
  /// key moved.
  static bool _seedCounts(
    Map<String, int> stored,
    List<RunRecord> window,
    Map<String, int> Function(RunRecord) countsOf,
  ) {
    final windowCounts = <String, int>{};
    for (final record in window) {
      _foldCounts(windowCounts, countsOf(record));
    }
    var moved = false;
    windowCounts.forEach((kind, count) {
      if (count > (stored[kind] ?? 0)) {
        stored[kind] = count;
        moved = true;
      }
    });
    return moved;
  }
}

/// Decodes a stored per-kind count map (issue #279): entries that are
/// not name-to-number pairs are dropped rather than thrown, the same
/// forgiving rule the counters above follow.
Map<String, int> _countsFromJson(Object? json) {
  if (json is! Map) return const {};
  final counts = <String, int>{};
  json.forEach((key, value) {
    if (key is String && value is num) counts[key] = value.toInt();
  });
  return counts;
}
