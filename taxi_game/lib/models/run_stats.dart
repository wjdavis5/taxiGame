import 'lifetime_run_totals.dart';
import 'run_record.dart';

/// Aggregates a history of ended shifts into the tuning view (issue #17).
///
/// The game is fully offline — no analytics, no funnels — so this is the
/// only instrument the difficulty curve (#18) and the chain economy get
/// tuned against: totals across every recorded shift, the medians that say
/// what a *typical* shift looks like (means lie when one 4 km outlier sits
/// next to a pile of first-crash wrecks), the distribution of run lengths,
/// and the bank-vs-push ratio that says whether the banking pressure of
/// issue #13 actually bites.
///
/// Since issue #183 the six Totals read the lifetime counters the caller
/// passes in ([LifetimeRunTotals], stored in the save): the history is a
/// fixed window that trims at 200 shifts, and totals folded over that
/// window froze at 200 and then fell as old shifts aged out. The medians,
/// the run-length bands and the bank-vs-push counts stay window-scoped —
/// they describe recent shifts — with [runCount] the window's own size,
/// because it is the denominator of [bankedShare] and the bands'
/// fractions, and a share of window counts over a lifetime count is not
/// any ratio at all. A compute without lifetime totals folds the window
/// for everything, exactly as it always did.
///
/// Pure computation over [RunRecord]s — no Flutter, no I/O — so every
/// number is unit testable, matching [FareChain] and [LivesTracker].
class RunStats {
  RunStats._({
    required this.runCount,
    required this.shiftsEnded,
    required this.totalScore,
    required this.totalDistanceMetres,
    required this.totalFares,
    required this.totalLivesLost,
    required this.totalDurationSeconds,
    required this.medianScore,
    required this.medianDistanceMetres,
    required this.medianDurationSeconds,
    required this.medianLifeLossDistanceMetres,
    required this.bankedCount,
    required this.forfeitedCount,
    required this.runLengthDistribution,
  });

  /// Aggregates [records], oldest first (order only matters for the
  /// medians, which sort anyway). An empty history is a valid, all-zero
  /// result — a fresh install before the first shift ends.
  ///
  /// [lifetime], when the caller has it, supplies the six Totals rows
  /// (issue #183); everything else always reads the window.
  factory RunStats.compute(List<RunRecord> records,
      {LifetimeRunTotals? lifetime}) {
    final distances = records.map((r) => r.distanceMetres).toList();
    final lifeLosses = <double>[];
    var banked = 0;
    for (final record in records) {
      lifeLosses.addAll(record.lifeLossDistancesMetres);
      if (record.banked) banked++;
    }

    return RunStats._(
      runCount: records.length,
      shiftsEnded: lifetime?.shiftsEnded ?? records.length,
      totalScore:
          lifetime?.totalScore ?? records.fold(0, (sum, r) => sum + r.score),
      totalDistanceMetres: lifetime?.totalDistanceMetres ??
          distances.fold(0.0, (sum, m) => sum + m),
      totalFares: lifetime?.totalFares ??
          records.fold(0, (sum, r) => sum + r.faresDelivered),
      totalLivesLost: lifetime?.totalLivesLost ?? lifeLosses.length,
      totalDurationSeconds: lifetime?.totalDurationSeconds ??
          records.fold(0.0, (sum, r) => sum + r.durationSeconds),
      medianScore: _median(records.map((r) => r.score.toDouble()).toList()),
      medianDistanceMetres: _median(distances),
      medianDurationSeconds:
          _median(records.map((r) => r.durationSeconds).toList()),
      medianLifeLossDistanceMetres: _median(lifeLosses),
      bankedCount: banked,
      forfeitedCount: records.length - banked,
      runLengthDistribution: _distribution(distances),
    );
  }

  /// How many shifts the history window holds — the denominator of
  /// [bankedShare] and the run-length fractions, and deliberately not the
  /// lifetime count: those shares are over window-scoped counts.
  final int runCount;

  // --- Totals -------------------------------------------------------------

  /// Every shift that has ever ended — the "Shifts ended" row. The
  /// lifetime counter (issue #183) when [LifetimeRunTotals] was passed
  /// in; the window's own count otherwise. Deliberately not [runCount]:
  /// the window trims at 200 shifts, and a "Shifts ended" that stops
  /// there is the bug this field exists to end.
  final int shiftsEnded;

  /// Every shift's final score added up — lifetime (issue #183) when the
  /// caller passed the counters in, the window's sum otherwise.
  final int totalScore;

  /// Every shift's distance added up, in metres — lifetime (issue #183)
  /// when the caller passed the counters in, the window's sum otherwise.
  final double totalDistanceMetres;

  /// Fares delivered across all shifts — lifetime (issue #183) when the
  /// caller passed the counters in, the window's sum otherwise. This row
  /// is one the window used to send *down*: a fare-heavy old shift aging
  /// out while a quiet new one arrived.
  final int totalFares;

  /// Lives lost across all shifts — crashes survived into a stall count;
  /// only the ones that cost a life do. Lifetime (issue #183) when the
  /// caller passed the counters in, the window's count otherwise.
  final int totalLivesLost;

