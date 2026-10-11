import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/models/daily_result.dart';
import 'package:taxi_game/models/daily_streak.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'helpers/calendar_days.dart';

/// The on-device daily history (issue #19): one result per day, the first
/// one counting, persisted through the same local-storage pipe as the
/// shift history — and strictly local, like everything else in the game.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late GameStateService gameState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  DailyResult resultFor(String dateKey,
          {int score = 100, bool banked = true}) =>
      DailyResult(
        dateKey: dateKey,
        score: score,
        banked: banked,
        completedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  group('recording a completed daily', () {
    test('stores it and reads it back from storage', () async {
      // The save goes first, as it does on a device: a shift that records
      // a daily result has long since written one, and history left
      // without a save is cleared with it (issue #218).
      await gameState.save();
      // Calendar yesterday, never now − 24h (issue #196): on the 25-hour
      // fall-back day that is still today for the hour after midnight, and
      // the "yesterday" result would spend today's one attempt instead.
      final yesterday = DailyShift.dateKeyFor(calendarDaysFromNow(-1));
      await gameState.recordDailyResult(resultFor(yesterday, score: 340));

      expect(gameState.dailyHistory, hasLength(1));
      expect(gameState.dailyResultFor(yesterday)!.score, 340);

      // A fresh service over the same storage sees the same history.
      final reloaded = GameStateService(storage);
      await reloaded.loadSaveData();
      expect(reloaded.dailyResultFor(yesterday)!.score, 340);
    });

    test('the first result for a day is the one that counts', () async {
      final today = DailyShift.todayKey;
      await gameState.recordDailyResult(resultFor(today, score: 340));
      await gameState.recordDailyResult(resultFor(today, score: 999,
          banked: false));

      expect(gameState.dailyHistory, hasLength(1),
          reason: 'a second record for the same day is dropped, not merged');
      expect(gameState.dailyResultFor(today)!.score, 340);
      expect(gameState.todayDailyComplete, isTrue);
    });

    test('an unplayed day has no result', () {
      expect(gameState.dailyResultFor('1999-01-01'), isNull);
      expect(gameState.todayDailyComplete, isFalse);
      expect(gameState.todayDailyResult, isNull);
    });

    test('today reads as today, not as any stored day', () async {
      await gameState.recordDailyResult(
          resultFor('2000-01-01', score: 55));
      expect(gameState.todayDailyComplete, isFalse,
          reason: 'a stored past day does not spend today\'s attempt');
    });
  });

  group('the history window', () {
    test('trims the oldest days past maxRecordedDailyResults', () async {
      // The window is 400+ days, so the walk crosses 2020's DST change
      // days, where a +24h step repeats the fall-back calendar day
      // (zone-dependent; the southern hemisphere hits it at April's
      // fall-back while the walk is still anchored at midnight) — and the
      // "first result counts" rule then drops one of the 405 records as a
      // same-day duplicate. Calendar steps give one record per calendar
      // day in every zone.
      for (var i = 0; i < GameStateService.maxRecordedDailyResults + 5; i++) {
        final day = calendarDaysFrom(DateTime(2020, 1, 1), i);
        await gameState.recordDailyResult(
            resultFor(DailyShift.dateKeyFor(day), score: i));
      }

      expect(gameState.dailyHistory.length,
          GameStateService.maxRecordedDailyResults);
      // The five oldest fell off the front; the newest survived.
      expect(
          gameState.dailyResultFor(DailyShift.dateKeyFor(DateTime(2020, 1, 1))),
          isNull);
      expect(
        gameState.dailyHistory.last.score,
        GameStateService.maxRecordedDailyResults + 4,
      );
    });
  });

  group('resetting progress', () {
    test('wipes the daily history too', () async {
      await gameState.recordDailyResult(resultFor(DailyShift.todayKey));
      await gameState.resetProgress();

      expect(gameState.dailyHistory, isEmpty);
      expect(gameState.todayDailyComplete, isFalse,
          reason: 'a reset makes today playable again');

      final reloaded = GameStateService(storage);
      await reloaded.loadSaveData();
      expect(reloaded.dailyHistory, isEmpty,
          reason: 'the wipe reached storage, not just memory');
    });
  });

  group('the visible streak and its reward (issue #281)', () {
    int rewardFor(int streak) => DailyStreak.rewardCoins(streak);

    test('a first daily starts the run and pays the declared bonus', () async {
      final today = DailyShift.todayKey;
      await gameState.recordDailyResult(resultFor(today));

      expect(gameState.dailyStreak, 1);
      expect(gameState.dailyBestStreak, 1);
      expect(gameState.totalCoins, rewardFor(1));
      expect(gameState.settledDailyStreakRewardFor(today), rewardFor(1));
    });

    test('consecutive days extend the run and escalate the bonus', () async {
      for (var i = 2; i >= 0; i--) {
        await gameState.recordDailyResult(
            resultFor(DailyShift.dateKeyFor(calendarDaysFromNow(-i))));
      }

      expect(gameState.dailyStreak, 3);
      expect(gameState.dailyBestStreak, 3);
      expect(gameState.totalCoins, rewardFor(1) + rewardFor(2) + rewardFor(3));
      expect(gameState.settledDailyStreakRewardFor(DailyShift.todayKey),
          rewardFor(3));
    });

    test('a missed day breaks the run but keeps the best', () async {
      // Days -3 and -2 played; -1 skipped; today restarts at day one.
      await gameState.recordDailyResult(
          resultFor(DailyShift.dateKeyFor(calendarDaysFromNow(-3))));
      await gameState.recordDailyResult(
          resultFor(DailyShift.dateKeyFor(calendarDaysFromNow(-2))));
      await gameState.recordDailyResult(resultFor(DailyShift.todayKey));

      expect(gameState.dailyStreak, 1);
      expect(gameState.dailyBestStreak, 2);
      expect(gameState.totalCoins, rewardFor(1) + rewardFor(2) + rewardFor(1),
          reason: 'the restart pays the day-one rate again');
    });

    test('a missed day reads as 0 without erasing the stored run', () async {
      // A two-day run ending two days ago: nothing alive today.
      await gameState.recordDailyResult(
          resultFor(DailyShift.dateKeyFor(calendarDaysFromNow(-3))));
      await gameState.recordDailyResult(
          resultFor(DailyShift.dateKeyFor(calendarDaysFromNow(-2))));

      expect(gameState.dailyStreak, 0);
      expect(gameState.dailyBestStreak, 2);
      expect(
        gameState.dailyStreakOn(
            DailyShift.dateKeyFor(calendarDaysFromNow(-2))),
        2,
        reason: 'the day the run ended still reads it',
      );
    });

    test('the reward settles at most once per date', () async {
      final today = DailyShift.todayKey;
      await gameState.recordDailyResult(resultFor(today, score: 100));
      await gameState.recordDailyResult(
          resultFor(today, score: 999, banked: false));

      expect(gameState.dailyHistory, hasLength(1));
      expect(gameState.dailyStreak, 1);
      expect(gameState.totalCoins, rewardFor(1),
          reason: 'the duplicate record must not pay a second time');
      expect(gameState.settledDailyStreakRewardFor(today), rewardFor(1));
    });

    /// Writes a save straight to storage — the shape a settled day's
    /// save has when its history write did not land (the split-write
    /// window, issue #281). [dailyStreak] is the raw JSON block.
    Future<void> seedSave({
      required int totalCoins,
      required Map<String, dynamic> dailyStreak,
    }) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        StorageService.saveDataKey,
        jsonEncode({
          'currentLevel': 11,
          'totalCoins': totalCoins,
          'totalGems': 0,
          'unlockedVehicles': ['taxi_yellow'],
          'selectedVehicle': 'taxi_yellow',
          'achievements': <String, bool>{},
          'settings': Settings.createDefault().toJson(),
          'dailyStreak': dailyStreak,
        }),
      );
    }

    test('a day the settlement already counted cannot extend or pay again',
        () async {
      // The save counted today and paid its bonus; the history lost the
      // day (the split-write state the kill test below simulates).
      final today = DailyShift.todayKey;
      await seedSave(totalCoins: rewardFor(1), dailyStreak: {
        'current': 1,
        'best': 1,
        'lastDateKey': today,
        'rewardDateKey': today,
        'lastRewardCoins': rewardFor(1),
      });

      final reloaded = GameStateService(storage);
      await reloaded.loadSaveData();
      await reloaded.recordDailyResult(resultFor(today, score: 999));

      expect(reloaded.totalCoins, rewardFor(1),
          reason: 'the settled day pays nothing again');
      expect(reloaded.dailyStreak, 1, reason: 'and extends nothing again');
      expect(reloaded.dailyBestStreak, 1);
      expect(reloaded.dailyHistory, hasLength(1),
          reason: 'the replay only fills the history back in');
    });

    test('a counted day with no settled reward pays nothing on replay',
        () async {
      // Defense-only shape: the block counted today with no reward on
      // record. The migration seed cannot produce it — fromHistory leaves
      // its day in the history, and the caller guard would drop the
      // replay — but the last-counted-day half of the settlement guard
      // must hold on its own.
      final today = DailyShift.todayKey;
      await seedSave(totalCoins: 0, dailyStreak: {
        'current': 1,
        'best': 1,
        'lastDateKey': today,
      });

      final reloaded = GameStateService(storage);
      await reloaded.loadSaveData();
      await reloaded.recordDailyResult(resultFor(today, score: 999));

      expect(reloaded.totalCoins, 0,
          reason: 'no reward may be invented for an already-counted day');
      expect(reloaded.dailyStreak, 1);
    });

    test('a kill between the record\'s two writes cannot undercount or '
        'pay twice', () async {
      final yesterday = DailyShift.dateKeyFor(calendarDaysFromNow(-1));
      final today = DailyShift.todayKey;
      await gameState.recordDailyResult(resultFor(yesterday));

      // The kill: the first write lands, the second never starts. With
      // the save written first, that leaves the save ahead of the
      // history — the settlement record intact, the run not one short.
      final killing = _KillAtSecondWriteStorage();
      await killing.init();
      final killed = GameStateService(killing);
      await killed.loadSaveData();
      await expectLater(
        killed.recordDailyResult(resultFor(today, score: 340)),
        throwsA(isA<StateError>()),
      );

      // A fresh stack over the same store sees what survived the kill.
      final reloaded = GameStateService(storage);
      await reloaded.loadSaveData();
      expect(reloaded.dailyStreak, 2,
          reason: 'the run counted today; it must not read one short');
      expect(reloaded.dailyBestStreak, 2);
      expect(reloaded.totalCoins, rewardFor(1) + rewardFor(2),
          reason: "today's bonus landed with the save");
      expect(reloaded.dailyResultFor(today), isNull,
          reason: 'the killed write was the history one');

      // The day replays safely: the history fills in, nothing pays or
      // extends twice.
      await reloaded.recordDailyResult(resultFor(today, score: 999));
      expect(reloaded.dailyStreak, 2);
      expect(reloaded.dailyBestStreak, 2);
      expect(reloaded.totalCoins, rewardFor(1) + rewardFor(2));
      expect(reloaded.dailyResultFor(today)!.score, 999);
    });

    test('a terminal save failure holds the history back, so the day '
        'replays in full', () async {
      final yesterday = DailyShift.dateKeyFor(calendarDaysFromNow(-1));
      final today = DailyShift.todayKey;
      // A real save from yesterday, as on a device: the durable state a
      // stranded day would sit beside.
      await gameState.recordDailyResult(resultFor(yesterday));
      final coinsAfterYesterday = gameState.totalCoins;

      // Today's record runs on a storage whose save writes fail
      // terminally.
      final failing = _FailingSaveStorage();
      await failing.init();
      final service = GameStateService(failing);
      await service.loadSaveData();
      await service.recordDailyResult(resultFor(today, score: 340));
      expect(failing.saveAttempts, 1,
          reason: 'precondition: the record went through the failing save');

      // The failed save and the held-back history: the durable store
      // still says yesterday only, and no history-ahead state exists.
      final reloaded = GameStateService(storage);
      await reloaded.loadSaveData();
      expect(reloaded.dailyResultFor(today), isNull,
          reason: 'the history write never ran beside a failed save');
      expect(reloaded.dailyStreak, 1, reason: 'the run still ends yesterday');
      expect(reloaded.totalCoins, coinsAfterYesterday);

      // The day replays in full: the run extends and the bonus settles.
      await reloaded.recordDailyResult(resultFor(today, score: 340));
      expect(reloaded.dailyStreak, 2);
      expect(reloaded.dailyBestStreak, 2);
      expect(reloaded.totalCoins, coinsAfterYesterday + rewardFor(2));
      expect(reloaded.settledDailyStreakRewardFor(today), rewardFor(2));
    });

    test('a completion older than the stored run settles nothing', () async {
      final yesterday = DailyShift.dateKeyFor(calendarDaysFromNow(-1));
      final today = DailyShift.todayKey;
      final tomorrow = DailyShift.dateKeyFor(calendarDaysFromNow(1));
      await gameState.recordDailyResult(resultFor(today));
      final coinsAfterToday = gameState.totalCoins;

      // The clock moves backward: a past course is completed after
      // today's. It may not mint a backdated bonus or move the run back.
      await gameState.recordDailyResult(resultFor(yesterday, score: 500));

      expect(gameState.totalCoins, coinsAfterToday,
          reason: 'no backdated bonus');
      expect(gameState.dailyStreak, 1, reason: 'the run still ends today');
      expect(gameState.dailyBestStreak, 1);
      expect(gameState.dailyHistory, hasLength(2),
          reason: 'the shift is still a record — only the settlement '
              'ignores it');

      // Forward again: the run continues from the stored last day.
      await gameState.recordDailyResult(resultFor(tomorrow));
      expect(gameState.dailyStreakOn(tomorrow), 2,
          reason: 'the run picks up from the day it ended on');
      expect(gameState.dailyBestStreak, 2);
      expect(gameState.totalCoins, coinsAfterToday + rewardFor(2));
    });

    test('the run and the settled reward survive a restart', () async {
      final yesterday = DailyShift.dateKeyFor(calendarDaysFromNow(-1));
      final today = DailyShift.todayKey;
      // The save goes first, as it does on a device (issue #218).
      await gameState.save();
      await gameState.recordDailyResult(resultFor(yesterday));
      await gameState.recordDailyResult(resultFor(today));

      final reloaded = GameStateService(storage);
      await reloaded.loadSaveData();

      expect(reloaded.dailyStreak, 2);
      expect(reloaded.dailyBestStreak, 2);
      expect(reloaded.totalCoins, rewardFor(1) + rewardFor(2));
      expect(reloaded.settledDailyStreakRewardFor(today), rewardFor(2));

      // A replay of the settled day still pays nothing after the load.
      await reloaded.recordDailyResult(resultFor(today, score: 1));
      expect(reloaded.totalCoins, rewardFor(1) + rewardFor(2));
    });

    test('a run crosses the fall-back transition without breaking', () async {
      // 2026-11-01 is the 25-hour US fall-back day; the calendar steps
      // keep the three keys three consecutive days in any host zone.
      for (var i = 0; i <= 2; i++) {
        await gameState.recordDailyResult(resultFor(DailyShift.dateKeyFor(
            calendarDaysFrom(DateTime(2026, 10, 31), i))));
      }

      expect(gameState.dailyStreakOn('2026-11-02'), 3,
          reason: 'three calendar days, one 25-hour day among them');
      expect(gameState.dailyBestStreak, 3);
      expect(gameState.totalCoins, rewardFor(1) + rewardFor(2) + rewardFor(3));
    });

    test('a run crosses the spring-forward transition without breaking',
        () async {
      // 2026-03-08 is the 23-hour US spring-forward day.
      for (var i = 0; i <= 2; i++) {
        await gameState.recordDailyResult(resultFor(DailyShift.dateKeyFor(
            calendarDaysFrom(DateTime(2026, 3, 7), i))));
      }

      expect(gameState.dailyStreakOn('2026-03-09'), 3,
          reason: 'three calendar days, one 23-hour day among them');
      expect(gameState.totalCoins, rewardFor(1) + rewardFor(2) + rewardFor(3));
    });

    test('a missed transition day resets the run', () async {
      // 2026-11-01 skipped between the 31st and the 2nd.
      await gameState.recordDailyResult(
          resultFor(DailyShift.dateKeyFor(DateTime(2026, 10, 31, 12))));
      await gameState.recordDailyResult(
          resultFor(DailyShift.dateKeyFor(DateTime(2026, 11, 2, 12))));

      expect(gameState.dailyStreakOn('2026-11-02'), 1,
          reason: 'the skipped 25-hour day broke the run');
      expect(gameState.dailyBestStreak, 1);
    });

    test('resetting progress wipes the streak and its settlement record',
        () async {
      await gameState.recordDailyResult(resultFor(DailyShift.todayKey));
      await gameState.resetProgress();

      expect(gameState.dailyStreak, 0);
      expect(gameState.dailyBestStreak, 0);
      expect(gameState.totalCoins, 0);
      expect(
          gameState.settledDailyStreakRewardFor(DailyShift.todayKey), isNull);
    });

    test('a save written before the streak block seeds from the history',
        () async {
      final yesterday = DailyShift.dateKeyFor(calendarDaysFromNow(-1));
      final twoDaysAgo = DailyShift.dateKeyFor(calendarDaysFromNow(-2));
      final threeDaysAgo = DailyShift.dateKeyFor(calendarDaysFromNow(-3));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        StorageService.dailyHistoryKey,
        jsonEncode([
          resultFor(threeDaysAgo).toJson(),
          resultFor(twoDaysAgo).toJson(),
          resultFor(yesterday).toJson(),
        ]),
      );
      // The pre-#281 save shape: no dailyStreak key at all.
      await prefs.setString(
        StorageService.saveDataKey,
        jsonEncode({
          'currentLevel': 11,
          'totalCoins': 40,
          'totalGems': 0,
          'unlockedVehicles': ['taxi_yellow'],
          'selectedVehicle': 'taxi_yellow',
          'achievements': <String, bool>{},
          'settings': Settings.createDefault().toJson(),
        }),
      );

      final reloaded = GameStateService(storage);
      await reloaded.loadSaveData();

      expect(reloaded.dailyStreak, 3,
          reason: 'the run that reaches yesterday is still alive');
      expect(reloaded.dailyBestStreak, 3);
      expect(reloaded.settledDailyStreakRewardFor(yesterday), isNull,
          reason: 'no reward was ever paid under the old save');
      expect(reloaded.totalCoins, 40,
          reason: 'the seed shows the streak, it pays nothing');

      // The seed persists: the next load reads it back as stored state.
      final again = GameStateService(storage);
      await again.loadSaveData();
      expect(again.dailyStreak, 3);
      expect(again.dailyBestStreak, 3);
    });
  });

  group('DailyResult JSON', () {
    test('round-trips', () {
      const result = DailyResult(
        dateKey: '2026-09-26',
        score: 340,
        banked: true,
        completedAtMs: 1780000000000,
      );
      final back = DailyResult.fromJson(result.toJson());
      expect(back.dateKey, result.dateKey);
      expect(back.score, result.score);
      expect(back.banked, result.banked);
      expect(back.completedAtMs, result.completedAtMs);
    });

    test('defaults missing keys instead of throwing', () {
      final result = DailyResult.fromJson(const {});
      expect(result.dateKey, '');
      expect(result.score, 0);
      expect(result.banked, isFalse);
      expect(result.completedAtMs, 0);
    });
  });
}

/// A storage that lets a record's first write land and kills the process
/// at the second — the shape of a crash between the record's two writes.
/// The kill is a thrown error the test catches; the durable store keeps
/// the first write, exactly as a device would.
class _KillAtSecondWriteStorage extends StorageService {
  int _writes = 0;

  void _reachWrite() {
    _writes++;
    if (_writes == 2) {
      throw StateError('simulated process kill at the second write');
    }
  }

  @override
  Future<bool> saveSaveData(SaveData data) {
    _reachWrite();
    return super.saveSaveData(data);
  }

  @override
  Future<void> saveDailyHistory(List<DailyResult> results) {
    _reachWrite();
    return super.saveDailyHistory(results);
  }
}

/// A storage whose save writes fail terminally — both attempts refused,
/// the same `false` the real retry path returns — while every other
/// write lands. The shape of a refused save beside a successful history
/// write: the state the record's history gate must prevent.
class _FailingSaveStorage extends StorageService {
  int saveAttempts = 0;

  @override
  Future<bool> saveSaveData(SaveData data) async {
    saveAttempts++;
    return false;
  }
}
