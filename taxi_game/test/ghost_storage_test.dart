import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/models/ghost_trace.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'helpers/calendar_days.dart';

/// The ghost trace's persistence and best-run rules (issue #20): one
/// trace under its own key, replaced only by a strictly better run on
/// the same day's course (or the first run of a new course), corrupt
/// data recovering to "no ghost", and resets wiping it like progress.
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

  /// Calendar days ago, never now − n·24h (issue #196): a duration step
  /// can land on today across a DST change day, and a ghost planted "n
  /// days ago" for today is not another day's ghost at all.
  String daysAgoKey(int days) =>
      DailyShift.dateKeyFor(calendarDaysFromNow(-days));

  Future<bool> recordGhost({
    String? dateKey,
    int score = 100,
    List<int> samples = const [200, 0, 200, -100],
  }) {
    return gameState.recordDailyGhostRun(
      dateKey: dateKey ?? DailyShift.todayKey,
      score: score,
      banked: true,
      vehicleId: 'taxi_yellow',
      samples: samples,
    );
  }

  group('storage', () {
    test('round-trips a trace', () async {
      const trace = GhostTrace(
        dateKey: '2026-09-26',
        score: 480,
        banked: true,
        vehicleId: 'sedan_blue',
        samples: [200, 0, 205, -60],
      );
      await storage.saveDailyGhost(trace);
      expect(storage.loadDailyGhost()!.toJson(), trace.toJson());
    });

    test('is null when never written', () async {
      expect(storage.loadDailyGhost(), isNull);
    });

    test('recovers from a corrupt payload to no ghost, not a crash',
        () async {
      SharedPreferences.setMockInitialValues({
        StorageService.dailyGhostKey: '{definitely not json',
      });
      final corruptStorage = StorageService();
      await corruptStorage.init();
      expect(corruptStorage.loadDailyGhost(), isNull);
    });

    test('clear wipes the trace', () async {
      await recordGhost();
      expect(storage.loadDailyGhost(), isNotNull);
      await storage.clearDailyGhost();
      expect(storage.loadDailyGhost(), isNull);
    });
  });

  group('the best-run rule', () {
    test('a run with no path offers nothing', () async {
      final stored = await gameState.recordDailyGhostRun(
        dateKey: DailyShift.todayKey,
        score: 100,
        banked: true,
        vehicleId: 'taxi_yellow',
        samples: const [],
      );
      expect(stored, isFalse);
      expect(gameState.todayGhost, isNull);
    });

    test('the first trace for a day becomes the ghost', () async {
      expect(await recordGhost(score: 100), isTrue);
      expect(gameState.todayGhost, isNotNull);
      expect(gameState.todayGhost!.score, 100);
      expect(gameState.todayGhost!.dateKey, DailyShift.todayKey);
    });

    test('a lower or equal score never replaces it', () async {
      await recordGhost(score: 100);
      expect(await recordGhost(score: 99), isFalse);
      expect(gameState.todayGhost!.score, 100);
      expect(await recordGhost(score: 100), isFalse,
          reason: 'a tie keeps the older ghost, like the personal best');
      expect(gameState.todayGhost!.score, 100);
    });

    test('a strictly better run replaces it', () async {
      await recordGhost(score: 100);
      expect(await recordGhost(score: 260, samples: [200, 0, 210, -400]),
          isTrue);
      expect(gameState.todayGhost!.score, 260);
      expect(gameState.todayGhost!.samples, [200, 0, 210, -400]);
    });

    test('a new day replaces the stale trace regardless of score',
        () async {
      await recordGhost(dateKey: daysAgoKey(1), score: 9999);
      expect(gameState.todayGhost, isNull,
          reason: "yesterday's ghost is meaningless on today's course");

      expect(await recordGhost(score: 5), isTrue,
          reason: 'the first trace of a new course is the course only');
      expect(gameState.todayGhost!.score, 5);
    });

    test('ghostFor only matches its own day', () async {
      await recordGhost(dateKey: '2026-01-01', score: 100);
      expect(gameState.ghostFor('2026-01-01'), isNotNull);
      expect(gameState.ghostFor('2026-01-02'), isNull);
      expect(gameState.todayGhost, isNull);
    });
  });

  group('persistence and reset', () {
    test('a fresh service loads the stored ghost', () async {
      // The save comes first, as it does on a device: a shift that
      // records a ghost has long since written one, and a ghost left
      // without a save is cleared with it (issue #218).
      await gameState.save();
      await recordGhost(score: 321);
      final reloaded = GameStateService(storage);
      await reloaded.loadSaveData();
      expect(reloaded.todayGhost!.score, 321);
    });

    test('resetProgress wipes the ghost', () async {
      await recordGhost(score: 321);
      gameState.resetProgress();
      expect(gameState.todayGhost, isNull);
      expect(storage.loadDailyGhost(), isNull);
    });
  });
}
