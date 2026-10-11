import 'daily_shift.dart';
import '../../models/weekly_gauntlet_record.dart';

/// The offline Weekly Gauntlet (issue #288).
///
/// The Daily gives the calendar loop one rhythm; this is the second. A
/// local week key — derived from the same device calendar the Daily
/// already reads — picks the week's objective and modifier, both pure
/// functions of that key, so every player in the world gets the identical
/// challenge in the same week with no server anywhere in the path. The
/// best result of the week persists on-device; the gauntlet itself is
/// replayable all week, unlike the daily's one attempt.
///
/// Pure logic — no I/O, and the only clock read is [currentWeekKey],
/// through [DailyShift]'s injectable clock, so the week rules are unit
/// testable the same way the day rules are.
class WeeklyGauntlet {
  WeeklyGauntlet._();

  /// The ISO-8601 week key of the local calendar week [moment] falls on:
  /// 'yyyy-Www', the week numbered by its Thursday, week 1 being the week
  /// containing the year's first Thursday. Calendar fields only, like
  /// [DailyShift.dateKeyFor] — no elapsed-time arithmetic, so the key is
  /// the same on every device in the same zone and no daylight-saving
  /// transition can move a week's edges. The Thursday anchor is what makes
  /// the year in the key correct across New Year: 2027-01-01 is a Friday,
  /// and its week belongs to 2026.
  static String weekKeyFor(DateTime moment) {
    // The week's Thursday, as calendar arithmetic in UTC (no zone, no
    // DST): DateTime normalizes the day overflow across month and year.
    final thursday = DateTime.utc(
      moment.year,
      moment.month,
      moment.day + 4 - moment.weekday,
    );
    final dayOfYear =
        thursday.difference(DateTime.utc(thursday.year, 1, 1)).inDays + 1;
    final week = (dayOfYear - 1) ~/ 7 + 1;
    return '${thursday.year.toString().padLeft(4, '0')}'
        '-W${week.toString().padLeft(2, '0')}';
  }

  /// The week key of the day named by [dateKey] ('yyyy-MM-dd'). Throws
  /// [ArgumentError] on a key that is not a calendar day, exactly like
  /// [DailyShift.seedForDateKey] — callers hold keys the date model built.
  static String weekKeyForDateKey(String dateKey) {
    if (dateKey.length != 10 || dateKey[4] != '-' || dateKey[7] != '-') {
      throw ArgumentError.value(dateKey, 'dateKey', 'expected yyyy-MM-dd');
    }
    final year = int.tryParse(dateKey.substring(0, 4));
    final month = int.tryParse(dateKey.substring(5, 7));
    final day = int.tryParse(dateKey.substring(8, 10));
    if (year == null || month == null || day == null) {
      throw ArgumentError.value(dateKey, 'dateKey', 'expected yyyy-MM-dd');
    }
    if (year < 1 || year > 9999) {
      throw ArgumentError.value(dateKey, 'dateKey', 'expected yyyy-MM-dd');
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      throw ArgumentError.value(dateKey, 'dateKey', 'expected yyyy-MM-dd');
    }
    // DateTime normalizes an impossible date (Feb 30 becomes Mar 2); a
    // day that moved under normalization was never a calendar day.
    final parsed = DateTime.utc(year, month, day);
    if (parsed.month != month || parsed.day != day) {
      throw ArgumentError.value(dateKey, 'dateKey', 'expected yyyy-MM-dd');
    }
    return weekKeyFor(DateTime(year, month, day));
  }

  /// The current week key on this device's clock — the same clock the
  /// Daily reads, pinned by the same tests.
  static String get currentWeekKey =>
      weekKeyForDateKey(DailyShift.todayKey);

  /// The week's course seed for the week named by [weekKey].
  ///
  /// A pure hash of the key string, so the same week always deals the
  /// same city on every device. Frozen like [DailyShift.seedForDateKey]:
  /// once shipped it must never be "improved", because stored gauntlet
  /// results name the week whose course they were set on. Every
  /// intermediate value stays inside 2^49 (the mask keeps each step under
  /// 2^30, the multiplier under 2^25), exact on every platform Dart
  /// compiles to.
  static int seedForWeek(String weekKey) {
    _checkWeekKey(weekKey);
    var hash = 0x811C9DC5; // FNV-1a offset basis, under 2^31
    for (final unit in weekKey.codeUnits) {
      hash = (((hash ^ unit) & 0xFFFFFF) * 0x01000193) & 0x3FFFFFFF;
    }
    return hash;
  }

