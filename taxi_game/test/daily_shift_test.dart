import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/systems/endless_course.dart';

/// The Date-seeded Daily Shift's pure core (issue #19): the same calendar
/// day must derive the same run seed on every device — that is the whole
/// shared-course trick, and it has to hold without a server.
void main() {
  group('DailyShift.dateKeyFor', () {
    test('formats the local calendar day, zero-padded', () {
      expect(DailyShift.dateKeyFor(DateTime(2026, 9, 26)), '2026-09-26');
      expect(DailyShift.dateKeyFor(DateTime(2027, 1, 5)), '2027-01-05');
      expect(DailyShift.dateKeyFor(DateTime(2099, 12, 31)), '2099-12-31');
    });

    test('reads only the calendar fields, not the clock', () {
      final morning = DateTime(2026, 9, 26, 0, 0, 1);
      final night = DateTime(2026, 9, 26, 23, 59, 59);
      expect(DailyShift.dateKeyFor(morning), DailyShift.dateKeyFor(night),
          reason: 'one day is one key, however late the shift runs');
    });

    test('todayKey is today on this device', () {
      final now = DateTime.now();
      expect(DailyShift.todayKey,
          DailyShift.dateKeyFor(DateTime(now.year, now.month, now.day)));
    });
  });

  group('DailyShift.seedForDateKey', () {
    // Pinned literals, not a function compared with itself (issue #180):
    // this test used to assert seedForDateKey(k) == seedForDateKey(k) —
    // f(x) is f(x), unfalsifiable — so an edited date hash would have
    // rewritten every day's course for every player with the suite green.
    // The three values below are the shipped hash's output, computed once
    // from the arithmetic as it stands in daily_shift.dart. They are a
    // frozen contract, not a snapshot: a failure here means the hash
    // changed, and the fix is to revert that change — never to update the
    // literals to match. The hash's layout is load-bearing ("once shipped
    // it must never be 'improved'", daily_shift.dart) because each stored
    // ghost replays its day's course via seedForDateKey(result.dateKey)
    // in daily_screen.dart — a new hash sends every historical trace onto
    // a city it never ran, and the same day stops being the same course
    // worldwide.
    test('is frozen: known days have these exact seeds', () {
      expect(DailyShift.seedForDateKey('2026-09-26'), 0x3196A8D6,
          reason: '2026-09-26 stays 831957206');
      expect(DailyShift.seedForDateKey('2027-01-01'), 0x087FB9EC,
          reason: '2027-01-01 stays 142588396');
      expect(DailyShift.seedForDateKey('1999-12-31'), 0x3C4AF755,
          reason: '1999-12-31 stays 1011545941');
    });

    test('neighbouring days land on unrelated seeds', () {
      var differing = 0;
      var day = DateTime(2026, 9, 1);
      for (var i = 0; i < 30; i++) {
        final key = DailyShift.dateKeyFor(day);
        final nextKey = DailyShift.dateKeyFor(day.add(const Duration(days: 1)));
        if (DailyShift.seedForDateKey(key) !=
            DailyShift.seedForDateKey(nextKey)) {
          differing++;
        }
        day = day.add(const Duration(days: 1));
      }
      expect(differing, 30, reason: 'every new day is genuinely a new city');
    });

    test('a full year of days yields distinct seeds in the 30-bit space',
        () {
      final seeds = <int>{};
      var day = DateTime(2026, 1, 1);
      while (day.year == 2026) {
        final seed = DailyShift.seedForDateKey(DailyShift.dateKeyFor(day));
        expect(seed, greaterThanOrEqualTo(0), reason: '$day non-negative');
        expect(seed, lessThan(0x40000000), reason: '$day 30-bit seed space');
        seeds.add(seed);
        day = day.add(const Duration(days: 1));
      }
      expect(seeds.length, 365, reason: 'no two days of the year collide');
    });

    test('the derived seed reproduces one shared course', () {
      const key = '2026-09-26';
      final a = EndlessCourse(seed: DailyShift.seedForDateKey(key));
      final b = EndlessCourse(seed: DailyShift.seedForDateKey(key));

      for (var i = 0; i < 50; i++) {
        final fa = a.fare(i);
        final fb = b.fare(i);
        expect(fa.pickup, fb.pickup, reason: 'fare $i pickup');
        expect(fa.dropoff, fb.dropoff, reason: 'fare $i dropoff');
        expect(fa.reward, fb.reward, reason: 'fare $i reward');
      }
    });

    test('rejects keys that are not yyyy-MM-dd', () {
      expect(() => DailyShift.seedForDateKey('2026-9-26'), throwsArgumentError);
      expect(() => DailyShift.seedForDateKey('nonsense'), throwsArgumentError);
    });
  });
}
