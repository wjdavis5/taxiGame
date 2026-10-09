import '../game/systems/run_summary.dart';
import 'run_record.dart';

/// The player's lifetime records (issue #21).
///
/// With no leaderboards anywhere in the app, these five numbers are the
/// standing answer to "how good am I": the highest score a shift ever
/// paid out at a bank, the longest fare chain ever ridden in one shift,
/// the furthest one shift has driven, the most fares delivered in one
/// shift, and how many shifts were ever banked clean.
///
/// They are *stored*, not queries over the shift history: the history is
/// a fixed window (issue #17 trims it at 200 shifts), and a record that
/// regresses because an old shift fell off the front of a list is not a
/// record. Once set, a personal best never goes down — except through an
/// explicit reset in [GameStateService.resetProgress]. The same rule had
/// to extend to the clean-bank count (issue #55): counting it over the
/// window let progress read "11/15" then "10/15" as old clean banks aged
/// out, and a player banking clean under 7.5% of the time could never
/// reach fifteen at all.
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

  /// Lifetime count of shifts ended as a bank with no life lost (issue
  /// #55) — the clean-bank achievements' measure. A monotone counter,
  /// never trimmed: the shift history's 200-record window must not be
  /// able to take a clean bank back out of it.
  int cleanBankedShifts;

  PersonalBests({
    this.bestBankedScore = 0,
    this.longestChain = 0,
    this.furthestDistancePx = 0.0,
    this.mostFaresInOneShift = 0,
    this.cleanBankedShifts = 0,
  });

  /// The furthest single shift in metres, on the same px scale
  /// [RunSummary.pixelsPerMetre] and the HUD's distance badge use — one
  /// constant referenced, never duplicated.
  double get furthestDistanceMetres =>
      furthestDistancePx / RunSummary.pixelsPerMetre;

  /// Folds one ended shift into the records. The four maxima only move
  /// up; the clean-bank counter only moves up. Returns true when this
  /// shift set at least one record or added a clean bank — callers use
  /// that to decide whether the save itself must reach the disk.
  bool applyRun({
    required int score,
    required bool banked,
    required int longestChain,
    required double distancePx,
    required int faresDelivered,
    required int livesLost,
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
    // The clean-bank measure (issue #55): a bank that cost no life. The
    // increment counts as an improvement so the counter is persisted by
    // the same conditional save the maxima ride — a lifetime count that
    // only lives in memory would be lost to the next launch.
    if (banked && livesLost == 0) {
      cleanBankedShifts++;
      improved = true;
    }
    return improved;
  }

  /// The one-time migration seed (issue #247), in
  /// [LifetimeRunTotals.seedFromWindow]'s shape (issue #183): a save
  /// whose records block was written before — or lost its write after —
  /// the history's bests stores a smaller number than the window still
  /// shows, and the window is then the only record of the better shift.
  /// Each maximum takes the larger of what is stored and what the window
  /// holds, per field: `bestBankedScore` over the window's *banked*
  /// records only (a wreck's forfeited score is not a record, exactly as
  /// [applyRun] judges it), the other three over every record. Returns
  /// true when any maximum moved, so the caller persists the seed before
  /// the window can trim the record out from under it.
  ///
  /// `cleanBankedShifts` is deliberately not seeded here: it is a
  /// lifetime counter, not a maximum, and has had its own migration
  /// (issue #55) since before this block existed. Post-seed saves always
  /// hold the larger number, so this no-ops from then on.
  bool seedFromWindow(List<RunRecord> window) {
    var seeded = false;
    for (final record in window) {
      if (record.banked && record.score > bestBankedScore) {
        bestBankedScore = record.score;
        seeded = true;
      }
      if (record.longestChain > longestChain) {
        longestChain = record.longestChain;
        seeded = true;
      }
      if (record.distancePx > furthestDistancePx) {
        furthestDistancePx = record.distancePx;
        seeded = true;
      }
      if (record.faresDelivered > mostFaresInOneShift) {
        mostFaresInOneShift = record.faresDelivered;
        seeded = true;
      }
    }
    return seeded;
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
      cleanBankedShifts: (json['cleanBankedShifts'] as num?)?.toInt() ?? 0,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'bestBankedScore': bestBankedScore,
      'longestChain': longestChain,
      'furthestDistancePx': furthestDistancePx,
      'mostFaresInOneShift': mostFaresInOneShift,
      'cleanBankedShifts': cleanBankedShifts,
    };
  }
}
