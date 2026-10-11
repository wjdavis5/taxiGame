import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/systems/weekly_gauntlet.dart';
import 'package:taxi_game/models/weekly_gauntlet_record.dart';

import 'helpers/calendar_days.dart';

/// The offline Weekly Gauntlet's pure core (issue #288): the local week
/// key, the deterministic objective/modifier draw, and the persisted
/// best. The whole feature is a contract with history — a stored best
/// names the week whose course it was set on — so the derivations are
/// pinned with literals, never a function compared with itself.
void main() {
  group('WeeklyGauntlet.weekKeyFor', () {
    test('numbers ISO weeks, Thursday-anchored', () {
      // The frozen ISO-8601 facts the derivation has to match: week 1 is
      // the week containing the year's first Thursday, and the year in
      // the key is that Thursday's.
      expect(WeeklyGauntlet.weekKeyFor(DateTime(2026, 1, 1)), '2026-W01');
      expect(WeeklyGauntlet.weekKeyFor(DateTime(2026, 1, 4)), '2026-W01',
          reason: 'the Sunday still belongs to the week that began Monday');
      expect(WeeklyGauntlet.weekKeyFor(DateTime(2026, 1, 5)), '2026-W02');
      expect(WeeklyGauntlet.weekKeyFor(DateTime(2025, 12, 29)), '2026-W01',
          reason: 'a Monday can belong to the next ISO year');
      expect(WeeklyGauntlet.weekKeyFor(DateTime(2026, 12, 31)), '2026-W53',
          reason: '2026 starts on a Thursday: a 53-week ISO year');
      expect(WeeklyGauntlet.weekKeyFor(DateTime(2027, 1, 1)), '2026-W53',
          reason: 'New Year is not a week boundary');
      expect(WeeklyGauntlet.weekKeyFor(DateTime(2027, 1, 4)), '2027-W01');
      expect(WeeklyGauntlet.weekKeyFor(DateTime(2028, 1, 1)), '2027-W52');
      expect(WeeklyGauntlet.weekKeyFor(DateTime(2020, 12, 31)), '2020-W53');
      expect(WeeklyGauntlet.weekKeyFor(DateTime(2021, 1, 1)), '2020-W53');
    });

    test('reads only calendar fields, so one day cannot move the week', () {
      final morning = DateTime(2026, 9, 26, 0, 0, 1);
      final night = DateTime(2026, 9, 26, 23, 59, 59);
      expect(WeeklyGauntlet.weekKeyFor(morning),
          WeeklyGauntlet.weekKeyFor(night));
    });

    test('a year of days yields exactly the year\'s ISO weeks', () {
      // Calendar steps, never +24h (issue #196): a duration step repeats
      // the fall-back day's key in some zones, which would make this
      // walk count phantom weeks.
      final keys = <String>{};
      var day = DateTime(2026, 1, 1);
      while (day.year == 2026) {
        keys.add(WeeklyGauntlet.weekKeyFor(day));
        day = calendarDaysFrom(day, 1);
      }
      // 2026 is a 53-week ISO year (January 1 is a Thursday); the year's
      // first days belong to 2026-W01 and its last to 2026-W53.
      expect(keys.length, 53, reason: 'no phantom weeks, no merged weeks');
      expect(keys.contains('2026-W01'), isTrue);
      expect(keys.contains('2026-W53'), isTrue);
    });
  });

  group('WeeklyGauntlet.weekKeyForDateKey', () {
    test('formats the day key through the same calendar', () {
      expect(WeeklyGauntlet.weekKeyForDateKey('2026-01-01'), '2026-W01');
      expect(WeeklyGauntlet.weekKeyForDateKey('2026-12-31'), '2026-W53');
    });

    test('rejects keys that are not yyyy-MM-dd', () {
      expect(() => WeeklyGauntlet.weekKeyForDateKey('2026-1-1'),
          throwsArgumentError);
      expect(() => WeeklyGauntlet.weekKeyForDateKey('nonsense'),
          throwsArgumentError);
      expect(() => WeeklyGauntlet.weekKeyForDateKey('2026-02-30'),
          throwsArgumentError,
          reason: 'a day DateTime would normalize was never a calendar day');
    });
  });

  group('WeeklyGauntlet.currentWeekKey', () {
    test('follows the Daily clock — one calendar model, two rhythms', () {
      DailyShift.clock = () => DateTime(2026, 10, 7, 9, 30);
      addTearDown(() => DailyShift.clock = DateTime.now);
      expect(WeeklyGauntlet.currentWeekKey, '2026-W41');
      expect(WeeklyGauntlet.currentWeekKey,
          WeeklyGauntlet.weekKeyForDateKey(DailyShift.todayKey));
    });
  });

  group('WeeklyGauntlet.seedForWeek', () {
    // Pinned literals, not a function compared with itself (issue #180's
    // rule): these are the shipped hash's outputs, computed once from the
    // arithmetic as it stands in weekly_gauntlet.dart. A failure here
    // means the hash changed, and the fix is to revert that change —
    // never to update the literals — because a stored gauntlet best names
    // the week whose course it was set on.
    test('is frozen: known weeks have these exact seeds', () {
      expect(WeeklyGauntlet.seedForWeek('2026-W01'), 689301980);
      expect(WeeklyGauntlet.seedForWeek('2026-W41'), 1024157976);
      expect(WeeklyGauntlet.seedForWeek('2026-W53'), 168370447);
      expect(WeeklyGauntlet.seedForWeek('2027-W01'), 223883763);
    });

    test('neighbouring weeks land on unrelated seeds in the 30-bit space',
        () {
      final seeds = <int>{};
      var day = DateTime(2026, 1, 5);
      while (day.year == 2026) {
        final seed = WeeklyGauntlet.seedForWeek(
            WeeklyGauntlet.weekKeyFor(day));
        expect(seed, greaterThanOrEqualTo(0));
        expect(seed, lessThan(0x40000000));
        seeds.add(seed);
        day = calendarDaysFrom(day, 7);
      }
      expect(seeds.length, 52,
          reason: 'the Mondays of 2026 are 52 distinct weeks from W02 on');
    });

    test('rejects keys that are not yyyy-Www', () {
      expect(() => WeeklyGauntlet.seedForWeek('2026-W1'),
          throwsArgumentError);
      expect(() => WeeklyGauntlet.seedForWeek('2026-41'),
          throwsArgumentError);
      expect(() => WeeklyGauntlet.seedForWeek('nonsense'),
          throwsArgumentError);
    });
  });

  group('WeeklyGauntlet.planForWeek', () {
    test('is frozen: known weeks draw these exact plans', () {
      final w01 = WeeklyGauntlet.planForWeek('2026-W01');
      expect(w01.seed, 689301980);
      expect(w01.objective, GauntletObjective.chain);
      expect(w01.modifier, GauntletModifier.suddenDeath);

      final w41 = WeeklyGauntlet.planForWeek('2026-W41');
      expect(w41.seed, 1024157976);
      expect(w41.objective, GauntletObjective.chain);
      expect(w41.modifier, GauntletModifier.doubleFares);

      final w53 = WeeklyGauntlet.planForWeek('2026-W53');
      expect(w53.seed, 168370447);
      expect(w53.objective, GauntletObjective.distance);
      expect(w53.modifier, GauntletModifier.doubleFares);

      final y27w01 = WeeklyGauntlet.planForWeek('2027-W01');
      expect(y27w01.seed, 223883763);
      expect(y27w01.objective, GauntletObjective.distance);
      expect(y27w01.modifier, GauntletModifier.suddenDeath);
    });

    test('same week key yields the same plan on every derivation', () {
      final a = WeeklyGauntlet.planForWeek('2026-W41');
      final b = WeeklyGauntlet.planForWeek('2026-W41');
      expect(a.objective, b.objective);
      expect(a.modifier, b.modifier);
      expect(a.seed, b.seed);
      expect(a.weekKey, '2026-W41');
    });

    test('a year of weeks varies both the objective and the modifier', () {
      final objectives = <GauntletObjective>{};
      final modifiers = <GauntletModifier>{};
      var day = DateTime(2026, 1, 1);
      while (day.year == 2026) {
        final plan = WeeklyGauntlet.planForWeek(
            WeeklyGauntlet.weekKeyFor(day));
        objectives.add(plan.objective);
        modifiers.add(plan.modifier);
        day = calendarDaysFrom(day, 1);
      }
      expect(objectives, GauntletObjective.values.toSet(),
          reason: 'every objective should appear across a year');
      expect(modifiers, GauntletModifier.values.toSet(),
          reason: 'every modifier should appear across a year');
    });

    test('the plan seed is the week seed the course is built from', () {
      const key = '2026-W41';
      expect(WeeklyGauntlet.planForWeek(key).seed,
          WeeklyGauntlet.seedForWeek(key));
    });
  });

  group('GauntletPlan progress', () {
    const key = '2026-W41';

    test('a record from another week reads as unplayed', () {
      final plan = WeeklyGauntlet.planForWeek(key);
      const stale = WeeklyGauntletRecord(
        weekKey: '2026-W40',
        bestScore: 9999,
        bestFares: 99,
        bestChain: 9,
        bestDistanceMetres: 9999,
      );
      expect(plan.progressIn(stale), 0);
      expect(plan.objectiveMet(stale), isFalse);
    });

    test('the week\'s own best is measured against the bar', () {
      final plan = WeeklyGauntlet.planForWeek('2026-W41');
      // 2026-W41's objective is the x6 chain; the record's best chain
      // decides whether the week is cleared.
      final record = WeeklyGauntletRecord(
        weekKey: key,
        bestChain: plan.objective.target - 1,
      );
      expect(plan.progressIn(record), plan.objective.target - 1);
      expect(plan.objectiveMet(record), isFalse);
      expect(
        plan.objectiveMet(
            const WeeklyGauntletRecord(weekKey: key, bestChain: 6)),
        isTrue,
      );
    });

    test('every objective reads its own field of the record', () {
      const record = WeeklyGauntletRecord(
        weekKey: 'x',
        bestScore: 1,
        bestFares: 2,
        bestChain: 3,
        bestDistanceMetres: 4,
      );
      expect(GauntletObjective.score.progressIn(record), 1);
      expect(GauntletObjective.fares.progressIn(record), 2);
      expect(GauntletObjective.chain.progressIn(record), 3);
      expect(GauntletObjective.distance.progressIn(record), 4);
    });
  });

  group('WeeklyGauntletRecord.afterRun', () {
    test('the first run of a week seeds every field', () {
      final record = const WeeklyGauntletRecord().afterRun(
        weekKey: '2026-W41',
        score: 1200,
        fares: 7,
        bestChain: 3,
        distanceMetres: 1500,
      );
      expect(record.weekKey, '2026-W41');
      expect(record.bestScore, 1200);
      expect(record.bestFares, 7);
      expect(record.bestChain, 3);
      expect(record.bestDistanceMetres, 1500);
    });

    test('same week keeps each field\'s maximum', () {
      final first = const WeeklyGauntletRecord().afterRun(
        weekKey: '2026-W41',
        score: 1200,
        fares: 7,
        bestChain: 3,
        distanceMetres: 1500,
      );
      final second = first.afterRun(
        weekKey: '2026-W41',
        score: 900,
        fares: 9,
        bestChain: 2,
        distanceMetres: 2100,
      );
      expect(second.bestScore, 1200, reason: 'a worse score never lowers it');
      expect(second.bestFares, 9);
      expect(second.bestChain, 3);
      expect(second.bestDistanceMetres, 2100);
    });

    test('an unchanged run returns the identical instance', () {
      final first = const WeeklyGauntletRecord().afterRun(
        weekKey: '2026-W41',
        score: 1200,
        fares: 7,
        bestChain: 3,
        distanceMetres: 1500,
      );
      final same = first.afterRun(
        weekKey: '2026-W41',
        score: 1200,
        fares: 7,
        bestChain: 3,
        distanceMetres: 1500,
      );
      expect(identical(same, first), isTrue,
          reason: 'callers skip the save on an identical instance');
    });

    test('a later week replaces the record outright', () {
      final first = const WeeklyGauntletRecord().afterRun(
        weekKey: '2026-W41',
        score: 5000,
        fares: 20,
        bestChain: 8,
        distanceMetres: 4000,
      );
      final next = first.afterRun(
        weekKey: '2026-W42',
        score: 10,
        fares: 1,
        bestChain: 1,
        distanceMetres: 5,
      );
      expect(next.weekKey, '2026-W42');
      expect(next.bestScore, 10, reason: 'a new week starts over');
      expect(next.bestFares, 1);
    });

    test('an older week is ignored and returns the identical instance', () {
      final current = const WeeklyGauntletRecord().afterRun(
        weekKey: '2026-W41',
        score: 5000,
        fares: 20,
        bestChain: 8,
        distanceMetres: 4000,
      );
      final stale = current.afterRun(
        weekKey: '2026-W40',
        score: 99999,
        fares: 99,
        bestChain: 9,
        distanceMetres: 99999,
      );
      expect(identical(stale, current), isTrue,
          reason: 'a backward clock cannot overwrite the current week');
    });
  });

  group('WeeklyGauntletRecord JSON', () {
    test('round-trips every field', () {
      const record = WeeklyGauntletRecord(
        weekKey: '2026-W41',
        bestScore: 4321,
        bestFares: 12,
        bestChain: 5,
        bestDistanceMetres: 2870,
      );
      expect(WeeklyGauntletRecord.fromJson(record.toJson()), record);
    });

    test('missing keys — an older build\'s block — read as empty', () {
      final record = WeeklyGauntletRecord.fromJson(const {});
      expect(record.weekKey, '');
      expect(record.bestScore, 0);
      expect(record.bestFares, 0);
      expect(record.bestChain, 0);
      expect(record.bestDistanceMetres, 0);
    });
  });

  group('no network, account, or leaderboard path (issue #288)', () {
    // The feature's whole point is that the week is computed, never
    // fetched. The app-wide zero-network claim is the privacy manifest's;
    // the first test keeps every shipped lib file inside it, the second
    // keeps the gauntlet's own surface free of the account/leaderboard
    // words a hidden backend path would need.
    test('no shipped lib surface carries network machinery', () {
      // A denylist heuristic, not a proof: it catches the common
      // machinery a network path would need — HTTP clients, sockets,
      // remote image loads, URI fetches — in every file that ships.
      const denied = <String>[
        'package:http',
        'package:dio',
        'web_socket_channel',
        'HttpClient',
        'WebSocket',
        'RawSocket',
        'InternetAddress',
        'Socket(',
        'Uri.https',
        'Uri.http',
        'Image.network',
        'NetworkImage',
      ];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      for (final file in files) {
        final text = file.readAsStringSync();
        for (final token in denied) {
          expect(text.contains(token), isFalse,
              reason: '${file.path} carries "$token"');
        }
      }
    });

    test('the gauntlet surface names no account or leaderboard path', () {
      const denied = <String>[
        'dart:io',
        'dart:html',
        'leaderboard',
        'account',
        'signIn',
        'oauth',
      ];
      final files = <File>[
        File('lib/game/systems/weekly_gauntlet.dart'),
        File('lib/models/weekly_gauntlet_record.dart'),
      ];
      for (final file in files) {
        expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
        final text = file.readAsStringSync();
        for (final token in denied) {
          expect(text.contains(token), isFalse,
              reason: '${file.path} carries "$token"');
        }
      }
    });
  });
}
