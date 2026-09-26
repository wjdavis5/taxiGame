import 'run_summary.dart';

/// The shareable end-of-run score card (issue #22).
///
/// Daily Shift (#19) made every player's course identical for a day, and
/// with no network the comparison happens through the OS share sheet —
/// the one channel a fully offline game still has. This is the card's
/// content, pulled together from the settled [RunSummary] plus the two
/// things the summary does not carry: the run's course seed and the
/// calendar day it belongs to. The issue's list is the contract — score,
/// chain, distance, date, seed — and [shareText] repeats it in plain text
/// so the share sheet offers words alongside the image.
///
/// Pure data, matching [RunSummary]: the renderer and the platform
/// channel consume it, and the labels are unit testable without either.
class ScoreCardData {
  const ScoreCardData({
    required this.title,
    required this.score,
    required this.bestChain,
    required this.distanceLabel,
    required this.dateKey,
    required this.seed,
    required this.isDailyShift,
    required this.isGhostRace,
    required this.isPersonalBest,
  });

  /// Assembles the card for a shift that just ended. [seed] is the run's
  /// course seed (`TaxiGame.runSeed` — for a daily, exactly
  /// [DailyShift.seedForDateKey]'s value for [dateKey]); [dateKey] is the
  /// day the run belongs to, pinned at run start for runs on the daily
  /// course and "today" for free play; the two flags pick the title.
  factory ScoreCardData.fromRun({
    required RunSummary summary,
    required int seed,
    required String dateKey,
    required bool isDailyShift,
    required bool isGhostRace,
  }) {
    final String title;
    if (isDailyShift) {
      title = 'DAILY SHIFT';
    } else if (isGhostRace) {
      title = 'GHOST RACE';
    } else {
      title = summary.outcome == ShiftOutcome.banked
          ? 'SHIFT BANKED'
          : 'SHIFT OVER';
    }
    return ScoreCardData(
      title: title,
      score: summary.score,
      bestChain: summary.bestChain,
      distanceLabel: summary.distanceLabel,
      dateKey: dateKey,
      seed: seed,
      isDailyShift: isDailyShift,
      isGhostRace: isGhostRace,
      isPersonalBest: summary.isPersonalBest,
    );
  }

  /// What the run was: the day's shared course, a race against the
  /// stored ghost, or an ordinary shift's two endings.
  final String title;

  /// The run's final score — the number being shared.
  final int score;

  /// The run's best chain multiplier.
  final int bestChain;

  /// The driven distance, already formatted (the HUD's [RunSummary.distanceLabel]).
  final String distanceLabel;

  /// The day the run belongs to, as a 'yyyy-MM-dd' date key. On the daily
  /// course this is the day the shared course was seeded from — the same
  /// key every player's card carries that day.
  final String dateKey;

  /// The course seed. On the daily it is derived from [dateKey], so a
  /// player reading the card can (and everyone else's card does) name
  /// the identical course.
  final int seed;

  /// True when the run was the day's one scoring Daily Shift.
  final bool isDailyShift;

  /// True when the run was a ghost race on the day's course (issue #20).
  final bool isGhostRace;

  /// True when the run beat the personal best — the card earns its badge.
  final bool isPersonalBest;

  /// '×N', as the summary panel shows it.
  String get chainLabel => '\u00d7$bestChain';

  /// The seed as the card renders it: bare digits, labelled by the row.
  String get seedLabel => '$seed';

  /// The plain-text line handed to the share sheet beside the image:
  /// every number the issue asks the card to carry, readable without
  /// opening the image.
  String get shareText {
    final course = isDailyShift
        ? 'Daily Shift $dateKey, seed $seed'
        : isGhostRace
            ? 'ghost race on the $dateKey course, seed $seed'
            : '$dateKey, seed $seed';
    return 'CAB HUSTLE — $title: $score pts\n'
        'Best chain $chainLabel \u00b7 $distanceLabel\n'
        '$course';
  }

  /// The card's footer. The daily's line is the point of sharing it:
  /// one course, every player, one day — beatable, comparable, gone at
  /// midnight.
  String get footer =>
      isDailyShift ? 'ONE COURSE \u00b7 EVERY PLAYER \u00b7 TODAY ONLY' : 'CAB HUSTLE';
}
