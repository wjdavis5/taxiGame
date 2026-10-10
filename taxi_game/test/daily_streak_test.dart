import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/models/daily_result.dart';
import 'package:taxi_game/models/daily_streak.dart';
import 'helpers/calendar_days.dart';

/// The visible Daily streak's pure core (issue #281): calendar-day runs,
/// the alive/dead reading a screen shows, and the one declared bonus. The
/// arithmetic is pinned on real daylight-saving transition dates because
/// a streak is defined in calendar days, not elapsed hours — the bug the
/// calendar-day helpers exist to keep out of these tests.
void main() {
  DailyResult resultFor(String dateKey) => DailyResult(
        dateKey: dateKey,
        score: 100,
        banked: true,
        completedAtMs: 0,
      );

  group('runs are counted in calendar days', () {
    test('consecutive days extend the run; a gap starts it over', () {
      var streak = const DailyStreak();
      for (final key in ['2026-09-01', '2026-09-02', '2026-09-03']) {
        streak = streak.afterCompletion(key);
      }

      expect(streak.current, 3);
      expect(streak.best, 3);
      expect(streak.currentOn('2026-09-03'), 3,
          reason: 'the run is alive on the day it was completed');
      expect(streak.currentOn('2026-09-04'), 3,
          reason: 'and it survives the night into the next day');
      expect(streak.currentOn('2026-09-05'), 0,
          reason: 'a missed day breaks it');

      final afterGap = streak.afterCompletion('2026-09-05');
      expect(afterGap.current, 1);
      expect(afterGap.best, 3,
          reason: 'the best run is a record, never taken away');
    });

    test('the run reading never changes the stored state', () {
      final streak = const DailyStreak()
          .afterCompletion('2026-09-01')
          .afterCompletion('2026-09-02');

      expect(streak.currentOn('2026-10-01'), 0);
      expect(streak.current, 2,
          reason: 'a dead reading is a schedule, not an erasure');
      expect(streak.best, 2);
      expect(streak.lastDateKey, '2026-09-02');
    });

    test('a completion that already counted cannot extend twice', () {
      final once = const DailyStreak().afterCompletion('2026-09-01');
      final again = once.afterCompletion('2026-09-01');

      expect(again.current, 1);
      expect(again.best, 1);
      expect(again.lastDateKey, '2026-09-01');
    });

    test('unreadable keys count as nothing, never throw', () {
      final streak = const DailyStreak()
          .afterCompletion('nonsense')
          .afterCompletion('2026-09-01');

      expect(streak.current, 1);
      expect(streak.best, 1);
    });

    test('an impossible date is not a day', () {
      // Feb 30 used to normalize to Mar 2 inside DateTime.utc and extend
      // a run across the gap it never was.
      final streak = const DailyStreak()
          .afterCompletion('2026-02-28')
          .afterCompletion('2026-02-30')
          .afterCompletion('2026-03-02');

      expect(streak.current, 1,
          reason: 'Feb 30 is nothing, so the run restarts at Mar 2');
    });

    test('an absurd year never throws from a reading', () {
      // A corrupt save's lastDateKey: 275761 is the first year past
      // DateTime.utc's representable range, and every reading parses the
      // key through the same day-number arithmetic.
      const corrupt = DailyStreak(
        current: 5,
        best: 5,
        lastDateKey: '275761-01-01',
      );

      expect(corrupt.currentOn('2026-09-01'), 0);
      expect(corrupt.isBeforeLast('2026-09-01'), isFalse);
      expect(corrupt.nextRewardOn('2026-09-01'), DailyStreak.rewardCoins(1));
    });

    test('isBeforeLast names only days before the stored last day', () {
      const streak = DailyStreak(
        current: 2,
        best: 2,
        lastDateKey: '2026-09-03',
      );

      expect(streak.isBeforeLast('2026-09-02'), isTrue);
      expect(streak.isBeforeLast('2026-09-03'), isFalse);
      expect(streak.isBeforeLast('2026-09-04'), isFalse);
      expect(const DailyStreak().isBeforeLast('2026-09-02'), isFalse,
          reason: 'with no run recorded, nothing is before it');
      expect(streak.isBeforeLast('nonsense'), isFalse);
      expect(const DailyStreak(lastDateKey: 'nonsense')
          .isBeforeLast('2026-09-02'), isFalse);
    });
  });

  group('across daylight-saving transitions', () {
    // 2026's transition dates: the US spring-forward and fall-back days
    // (Mar 8, Nov 1) and the EU pair (Mar 29, Oct 25). The walk goes
    // through the tests' calendar-day helper — wall-clock steps, never
    // +24h — and the streak arithmetic itself never reads a clock, so a
    // 23- or 25-hour day must be one plain step in every host zone. The
    // expected keys are literals: a step that repeated or skipped the
    // transition day fails right here, before the run means anything.
    const transitions = <String, List<String>>{
      '2026-03-08': ['2026-03-07', '2026-03-08', '2026-03-09'],
      '2026-03-29': ['2026-03-28', '2026-03-29', '2026-03-30'],
      '2026-10-25': ['2026-10-24', '2026-10-25', '2026-10-26'],
      '2026-11-01': ['2026-10-31', '2026-11-01', '2026-11-02'],
    };
    for (final entry in transitions.entries) {
      final transition = DateTime.parse(entry.key);

      test('a run steps through ${entry.key}', () {
        final keys = [
          for (var i = -1; i <= 1; i++)
            DailyShift.dateKeyFor(calendarDaysFrom(transition, i)),
        ];
        expect(keys, entry.value,
            reason: 'a 23- or 25-hour day is still one calendar day');

        var streak = const DailyStreak();
        for (final key in keys) {
          streak = streak.afterCompletion(key);
        }
        expect(streak.current, 3);
        expect(streak.best, 3);
        expect(streak.currentOn(keys[2]), 3);
      });

      test('a missed day right after ${entry.key} resets the run', () {
        final before = entry.value[0];
        final after = entry.value[2];
        final streak = const DailyStreak()
            .afterCompletion(before)
            .afterCompletion(after);

        expect(streak.current, 1,
            reason: 'the transition day was skipped, so the run is broken');
        expect(streak.best, 1);
      });
    }
  });

  group('the declared reward', () {
    test('escalates 50 a day and caps at a week', () {
      expect(DailyStreak.rewardCoins(0), 0);
      expect(DailyStreak.rewardCoins(1), 50);
      expect(DailyStreak.rewardCoins(2), 100);
      expect(DailyStreak.rewardCoins(7), 350);
      expect(DailyStreak.rewardCoins(8), 350,
          reason: 'the eighth day pays the cap, flat');
      expect(DailyStreak.rewardCoins(30), 350);
    });

    test('nextRewardOn names the run the next completion would reach', () {
      final streak = const DailyStreak().afterCompletion('2026-09-01');

      expect(streak.nextRewardOn('2026-09-01'), 100,
          reason: 'a played day reads the next day\'s bonus');
      expect(streak.nextRewardOn('2026-09-02'), 100,
          reason: 'completing tomorrow extends the run to 2');
      expect(streak.nextRewardOn('2026-09-03'), 50,
          reason: 'a missed day restarts the run — and the rate');
    });

    test('the settlement record is the at-most-once guard', () {
      final settled =
          const DailyStreak().withRewardSettled('2026-09-01', 50);

      expect(settled.settledRewardFor('2026-09-01'), 50);
      expect(settled.settledRewardFor('2026-09-02'), isNull);
      expect(settled.withRewardSettled('2026-09-02', 0), same(settled),
          reason: 'a zero-coins settlement is a no-op');
    });
  });

  group('seeding from the daily history (pre-#281 saves)', () {
    test('an alive run seeds as current; the best always seeds', () {
      final streak = DailyStreak.fromHistory(
        [
          resultFor('2026-09-01'),
          resultFor('2026-09-02'),
          resultFor('2026-09-03'),
        ],
        todayKey: '2026-09-04',
      );

      expect(streak.current, 3,
          reason: 'the last day is yesterday, so the run is still alive');
      expect(streak.best, 3);
      expect(streak.lastDateKey, '2026-09-03');
      expect(streak.rewardDateKey, isEmpty,
          reason: 'nothing was ever paid under the old save');
    });

    test('a run ending today seeds as current too', () {
      final streak = DailyStreak.fromHistory(
        [resultFor('2026-09-01'), resultFor('2026-09-02')],
        todayKey: '2026-09-02',
      );

      expect(streak.current, 2);
      expect(streak.lastDateKey, '2026-09-02');
    });

    test('a dead run seeds as no current run, best kept', () {
      final streak = DailyStreak.fromHistory(
        [
          resultFor('2026-09-01'),
          resultFor('2026-09-02'),
          resultFor('2026-09-03'),
        ],
        todayKey: '2026-09-06',
      );

      expect(streak.current, 0,
          reason: 'a lost streak must not be resurrected by the seed');
      expect(streak.best, 3);
      expect(streak.lastDateKey, isEmpty);
    });

    test('gaps split the best run', () {
      final streak = DailyStreak.fromHistory(
        [
          resultFor('2026-09-01'),
          resultFor('2026-09-02'),
          resultFor('2026-09-05'),
          resultFor('2026-09-06'),
          resultFor('2026-09-07'),
        ],
        todayKey: '2026-09-08',
      );

      expect(streak.current, 3);
      expect(streak.best, 3);
    });

    test('an empty or unreadable history seeds nothing', () {
      expect(DailyStreak.fromHistory(const [], todayKey: '2026-09-01'),
          const DailyStreak());
      expect(
        DailyStreak.fromHistory([resultFor('nonsense')],
            todayKey: '2026-09-01'),
        const DailyStreak(),
      );
    });
  });

  group('DailyStreak JSON', () {
    test('round-trips every field', () {
      const streak = DailyStreak(
        current: 4,
        best: 12,
        lastDateKey: '2026-09-26',
        rewardDateKey: '2026-09-26',
        lastRewardCoins: 200,
      );
      final back = DailyStreak.fromJson(streak.toJson());

      expect(back.current, 4);
      expect(back.best, 12);
      expect(back.lastDateKey, '2026-09-26');
      expect(back.rewardDateKey, '2026-09-26');
      expect(back.lastRewardCoins, 200);
    });

    test('defaults missing keys instead of throwing', () {
      final streak = DailyStreak.fromJson(const {});

      expect(streak.current, 0);
      expect(streak.best, 0);
      expect(streak.lastDateKey, isEmpty);
      expect(streak.rewardDateKey, isEmpty);
      expect(streak.lastRewardCoins, 0);
      expect(streak.isVirgin, isTrue);
    });
  });
}