  /// Drive time across all shifts, in seconds (each record's
  /// [RunRecord.durationSeconds] summed) — lifetime (issue #183) when the
  /// caller passed the counters in, the window's sum otherwise. Another
  /// row the window could send down, the same way as [totalFares].
  final double totalDurationSeconds;

  // --- Medians: what a typical shift looks like ---------------------------

  /// The middle shift's score; null with no history.
  final double? medianScore;

  /// The middle shift's distance, in metres; null with no history.
  final double? medianDistanceMetres;

  /// The middle shift's drive time, in seconds; null with no history.
  final double? medianDurationSeconds;

  /// The middle value across every life ever lost — how far into a shift
  /// the typical crash lands. Null when no life was ever lost: the median
  /// of nothing is a question, not zero.
  final double? medianLifeLossDistanceMetres;

  // --- Bank vs push -------------------------------------------------------

  /// Shifts that ended in a bank at a dropoff.
  final int bankedCount;

  /// Shifts that ended wrecked, score forfeited.
  final int forfeitedCount;

  /// Fraction of ended shifts that banked, 0..1 — 0 with no history. The
  /// bank-vs-push ratio: near 0 means players die holding unbanked score,
  /// near 1 means the bank is so safe it is always taken.
  double get bankedShare =>
      runCount == 0 ? 0.0 : bankedCount / runCount;

  // --- Run-length distribution -------------------------------------------

  /// One bucket per distance band, in fixed order, with the count of
  /// shifts that landed in it. The shape of the whole history at a glance:
  /// tuning watches the mass migrate right as the curve eases.
  final List<RunLengthBucket> runLengthDistribution;

  /// True when there is nothing at all to show — the stats screen's empty
  /// state. The window is empty *and* the lifetime totals read zero
  /// (issue #249): a corrupt or lost history recovers to an empty window
  /// while the save keeps [shiftsEnded] and the rest of its lifetime
  /// counters, and gating the screen on [runCount] alone hid those totals
  /// behind "No shifts recorded yet". A fresh install — nothing in either
  /// — is still the empty state.
  bool get isEmpty => runCount == 0 && shiftsEnded == 0;

  // --- Formatting (shared with the stats screen) --------------------------

  /// Distance in race-telemetry units: metres under a kilometre,
  /// kilometres above — the same shape as the run-summary distance label.
  static String formatDistance(double metres) {
    return metres >= 1000
        ? '${(metres / 1000).toStringAsFixed(1)} km'
        : '${metres.round()} m';
  }

  /// Duration as a clock: m:ss under an hour, h:mm:ss above.
  static String formatDuration(double seconds) {
    final total = seconds.round();
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final secs = total % 60;
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${twoDigits(minutes)}:${twoDigits(secs)}'
        : '$minutes:${twoDigits(secs)}';
  }

  /// Median of [values]; null when empty. An even count takes the mean of
  /// the two middle values — the honest midpoint.
  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = List<double>.of(values)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  static List<RunLengthBucket> _distribution(List<double> distancesMetres) {
    return RunLengthBucket.bounds
        .map((bounds) => RunLengthBucket._(
              label: bounds.label,
              minMetres: bounds.minMetres,
              maxMetres: bounds.maxMetres,
              count: distancesMetres.where(bounds.contains).length,
            ))
        .toList();
  }
}

/// One distance band in [RunStats.runLengthDistribution].
class RunLengthBucket {
  const RunLengthBucket._({
    required this.label,
    required this.minMetres,
    required this.maxMetres,
    required this.count,
  });

  /// The fixed bands, in display order. Five bands span the life of the
  /// stat: a first-crash wreck (~a hundred-odd metres) to a veteran bank.
  /// Band edges are metres: [min, max), the last open-ended.
  static const bounds = <_BucketBounds>[
    _BucketBounds('Under 500 m', 0, 500),
    _BucketBounds('500 m – 1 km', 500, 1000),
    _BucketBounds('1 – 2 km', 1000, 2000),
    _BucketBounds('2 – 4 km', 2000, 4000),
    _BucketBounds('Over 4 km', 4000, null),
  ];

  final String label;

  /// Inclusive lower edge of the band, in metres.
  final double minMetres;

  /// Exclusive upper edge, in metres — null for the open-ended top band.
  final double? maxMetres;

  /// Shifts whose distance landed in this band.
  final int count;

  /// The band's share of all recorded shifts, 0..1 — raw material for the
  /// distribution bar. Guarded by the caller's runCount > 0.
  double fractionOf(int runCount) =>
      runCount == 0 ? 0.0 : (count / runCount).clamp(0.0, 1.0);
}

/// The immutable definition of a distance band.
class _BucketBounds {
  const _BucketBounds(this.label, this.minMetres, this.maxMetres);

  final String label;
  final double minMetres;
  final double? maxMetres;

  bool contains(double metres) {
    final max = maxMetres;
    return metres >= minMetres && (max == null || metres < max);
  }
}