  /// The week's objective and modifier, both derived deterministically
  /// from [weekKey] — two independent draws off the one stable seed, so
  /// the pair varies week to week and never depends on when or where it
  /// is read. The seed the week's course is built from comes along.
  static GauntletPlan planForWeek(String weekKey) {
    final seed = seedForWeek(weekKey);
    return GauntletPlan._(
      weekKey: weekKey,
      objective: GauntletObjective.values[
          _mix(seed, 0x11) % GauntletObjective.values.length],
      modifier: GauntletModifier.values[
          _mix(seed, 0x22) % GauntletModifier.values.length],
      seed: seed,
    );
  }

  /// A small avalanche over [x] with a [salt], so the objective and
  /// modifier draws are not two readings of the same low bits. Masked
  /// to 30 bits before the multiply; every intermediate stays under
  /// 2^45, exact everywhere.
  static int _mix(int x, int salt) {
    var h = (x ^ (salt * 0x9E3779B1)) & 0x3FFFFFFF;
    h = ((h ^ (h >> 15)) & 0x7FFF) * 0x2C1B3C6D;
    return (h ^ (h >> 13)) & 0x3FFFFFFF;
  }

  static void _checkWeekKey(String weekKey) {
    if (weekKey.length != 8 ||
        weekKey[4] != '-' ||
        weekKey[5] != 'W' ||
        int.tryParse(weekKey.substring(0, 4)) == null ||
        int.tryParse(weekKey.substring(6, 8)) == null) {
      throw ArgumentError.value(weekKey, 'weekKey', 'expected yyyy-Www');
    }
  }
}

/// What the week asks the player to do in one gauntlet run. The target is
/// the bar the run's own numbers are measured against; the same run may
/// clear several of the week's bars, but only the week's own objective is
/// what the card reads.
enum GauntletObjective {
  /// The run's final fare-chain score, banked or forfeited — the number
  /// the Daily already shares.
  score(5000),

  /// Fares dropped off in one run.
  fares(20),

  /// The run's best chain multiplier.
  chain(6),

  /// Metres driven in one run.
  distance(3500);

  const GauntletObjective(this.target);

  /// The declared bar for this objective, in the objective's own unit.
  final int target;

  /// The one-line statement of the week's goal, target included.
  String get title => switch (this) {
        score => 'Score $target points in one run',
        fares => 'Deliver $target fares in one run',
        chain => 'Reach a x$target fare chain in one run',
        distance => 'Drive $target m in one run',
      };

  /// The best-of-week reading against the bar, for the card's progress
  /// line.
  String progressTitle(int best) => switch (this) {
        score => 'Best score $best / $target',
        fares => 'Best fares $best / $target',
        chain => 'Best chain x$best / x$target',
        distance => 'Best distance $best m / $target m',
      };

  /// The best value [record] holds for this objective.
  int progressIn(WeeklyGauntletRecord record) => switch (this) {
        score => record.bestScore,
        fares => record.bestFares,
        chain => record.bestChain,
        distance => record.bestDistanceMetres,
      };
}

/// How the week changes the run. Each one is a real rule the game
/// enforces for gauntlet runs, not a label: [suddenDeath] shrinks the
/// crash budget, [doubleFares] pays every fare twice.
enum GauntletModifier {
  /// The run starts with one life instead of three.
  suddenDeath,

  /// Every fare pays double coins. The chain score — and so the score
  /// objective — is untouched; the modifier changes the payout, not the
  /// mastery.
  doubleFares;

  /// The one-line statement of the rule, shown on the card.
  String get title => switch (this) {
        suddenDeath => 'One life — the first crash ends the run',
        doubleFares => 'Double fares — every fare pays double coins',
      };
}

/// One week's challenge: the key it belongs to, the objective, the
/// modifier, and the course seed. Built only by [WeeklyGauntlet], so a
/// plan and its key can never disagree.
class GauntletPlan {
  const GauntletPlan._({
    required this.weekKey,
    required this.objective,
    required this.modifier,
    required this.seed,
  });

  /// The 'yyyy-Www' week this plan belongs to.
  final String weekKey;

  final GauntletObjective objective;
  final GauntletModifier modifier;

  /// The week's course seed, from [WeeklyGauntlet.seedForWeek].
  final int seed;

  /// The best the record holds for this plan's week and objective — 0
  /// when the record belongs to another week (a new week starts over).
  int progressIn(WeeklyGauntletRecord record) =>
      record.weekKey == weekKey ? objective.progressIn(record) : 0;

  /// True when the stored best has reached the week's bar.
  bool objectiveMet(WeeklyGauntletRecord record) =>
      progressIn(record) >= objective.target;
}
