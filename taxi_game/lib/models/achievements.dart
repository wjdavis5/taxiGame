import 'daily_result.dart';

/// Everything an achievement's measure is allowed to read (issue #21):
/// one immutable snapshot of the player's standing, built fresh at every
/// evaluation. Because it is values rather than live service references,
/// the definitions below stay pure functions — trivially testable, and
/// unable to reach storage or the clock.
class AchievementState {
  /// The highest score a shift ever paid out at a bank.
  final int bestBankedScore;

  /// The longest fare chain ever ridden in one shift.
  final int longestChain;

  /// The furthest one shift has driven, in whole metres (floored — the
  /// milestones are coarse, and a fraction never decides one).
  final int furthestDistanceMetres;

  /// The most fares ever delivered within one shift.
  final int mostFaresInOneShift;

  /// Shifts that ended in a bank with no life lost — the banking
  /// discipline the clean-bank achievements measure. A lifetime count
  /// held in [PersonalBests] (issue #55), never trimmed: the shift
  /// history is a fixed 200-record window, and counting over it let
  /// progress fall as old clean banks aged out — with THE HOUSE ALWAYS
  /// WINS (15) unreachable outright for anyone banking clean less than
  /// 7.5% of the time.
  final int cleanBankedShifts;

  /// How many garage vehicles the player owns, starter included.
  final int unlockedVehicleCount;

  /// The longest run of consecutive days with a completed Daily Shift.
  /// A streak stands even if today's is unplayed — the record is of what
  /// was done, not of what is still alive.
  final int longestDailyStreak;

  /// Close calls cleared across every shift ever ended (issue #283) —
  /// the near-miss economy's lifetime count, folded into the save's
  /// totals like the clean-bank counter, never counted over the window.
  final int totalNearMisses;

  /// Completed Daily Shifts, consecutive or not (issue #283): the
  /// participation measure the streak tiers cannot say — a lapsed streak
  /// still keeps every day that was played.
  final int completedDailyCount;

  /// Distance driven across every shift ever ended, in whole metres
  /// (floored, like [furthestDistanceMetres]) (issue #283).
  final int lifetimeDistanceMetres;

  /// True once the tutorial ladder is finished (issue #283): the save
  /// sits past its last rung. The ladder's record hangs off this one
  /// fact, never off an asset probe.
  final bool tutorialComplete;

  const AchievementState({
    required this.bestBankedScore,
    required this.longestChain,
    required this.furthestDistanceMetres,
    required this.mostFaresInOneShift,
    required this.cleanBankedShifts,
    required this.unlockedVehicleCount,
    required this.longestDailyStreak,
    required this.totalNearMisses,
    required this.completedDailyCount,
    required this.lifetimeDistanceMetres,
    required this.tutorialComplete,
  });
}

/// Reads one number out of an [AchievementState]. Every achievement in
/// the catalog is "measure reaches threshold", so this one shape covers
/// all of them and the UI can show progress toward any locked one.
typedef AchievementMeasure = int Function(AchievementState state);

/// One achievement: what it is called, what it asks for, and how to
/// measure it. Earned state is *not* here — it lives in the save's
/// `achievements` map (issue #21), so a definition stays a pure,
/// stateless constant.
class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.title,
    required this.description,
    required this.threshold,
    required this.measure,
  });

  /// Stable identifier — the key under which the save's `achievements`
  /// map records the award. Never rename a shipped id: the save holds it.
  final String id;

  /// Short display name, shown on the unlock banner and records screen.
  final String title;

  /// One line naming exactly what earns it.
  final String description;

  /// The value [measure] must reach for the achievement to be earned.
  final int threshold;

  /// The measured quantity, read from an [AchievementState].
  final AchievementMeasure measure;

  /// True when [state] earns the achievement.
  bool isEarned(AchievementState state) => measure(state) >= threshold;

  /// The measured value, capped at the threshold — progress text reads
  /// "7/7" on an earned achievement, never "12/7".
  int progress(AchievementState state) =>
      measure(state).clamp(0, threshold).toInt();
}

