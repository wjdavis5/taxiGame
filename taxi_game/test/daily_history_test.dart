import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/models/daily_result.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';

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
      final yesterday =
          DailyShift.dateKeyFor(DateTime.now().subtract(const Duration(days: 1)));
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
      for (var i = 0; i < GameStateService.maxRecordedDailyResults + 5; i++) {
        final day = DateTime(2020, 1, 1).add(Duration(days: i));
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
      gameState.resetProgress();

      expect(gameState.dailyHistory, isEmpty);
      expect(gameState.todayDailyComplete, isFalse,
          reason: 'a reset makes today playable again');

      final reloaded = GameStateService(storage);
      await reloaded.loadSaveData();
      expect(reloaded.dailyHistory, isEmpty,
          reason: 'the wipe reached storage, not just memory');
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
