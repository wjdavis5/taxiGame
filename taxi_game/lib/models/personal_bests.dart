import '../game/systems/run_summary.dart';

/// The player's lifetime records (issue #21).
///
/// With no leaderboards anywhere in the app, these four numbers are the
/// standing answer to "how good am I": the highest score a shift ever
/// paid out at a bank, the longest fare chain ever ridden in one shift,
/// the furthest one shift has driven, and the most fares delivered in
/// one shift.
///
/// They are *stored maxima*, not queries over the shift history: the
/// history is a fixed window (issue #17 trims it at 200 shifts), and a
/// record that regresses because an old shift fell off the front of a
/// list is not a record. Once set, a personal best never goes down —
/// except through an explicit reset in [GameStateService.resetProgress].
///
/// `bestBankedScore` is deliberately banked-only. The headline best the
/// menu shows ([SaveData.endlessBestScore], issue #15) counts a wrecked
/// shift's forfeited score too, because that is the number a replay
/// tries to beat; this one only counts score that actually reached the
/// wallet, because a record of money never earned is a lie.
///
/// Pure data with a JSON round-trip, matching [SaveData]'s persistence
/// style. Fields are superset-safe: reading a save written by an older
/// build defaults missing keys rather than throwing.
class PersonalBests {
  /// The highest score any shift has ended with *as a bank* — the moment
  /// the chain score became coins. A wrecked shift, however big its
  /// forfeited score, never touches this.
  int bestBankedScore;

  /// The highest the fare-chain multiplier has ever reached within one
  /// shift — the "best chain" line on the run summary, held across all
  /// shifts.
  int longestChain;

  /// How far the furthest single shift has driven, in world px — the
  /// same scale [RunRecord.distancePx] and the HUD's distance badge use.
  double furthestDistancePx;

  /// The most fares ever delivered within one shift.
  int mostFaresInOneShift;

  PersonalBests({
    this.bestBankedScore = 0,
    this.longestChain = 0,
    this.furthestDistancePx = 0.0,
    this.mostFaresInOneShift = 0,
  });

  /// The furthest single shift in metres, on the same px scale
  /// [RunSummary.pixelsPerMetre] and the HUD's distance badge use — one
  /// constant referenced, never duplicated.
  double get furthestDistanceMetres =>
      furthestDistancePx / RunSummary.pixelsPerMetre;

  /// Folds one ended shift into the records. Every field is a running
  /// maximum; returns true when this shift set at least one new record.
  bool applyRun({
    required int score,
    required bool banked,
    required int longestChain,
    required double distancePx,
    required int faresDelivered,
  }) {
    var improved = false;
    // Only a bank pays out, so only a bank can set the banked record.
    if (banked && score > bestBankedScore) {
      bestBankedScore = score;
      improved = true;
    }
    if (longestChain > this.longestChain) {
      this.longestChain = longestChain;
      improved = true;
    }
    if (distancePx > furthestDistancePx) {
      furthestDistancePx = distancePx;
      improved = true;
    }
    if (faresDelivered > mostFaresInOneShift) {
      mostFaresInOneShift = faresDelivered;
      improved = true;
    }
    return improved;
  }

  /// Load from JSON. Missing keys — saves written by an older build —
  /// fall back to "no shift has ever ended", never throw.
  factory PersonalBests.fromJson(Map<String, dynamic> json) {
    return PersonalBests(
      bestBankedScore: (json['bestBankedScore'] as num?)?.toInt() ?? 0,
      longestChain: (json['longestChain'] as num?)?.toInt() ?? 0,
      furthestDistancePx:
          (json['furthestDistancePx'] as num?)?.toDouble() ?? 0.0,
      mostFaresInOneShift:
          (json['mostFaresInOneShift'] as num?)?.toInt() ?? 0,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'bestBankedScore': bestBankedScore,
      'longestChain': longestChain,
      'furthestDistancePx': furthestDistancePx,
      'mostFaresInOneShift': mostFaresInOneShift,
    };
  }
}
