import 'dart:math' as math;

import 'daily_result.dart';

/// The visible Daily streak (issue #281).
///
/// Until this block existed the only streak consumer was three hidden
/// achievements: no screen showed the run a player was on, nothing in the
/// save carried it, and a missed day cost nothing the player could see.
/// This is that state made visible and rewarding — the current run, the
/// best ever, and the one declared coin bonus a completion settles.
///
/// Pure data with a JSON round-trip, matching [DailyResult]'s persistence
/// style, plus the calendar arithmetic the streak is defined by. Runs are
/// counted in *calendar days* of the 'yyyy-MM-dd' date keys, never in
/// elapsed hours: a daylight-saving transition changes the length of a
/// local day, and a run must neither break nor extend across one. Date
/// keys have no zone in them, so the day numbers below are the same on
/// every device, exactly like the seeds the courses come from.
class DailyStreak {
  const DailyStreak({
    this.current = 0,
    this.best = 0,
    this.lastDateKey = '',
    this.rewardDateKey = '',
    this.lastRewardCoins = 0,
  });

  /// The current run of consecutive completed dailies, as of
  /// [lastDateKey]. The stored run is only *alive* on [lastDateKey] and
  /// the calendar day after it; see [currentOn] for the reading a screen
  /// shows.
  final int current;

  /// The longest run ever completed. Monotone — a missed day zeroes the
  /// reading but never takes this away.
  final int best;

  /// The date key of the day that last extended [current]. Empty until
  /// the first daily is ever recorded.
  final String lastDateKey;

  /// The date key of the day whose streak bonus was last settled. Empty
  /// until the first reward settles. Together with [lastRewardCoins]
  /// this is the settlement record: a date already here never pays
  /// again, whatever else re-runs.
  final String rewardDateKey;

  /// The coins settled for [rewardDateKey] — the declared amount the
  /// player was actually paid, kept so the UI can name it.
  final int lastRewardCoins;

  /// The declared bonus: this many coins a day, capped at [rewardCapDays]
  /// — the first week of a run pays 50 more a day, and every day past it
  /// pays the cap flat. A missed day resets the rate with the run.
  static const int rewardPerDay = 50;
  static const int rewardCapDays = 7;

  /// The declared streak bonus for a run of [streak] completed days.
  static int rewardCoins(int streak) =>
      rewardPerDay * math.min(streak, rewardCapDays);

  /// The run as it stands on [dayKey]: [current] while the last counted
  /// day is [dayKey] itself or the calendar day before it — a run that
  /// survived the night is still alive the next day. Any older last day
  /// means a missed day broke it, and the reading is 0; the stored state
  /// is the record of what was earned, not the schedule, so it is left
  /// untouched (a restart cannot be tricked into forgetting [best]).
  int currentOn(String dayKey) {
    final last = _dayNumber(lastDateKey);
    final day = _dayNumber(dayKey);
    if (last == null || day == null) return 0;
    return day == last || day == last + 1 ? current : 0;
  }

  /// The run a completion on [dayKey] would reach: the run alive on
  /// [dayKey] plus the day itself.
  int afterCompletionOn(String dayKey) => currentOn(dayKey) + 1;

  /// The declared bonus the next completion pays, read on [dayKey]: the
  /// reward for the run [afterCompletionOn] would reach. On an unplayed
  /// day that is the day's own bonus; on a played day it is the next
  /// day's — the one the player can still earn.
  int nextRewardOn(String dayKey) => rewardCoins(afterCompletionOn(dayKey));

  /// The coins already settled for [dayKey], or null when none has. The
  /// settlement guard: a date whose reward is on record never pays again.
  int? settledRewardFor(String dayKey) =>
      rewardDateKey == dayKey ? lastRewardCoins : null;

  /// True when [dayKey] is a calendar day before [lastDateKey]: a
  /// completion arriving out of order, from a clock that moved backward.
  /// The settlement ignores those — they can neither extend the run nor
  /// pay a backdated bonus, so walking the clock back through past days
  /// cannot mint a reward at every stop. Unreadable keys are not "before"
  /// anything; the normal rules apply to them.
  bool isBeforeLast(String dayKey) {
    final day = _dayNumber(dayKey);
    final last = _dayNumber(lastDateKey);
    return day != null && last != null && day < last;
  }

