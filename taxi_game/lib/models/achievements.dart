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

  const AchievementState({
    required this.bestBankedScore,
    required this.longestChain,
    required this.furthestDistanceMetres,
    required this.mostFaresInOneShift,
    required this.cleanBankedShifts,
    required this.unlockedVehicleCount,
    required this.longestDailyStreak,
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

  /// Every achievement, in records-screen order (chain, distance,
  /// banking, cars, streaks).
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