/// The achievement set (issue #21): fifteen awards across the five
/// tracks the issue names — chain milestones, distance milestones,
/// banking discipline, cars collected, and daily streaks.
///
/// Issue #283 grows it into the mastery set: the tracks the systems the
/// game celebrates were missing — lifetime close calls, score tiers,
/// daily participation without a streak, lifetime driving volume, and
/// the tutorial ladder's own finish. Every new measure reads data the
/// save already recorded.
///
/// Pure constants — no Flutter, no I/O, no clock — so every rule is unit
/// testable like the rest of the models.
class AchievementCatalog {
  AchievementCatalog._();

  // --- Chain milestones (longest chain in one shift) ----------------------

  static const chain3 = AchievementDef(
    id: 'chain_3',
    title: 'HOT STREAK',
    description: 'Ride a \u00d73 fare chain in one shift.',
    threshold: 3,
    measure: _longestChain,
  );
  static const chain5 = AchievementDef(
    id: 'chain_5',
    title: 'CHAIN ARTIST',
    description: 'Ride a \u00d75 fare chain in one shift.',
    threshold: 5,
    measure: _longestChain,
  );
  static const chain8 = AchievementDef(
    id: 'chain_8',
    title: 'CHAIN MASTER',
    description: 'Ride a \u00d78 fare chain in one shift.',
    threshold: 8,
    measure: _longestChain,
  );

  // --- Distance milestones (one shift) ------------------------------------

  static const distance1000 = AchievementDef(
    id: 'distance_1000',
    title: 'KNOWING THE STREETS',
    description: 'Drive 1 km in a single shift.',
    threshold: 1000,
    measure: _furthestDistanceMetres,
  );
  static const distance3000 = AchievementDef(
    id: 'distance_3000',
    title: 'MARATHON SHIFT',
    description: 'Drive 3 km in a single shift.',
    threshold: 3000,
    measure: _furthestDistanceMetres,
  );
  static const distance5000 = AchievementDef(
    id: 'distance_5000',
    title: 'CROSS-TOWN LEGEND',
    description: 'Drive 5 km in a single shift.',
    threshold: 5000,
    measure: _furthestDistanceMetres,
  );

  // --- Banking discipline (banked shifts with no life lost) ---------------

  static const bankClean1 = AchievementDef(
    id: 'bank_clean_1',
    title: 'SCOT-FREE',
    description: 'Bank a shift without losing a single life.',
    threshold: 1,
    measure: _cleanBankedShifts,
  );
  static const bankClean5 = AchievementDef(
    id: 'bank_clean_5',
    title: 'SURE HANDS',
    description: 'Bank five shifts without losing a life in any of them.',
    threshold: 5,
    measure: _cleanBankedShifts,
  );
  static const bankClean15 = AchievementDef(
    id: 'bank_clean_15',
    title: 'THE HOUSE ALWAYS WINS',
    description: 'Bank fifteen shifts without losing a life in any of them.',
    threshold: 15,
    measure: _cleanBankedShifts,
  );

  // --- Cars collected (garage fleet owned) --------------------------------

  // Thresholds count the fleet as shipped: 7 vehicles in the garage
  // (starter included). `test/achievements_test.dart` asserts that count,
  // so growing the fleet forces a conscious look at this tier.
  static const cars2 = AchievementDef(
    id: 'cars_2',
    title: 'TWO-CAB OPERATION',
    description: 'Own 2 cars in the garage.',
    threshold: 2,
    measure: _unlockedVehicleCount,
  );
  static const cars4 = AchievementDef(
    id: 'cars_4',
    title: 'FLEET BUILDER',
    description: 'Own 4 cars in the garage.',
    threshold: 4,
    measure: _unlockedVehicleCount,
  );
  static const cars7 = AchievementDef(
    id: 'cars_7',
    title: 'FULL FLEET',
    description: 'Own every car in the garage.',
    threshold: 7,
    measure: _unlockedVehicleCount,
  );

