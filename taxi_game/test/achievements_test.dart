import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/data/vehicle_catalog.dart';
import 'package:taxi_game/models/achievements.dart';
import 'package:taxi_game/models/daily_result.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The achievement system (issue #21): definitions measure an immutable
/// snapshot, evaluation writes earned ids into the save's `achievements`
/// map — the map that existed from the first schema and was never
/// written by gameplay until now — and every award persists and queues
/// an unlock for the UI that caused it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  RunRecord run({
    int chain = 1,
    double distancePx = 1000,
    bool banked = true,
    int livesLost = 0,
    int fares = 1,
  }) {
    return RunRecord(
      endedAtMs: 0,
      distancePx: distancePx,
      score: 120,
      faresDelivered: fares,
      longestChain: chain,
      livesLost: livesLost,
      lifeLossDistancesPx: List.filled(livesLost, 500.0),
      banked: banked,
      durationSeconds: 60,
    );
  }

  group('the catalog', () {
    test('covers the five tracks the issue names', () {
      final ids = AchievementCatalog.all.map((a) => a.id).toSet();
      expect(ids, containsAll(<String>[
        // Chain milestones.
        'chain_3', 'chain_5', 'chain_8',
        // Distance milestones.
        'distance_1000', 'distance_3000', 'distance_5000',
        // Banking discipline.
        'bank_clean_1', 'bank_clean_5', 'bank_clean_15',
        // Cars collected.
        'cars_2', 'cars_4', 'cars_7',
        // Daily streaks.
        'streak_3', 'streak_7', 'streak_30',
      ]));
      expect(AchievementCatalog.all.length, 15);
    });

    test('ids are unique — the achievements map keys on them', () {
      final ids = AchievementCatalog.all.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('the car tiers match the fleet as shipped', () {
      // The FULL FLEET tier is 7 because the garage ships 7 vehicles.
      // Growing the fleet must grow the tier, so assert the coupling.
      expect(VehicleCatalog.vehicles.length, 7);
    });

    test('streaks count consecutive days, gaps break them', () {
      expect(AchievementCatalog.longestDailyStreak(const []), 0);
      expect(
        AchievementCatalog.longestDailyStreak(const [
          DailyResult(dateKey: '2026-01-04', score: 1, banked: true,
              completedAtMs: 0),
        ]),
        1,
      );
      expect(
        AchievementCatalog.longestDailyStreak(const [
          DailyResult(dateKey: '2026-01-01', score: 1, banked: true,
              completedAtMs: 0),
          DailyResult(dateKey: '2026-01-02', score: 1, banked: true,
              completedAtMs: 0),
          DailyResult(dateKey: '2026-01-03', score: 1, banked: true,
              completedAtMs: 0),
        ]),
        3,
        reason: 'three days in a row, whatever order they arrive in',
      );
      expect(
        AchievementCatalog.longestDailyStreak(const [
          DailyResult(dateKey: '2026-01-01', score: 1, banked: true,
              completedAtMs: 0),
          DailyResult(dateKey: '2026-01-02', score: 1, banked: true,
              completedAtMs: 0),
          DailyResult(dateKey: '2026-01-05', score: 1, banked: true,
              completedAtMs: 0),
          DailyResult(dateKey: '2026-01-06', score: 1, banked: true,
              completedAtMs: 0),
        ]),
        2,
        reason: 'the gap splits the streak; the longest run wins',
      );
      // A month boundary is one step, not a gap: the day-number math is
      // calendar arithmetic, not string arithmetic.
      expect(
        AchievementCatalog.longestDailyStreak(const [
          DailyResult(dateKey: '2026-01-31', score: 1, banked: true,
              completedAtMs: 0),
          DailyResult(dateKey: '2026-02-01', score: 1, banked: true,
              completedAtMs: 0),
        ]),
        2,
      );
      // A malformed key counts as nothing rather than throwing.
      expect(
        AchievementCatalog.longestDailyStreak(const [
          DailyResult(dateKey: 'nonsense', score: 1, banked: true,
              completedAtMs: 0),
          DailyResult(dateKey: '2026-03-01', score: 1, banked: true,
              completedAtMs: 0),
        ]),
        1,
      );
    });

    test('progress caps at the threshold', () {
      const state = AchievementState(
        bestBankedScore: 0,
        longestChain: 9,
        furthestDistanceMetres: 0,
        mostFaresInOneShift: 0,
        cleanBankedShifts: 0,
        unlockedVehicleCount: 0,
        longestDailyStreak: 0,
      );
      expect(AchievementCatalog.chain8.progress(state), 8,
          reason: '"9/8" is noise; earned reads 8/8 or EARNED');
      expect(AchievementCatalog.chain8.isEarned(state), isTrue);
    });
  });

  group('evaluation writes the achievements map', () {
    test('a fresh save has earned nothing', () {
      expect(gameState.unlockedAchievementCount, 0);
      expect(gameState.isAchievementUnlocked('chain_3'), isFalse);
      expect(gameState.takePendingAchievementUnlocks(), isEmpty);
    });

    test('a chain milestone unlocks from an ended shift', () async {
      await gameState.recordEndlessRun(run(chain: 3));

      expect(gameState.isAchievementUnlocked('chain_3'), isTrue);
      expect(gameState.isAchievementUnlocked('chain_5'), isFalse);
      expect(gameState.unlockedAchievementCount, 2,
          reason: 'the clean bank rode along — the same shift earned '
              'bank_clean_1');
    });

    test('a distance milestone unlocks from a long shift', () async {
      await gameState.recordEndlessRun(run(distancePx: 12000)); // 1.2 km

      expect(gameState.isAchievementUnlocked('distance_1000'), isTrue);
      expect(gameState.isAchievementUnlocked('distance_3000'), isFalse);
    });

    test('banking discipline counts only clean banks', () async {
      // A bank that cost two lives is a bank, but not a clean one.
      await gameState.recordEndlessRun(
          run(banked: true, livesLost: 2));
      expect(gameState.isAchievementUnlocked('bank_clean_1'), isFalse);

      await gameState.recordEndlessRun(
          run(banked: false, livesLost: 3));
      expect(gameState.isAchievementUnlocked('bank_clean_1'), isFalse,
          reason: 'a wreck is not a bank at all');

      await gameState.recordEndlessRun(run(banked: true, livesLost: 0));
      expect(gameState.isAchievementUnlocked('bank_clean_1'), isTrue);
    });

    test('a streak unlocks from consecutive completed dailies', () async {
      DailyResult daily(String dateKey) => DailyResult(
            dateKey: dateKey,
            score: 100,
            banked: true,
            completedAtMs: 0,
          );

      await gameState.recordDailyResult(daily('2026-01-01'));
      await gameState.recordDailyResult(daily('2026-01-02'));
      expect(gameState.isAchievementUnlocked('streak_3'), isFalse);

      await gameState.recordDailyResult(daily('2026-01-03'));
      expect(gameState.isAchievementUnlocked('streak_3'), isTrue);
    });

    test('a fleet purchase unlocks the cars-collected tier', () async {
      gameState.addCoins(2000);

      // The starter cab is owned from the first launch; one purchase is
      // two cars.
      expect(gameState.unlockVehicle('compact_red', 150), isTrue);
      expect(gameState.isAchievementUnlocked('cars_2'), isTrue);
      expect(gameState.isAchievementUnlocked('cars_4'), isFalse);
    });

    test('an award persists into the save\'s achievements map', () async {
      await gameState.recordEndlessRun(run(chain: 5));

      // Simulate an app restart: a brand-new service stack reading the
      // same on-device store. The map — not an in-memory list — must
      // carry the award.
      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();

      expect(reloaded.isAchievementUnlocked('chain_5'), isTrue);
      expect(reloaded.isAchievementUnlocked('chain_8'), isFalse);
    });

    test('earning is forever — later runs never revoke', () async {
      await gameState.recordEndlessRun(run(chain: 8));
      expect(gameState.isAchievementUnlocked('chain_8'), isTrue);

      // Every later shift, however poor, leaves the award standing.
      await gameState.recordEndlessRun(run(chain: 1));
      expect(gameState.isAchievementUnlocked('chain_8'), isTrue);
      expect(gameState.unlockedAchievementCount, greaterThanOrEqualTo(3),
          reason: 'chain 8 also earned the 3 and 5 tiers on the way up');
    });

    test('one unlock queues per new award, and the queue drains', () async {
      await gameState.recordEndlessRun(run(chain: 5));

      final pending = gameState.takePendingAchievementUnlocks();
      expect(pending.map((a) => a.id), containsAll(<String>['chain_3',
          'chain_5']));

      // Drained: the shift's panel showed them, nobody re-shows them.
      expect(gameState.takePendingAchievementUnlocks(), isEmpty);

      // And a shift that earns nothing queues nothing.
      await gameState.recordEndlessRun(run(chain: 1));
      expect(gameState.takePendingAchievementUnlocks(), isEmpty);
    });

    test('resetting progress takes the achievements with it', () async {
      await gameState.recordEndlessRun(run(chain: 3));
      expect(gameState.isAchievementUnlocked('chain_3'), isTrue);

      gameState.resetProgress();

      expect(gameState.isAchievementUnlocked('chain_3'), isFalse);
      expect(gameState.unlockedAchievementCount, 0);
      expect(gameState.personalBests.longestChain, 0,
          reason: 'the records are progress too');
      expect(gameState.takePendingAchievementUnlocks(), isEmpty,
          reason: 'nothing announces after the save it earned in is gone');
    });
  });

  group('the state snapshot', () {
    test('measures read the records, history, garage, and dailies',
        () async {
      await gameState.recordEndlessRun(run(
        chain: 4,
        distancePx: 15000,
        banked: true,
        fares: 7,
      ));

      final state = gameState.achievementState;
      expect(state.longestChain, 4);
      expect(state.furthestDistanceMetres, 1500);
      expect(state.bestBankedScore, 120);
      expect(state.mostFaresInOneShift, 7);
      expect(state.cleanBankedShifts, 1);
      expect(state.unlockedVehicleCount, 1,
          reason: 'the starter cab counts');
      expect(state.longestDailyStreak, 0);
    });
  });
}