  /// True until the block holds anything — the shape a save written
  /// before the streak existed loads with. Used once to seed the block
  /// from the daily history (`GameStateService.loadSaveData`); a
  /// non-virgin block is never touched by that seed.
  bool get isVirgin =>
      current == 0 &&
      best == 0 &&
      lastDateKey.isEmpty &&
      rewardDateKey.isEmpty &&
      lastRewardCoins == 0;

  /// The state after a completion on [dayKey]. A state that already
  /// counted [dayKey] is returned unchanged, so a replay can neither
  /// extend the run twice nor push [best].
  DailyStreak afterCompletion(String dayKey) {
    if (lastDateKey == dayKey) return this;
    final run = afterCompletionOn(dayKey);
    return DailyStreak(
      current: run,
      best: math.max(best, run),
      lastDateKey: dayKey,
      rewardDateKey: rewardDateKey,
      lastRewardCoins: lastRewardCoins,
    );
  }

  /// The state with [coins] settled as [dayKey]'s bonus. Zero pays
  /// nothing and changes nothing — the caller's at-most-once guard
  /// expressed in the data.
  DailyStreak withRewardSettled(String dayKey, int coins) {
    if (coins <= 0) return this;
    return DailyStreak(
      current: current,
      best: best,
      lastDateKey: lastDateKey,
      rewardDateKey: dayKey,
      lastRewardCoins: coins,
    );
  }

  /// The block a save's daily history implies (issue #281): the one
  /// migration that seeds a save written before the block existed. The
  /// history is the same source the hidden streak achievements count
  /// from — [best] is its longest run, and [current] the run still alive
  /// on [todayKey], one whose last day is that day or the calendar day
  /// before it. A dead run seeds as nothing: the block must not
  /// resurrect a streak the player already lost. No reward is seeded —
  /// nothing was ever paid under the old save, and the settlement record
  /// must not claim otherwise.
  factory DailyStreak.fromHistory(
    List<DailyResult> results, {
    required String todayKey,
  }) {
    final entries = <({int day, String key})>[];
    for (final result in results) {
      final day = _dayNumber(result.dateKey);
      if (day != null) entries.add((day: day, key: result.dateKey));
    }
    if (entries.isEmpty) return const DailyStreak();
    entries.sort((a, b) => a.day.compareTo(b.day));

    var best = 1;
    var run = 1;
    for (var i = 1; i < entries.length; i++) {
      run = entries[i].day == entries[i - 1].day + 1 ? run + 1 : 1;
      if (run > best) best = run;
    }

    final today = _dayNumber(todayKey);
    final last = entries.last;
    if (today == null || (last.day != today && last.day != today - 1)) {
      return DailyStreak(best: best);
    }
    var current = 1;
    for (var i = entries.length - 1; i > 0; i--) {
      if (entries[i].day != entries[i - 1].day + 1) break;
      current++;
    }
    return DailyStreak(current: current, best: best, lastDateKey: last.key);
  }

  /// Load from JSON. Missing keys — a block written by an older build —
  /// fall back to the value a fresh block would have, never throw: one
  /// unreadable block must not lose the whole save.
  factory DailyStreak.fromJson(Map<String, dynamic> json) {
    return DailyStreak(
      current: (json['current'] as num?)?.toInt() ?? 0,
      best: (json['best'] as num?)?.toInt() ?? 0,
      lastDateKey: (json['lastDateKey'] as String?) ?? '',
      rewardDateKey: (json['rewardDateKey'] as String?) ?? '',
      lastRewardCoins: (json['lastRewardCoins'] as num?)?.toInt() ?? 0,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'current': current,
      'best': best,
      'lastDateKey': lastDateKey,
      'rewardDateKey': rewardDateKey,
      'lastRewardCoins': lastRewardCoins,
    };
  }

  /// Whole days since the epoch for a 'yyyy-MM-dd' key, as a UTC-midnight
  /// day number — pure calendar arithmetic, no local clock or time zone
  /// in it, so two consecutive keys are consecutive numbers in every
  /// zone, across every daylight-saving transition. Unreadable keys
  /// count as nothing rather than throwing: one malformed day must not
  /// lose the streak, and a corrupt save's absurd year must not crash a
  /// UI getter through `DateTime.utc`'s range check.
  static int? _dayNumber(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (year < 1 || year > 9999) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final parsed = DateTime.utc(year, month, day);
    // `DateTime.utc` normalizes an impossible date (Feb 30 becomes Mar 2)
    // instead of rejecting it; a day that moved under normalization was
    // never a calendar day, so it counts as nothing like the rest.
    if (parsed.month != month || parsed.day != day) return null;
    return parsed.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
  }
}