  // --- Daily streaks (consecutive completed Daily Shifts) -----------------

  static const streak3 = AchievementDef(
    id: 'streak_3',
    title: 'HABIT FORMING',
    description: 'Complete the Daily Shift 3 days in a row.',
    threshold: 3,
    measure: _longestDailyStreak,
  );
  static const streak7 = AchievementDef(
    id: 'streak_7',
    title: 'WEEKLY GRIND',
    description: 'Complete the Daily Shift 7 days in a row.',
    threshold: 7,
    measure: _longestDailyStreak,
  );
  static const streak30 = AchievementDef(
    id: 'streak_30',
    title: 'MONTH ON THE METER',
    description: 'Complete the Daily Shift 30 days in a row.',
    threshold: 30,
    measure: _longestDailyStreak,
  );

  // --- Close calls (lifetime near-miss mastery, issue #283) ---------------

  static const closeCall10 = AchievementDef(
    id: 'close_call_10',
    title: 'CLOSE SHAVE',
    description: 'Clear 10 close calls across your shifts.',
    threshold: 10,
    measure: _totalNearMisses,
  );
  static const closeCall100 = AchievementDef(
    id: 'close_call_100',
    title: 'SHAVE ARTIST',
    description: 'Clear 100 close calls across your shifts.',
    threshold: 100,
    measure: _totalNearMisses,
  );
  static const closeCall500 = AchievementDef(
    id: 'close_call_500',
    title: 'THREADING THE NEEDLE',
    description: 'Clear 500 close calls across your shifts.',
    threshold: 500,
    measure: _totalNearMisses,
  );

  // --- Score tiers (best banked score, issue #283) ------------------------

  // The share card's rank bands (score_card.dart), banked: the same names
  // a run earns when it settles, now records of what reached the wallet.
  static const score500 = AchievementDef(
    id: 'score_500',
    title: 'CERTIFIED HUSTLER',
    description: 'Bank 500 in a single shift.',
    threshold: 500,
    measure: _bestBankedScore,
  );
  static const score2000 = AchievementDef(
    id: 'score_2000',
    title: 'TRAFFIC MENACE',
    description: 'Bank 2000 in a single shift.',
    threshold: 2000,
    measure: _bestBankedScore,
  );
  static const score5000 = AchievementDef(
    id: 'score_5000',
    title: 'GIG-LEGEND',
    description: 'Bank 5000 in a single shift.',
    threshold: 5000,
    measure: _bestBankedScore,
  );

  // --- Daily participation (total completed dailies, issue #283) ----------

  static const daily10 = AchievementDef(
    id: 'daily_10',
    title: 'DAILY DRIVER',
    description: 'Complete the Daily Shift on 10 days.',
    threshold: 10,
    measure: _completedDailyCount,
  );
  static const daily50 = AchievementDef(
    id: 'daily_50',
    title: 'CITY REGULAR',
    description: 'Complete the Daily Shift on 50 days.',
    threshold: 50,
    measure: _completedDailyCount,
  );
  static const daily200 = AchievementDef(
    id: 'daily_200',
    title: 'RITUAL KEEPER',
    description: 'Complete the Daily Shift on 200 days.',
    threshold: 200,
    measure: _completedDailyCount,
  );

  // --- Lifetime volume (distance across every shift, issue #283) ----------

  static const lifetime25km = AchievementDef(
    id: 'lifetime_25km',
    title: 'FAMILIAR ROADS',
    description: 'Drive 25 km across all your shifts.',
    threshold: 25000,
    measure: _lifetimeDistanceMetres,
  );
  static const lifetime100km = AchievementDef(
    id: 'lifetime_100km',
    title: 'CENTURY CLUB',
    description: 'Drive 100 km across all your shifts.',
    threshold: 100000,
    measure: _lifetimeDistanceMetres,
  );
  static const lifetime500km = AchievementDef(
    id: 'lifetime_500km',
    title: 'ROAD VETERAN',
    description: 'Drive 500 km across all your shifts.',
    threshold: 500000,
    measure: _lifetimeDistanceMetres,
  );

  // --- The ladder's finish (issue #283) -----------------------------------

  static const tutorialComplete = AchievementDef(
    id: 'tutorial_complete',
    title: 'LICENSED DRIVER',
    description: 'Complete all ten tutorial levels.',
    threshold: 1,
    measure: _tutorialComplete,
  );

  /// Every achievement, in records-screen order — the five original
  /// tracks (chain, distance, banking, cars, streaks), then issue #283's
  /// mastery tracks (close calls, score, dailies, lifetime volume, the
  /// ladder). Appending keeps every existing tie-break and progress
  /// order stable.
  static const List<AchievementDef> all = [
    chain3,
    chain5,
    chain8,
    distance1000,
    distance3000,
    distance5000,
    bankClean1,
    bankClean5,
    bankClean15,
    cars2,
    cars4,
    cars7,
    streak3,
    streak7,
    streak30,
    closeCall10,
    closeCall100,
    closeCall500,
    score500,
    score2000,
    score5000,
    daily10,
    daily50,
    daily200,
    lifetime25km,
    lifetime100km,
    lifetime500km,
    tutorialComplete,
  ];

  /// The definition with [id], or null when no such achievement exists.
  static AchievementDef? byId(String id) {
    for (final def in all) {
      if (def.id == id) return def;
    }
    return null;
  }

  // --- Measures (static so the definitions above can be const) ------------

  static int _longestChain(AchievementState state) => state.longestChain;
  static int _furthestDistanceMetres(AchievementState state) =>
      state.furthestDistanceMetres;
  static int _cleanBankedShifts(AchievementState state) =>
      state.cleanBankedShifts;
  static int _unlockedVehicleCount(AchievementState state) =>
      state.unlockedVehicleCount;
  static int _longestDailyStreak(AchievementState state) =>
      state.longestDailyStreak;
  static int _totalNearMisses(AchievementState state) => state.totalNearMisses;
  static int _bestBankedScore(AchievementState state) => state.bestBankedScore;
  static int _completedDailyCount(AchievementState state) =>
      state.completedDailyCount;
  static int _lifetimeDistanceMetres(AchievementState state) =>
      state.lifetimeDistanceMetres;
  static int _tutorialComplete(AchievementState state) =>
      state.tutorialComplete ? 1 : 0;

  /// The longest run of consecutive calendar days in [results] — the
  /// daily-streak measure. Computed from the on-device daily history
  /// (issue #19), which keeps a bit over a year: far more window than
  /// the longest streak asked for here.
  ///
  /// Date keys are 'yyyy-MM-dd' ([DailyShift.dateKeyFor]'s format, the
  /// same key one result per day is stored under). Unreadable keys count
  /// as nothing rather than throwing — one malformed result must not
  /// lose the streak. Duplicates cannot exist (the data layer enforces
  /// one result per day), but a repeated key would simply not extend a
  /// run, never inflate it.
  static int longestDailyStreak(List<DailyResult> results) {
    final days = <int>[];
    for (final result in results) {
      final day = _dayNumber(result.dateKey);
      if (day != null) days.add(day);
    }
    if (days.isEmpty) return 0;
    days.sort();

    var best = 1;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      run = days[i] == days[i - 1] + 1 ? run + 1 : 1;
      if (run > best) best = run;
    }
    return best;
  }

  /// Whole days since the epoch for a 'yyyy-MM-dd' key, as a UTC-midnight
  /// day number — pure calendar arithmetic, no local clock or time zone
  /// in it, so a streak means the same thing it read as when earned.
  static int? _dayNumber(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime.utc(year, month, day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }
}
