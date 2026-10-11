import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/data/vehicle_catalog.dart';
import 'package:taxi_game/game/levels/level.dart';
import 'package:taxi_game/models/achievements.dart';
import 'package:taxi_game/models/daily_result.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/models/save_data.dart';
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
    int nearMisses = 0,
    int score = 120,
  }) {
    return RunRecord(
      endedAtMs: 0,
      distancePx: distancePx,
      score: score,
      faresDelivered: fares,
      longestChain: chain,
      livesLost: livesLost,
      lifeLossDistancesPx: List.filled(livesLost, 500.0),
      banked: banked,
      durationSeconds: 60,
      nearMisses: nearMisses,
    );
  }

  group('the catalog', () {
    test('covers the five original tracks and issue #283\'s mastery '
        'tracks', () {
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
        // Lifetime close calls (issue #283).
        'close_call_10', 'close_call_100', 'close_call_500',
        // Score tiers (issue #283).
        'score_500', 'score_2000', 'score_5000',
        // Nonconsecutive daily participation (issue #283).
        'daily_10', 'daily_50', 'daily_200',
        // Lifetime driving volume (issue #283).
        'lifetime_25km', 'lifetime_100km', 'lifetime_500km',
        // The ladder's finish (issue #283).
        'tutorial_complete',
      ]));
      expect(AchievementCatalog.all.length, 28);
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
        totalNearMisses: 0,
        completedDailyCount: 0,
        lifetimeDistanceMetres: 0,
        tutorialComplete: false,
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

    test('the clean-bank count is lifetime — it never drops as the '
        'history window trims (issue #55)', () async {
      // The issue's arithmetic: a player banking clean every 20th shift
      // has fifteen clean banks after 300 shifts, but only ten inside
      // the last 200 — so counting over the window could never reach
      // THE HOUSE ALWAYS WINS (15) at a 5% clean rate, and progress read
      // "11/15" then "10/15" as old clean banks aged out. The measure is
      // a lifetime counter now; watch it only ever climb.
      var expected = 0;
      var previous = 0;
      for (var i = 1; i <= 300; i++) {
        final clean = i % 20 == 0;
        await gameState.recordEndlessRun(run(
          banked: clean,
          livesLost: clean ? 0 : 3,
        ));
        final count = gameState.achievementState.cleanBankedShifts;
        expect(count, greaterThanOrEqualTo(previous),
            reason: 'progress went backwards at shift $i');
        if (clean) {
          expected++;
          expect(count, expected,
              reason: 'shift $i was the $expected-th clean bank');
        }
        previous = count;
      }

      expect(previous, 15);
      expect(gameState.isAchievementUnlocked('bank_clean_15'), isTrue,
          reason: 'fifteen lifetime clean banks, whenever they happened');

      // The contrast that is the bug: the trimmed window now holds only
      // the last ten of them — the measure must not be reading it.
      final windowCount = gameState.runHistory
          .where((record) => record.banked && record.livesLost == 0)
          .length;
      expect(windowCount, 10);
      expect(windowCount, lessThan(previous),
          reason: 'the window alone could not have earned the award');
    });

    test('a pre-fix save seeds the lifetime counter from its history '
        'window (issue #55)', () async {
      // An old save: a 40-record history whose window holds twelve clean
      // banks, and a personalBests block written before the counter
      // existed (no cleanBankedShifts key). Loading must carry those
      // twelve across — a fix may not start a veteran at zero.
      final history = <Map<String, dynamic>>[
        for (var i = 0; i < 40; i++)
          run(banked: i < 12, livesLost: i < 12 ? 0 : 3).toJson(),
      ];
      final save = SaveData.createDefault().toJson();
      (save['personalBests'] as Map<String, dynamic>)
          .remove('cleanBankedShifts');

      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey: jsonEncode(save),
        StorageService.runHistoryKey: jsonEncode(history),
      });
      final storage = StorageService();
      await storage.init();
      final migrated = GameStateService(storage);
      await migrated.loadSaveData();

      expect(migrated.achievementState.cleanBankedShifts, 12,
          reason: 'the window\'s clean banks seed the lifetime counter');
      expect(migrated.isAchievementUnlocked('bank_clean_5'), isTrue,
          reason: 'twelve clean banks retro-award SURE HANDS on load');

      // The seed persisted, not just patched memory: a restart reads it
      // straight from the save even though the window may since have
      // moved on.
      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();
      expect(reloaded.achievementState.cleanBankedShifts, 12);

      // And the stored counter wins ties with the window: seeding takes
      // the maximum, so a post-migration load never re-reads a smaller
      // number back in.
      expect(
        reloaded.personalBests.toJson().containsKey('cleanBankedShifts'),
        isTrue,
      );
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
      final compact = VehicleCatalog.byId('compact_red')!;
      gameState.addCoins(compact.price);

      // The starter cab is owned from the first launch; one purchase is
      // two cars.
      expect(gameState.unlockVehicle('compact_red', compact.price), isTrue);
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

      await gameState.resetProgress();

      expect(gameState.isAchievementUnlocked('chain_3'), isFalse);
      expect(gameState.unlockedAchievementCount, 0);
      expect(gameState.personalBests.longestChain, 0,
          reason: 'the records are progress too');
      expect(gameState.takePendingAchievementUnlocks(), isEmpty,
          reason: 'nothing announces after the save it earned in is gone');
    });
  });

  group('the mastery tracks (issue #283)', () {
    test('the graduation bonus is the pinned literal', () {
      // The number is a product decision, not an implementation detail:
      // the completion panel and the settings card both name it, so a
      // retune must fail here rather than ride through assertions that
      // derive their expected value from this same constant.
      expect(GameStateService.tutorialGraduationBonus, 500);
    });

    test('lifetime close calls fold across shifts and unlock their tier',
        () async {
      await gameState.recordEndlessRun(run(nearMisses: 6));
      await gameState.recordEndlessRun(run(nearMisses: 4));

      expect(gameState.achievementState.totalNearMisses, 10,
          reason: 'the counter folds every shift, not just the latest');
      expect(gameState.isAchievementUnlocked('close_call_10'), isTrue);
      expect(gameState.isAchievementUnlocked('close_call_100'), isFalse);
      expect(
        gameState
            .takePendingAchievementUnlocks()
            .map((a) => a.id),
        contains('close_call_10'),
        reason: 'the shift that reached the tier queues its banner',
      );
    });

    test('the close-call tier waits for the tenth call', () async {
      await gameState.recordEndlessRun(run(nearMisses: 9));
      expect(gameState.achievementState.totalNearMisses, 9);
      expect(gameState.isAchievementUnlocked('close_call_10'), isFalse,
          reason: 'nine close calls are one below the bar');

      await gameState.recordEndlessRun(run(nearMisses: 1));
      expect(gameState.isAchievementUnlocked('close_call_10'), isTrue,
          reason: 'the tenth call lands it');
    });

    test('score tiers read the best banked score', () async {
      await gameState.recordEndlessRun(run(score: 600));
      expect(gameState.isAchievementUnlocked('score_500'), isTrue);
      expect(gameState.isAchievementUnlocked('score_2000'), isFalse);

      // A wreck's forfeited score is not a bank (personal_bests.dart):
      // the tier measures money that reached the wallet.
      await gameState.recordEndlessRun(
          run(score: 9000, banked: false, livesLost: 3));
      expect(gameState.achievementState.bestBankedScore, 600);
      expect(gameState.isAchievementUnlocked('score_5000'), isFalse,
          reason: 'a wrecked 9000 never banked, so no tier');
    });

    test('the score tier waits for the banked 500', () async {
      await gameState.recordEndlessRun(run(score: 499));
      expect(gameState.achievementState.bestBankedScore, 499);
      expect(gameState.isAchievementUnlocked('score_500'), isFalse,
          reason: 'a banked 499 is one below the bar');

      await gameState.recordEndlessRun(run(score: 500));
      expect(gameState.isAchievementUnlocked('score_500'), isTrue,
          reason: 'the banked 500 lands it');
    });

    test('daily participation counts completed dailies, gaps included',
        () async {
      DailyResult daily(String dateKey) => DailyResult(
            dateKey: dateKey,
            score: 100,
            banked: true,
            completedAtMs: 0,
          );

      // Days every other one: nothing consecutive, so the streak tiers
      // stay locked while the participation tier fills.
      for (var i = 1; i <= 9; i++) {
        final day = (2 * i).toString().padLeft(2, '0');
        await gameState.recordDailyResult(daily('2026-01-$day'));
      }
      expect(gameState.achievementState.completedDailyCount, 9);
      expect(gameState.isAchievementUnlocked('daily_10'), isFalse,
          reason: 'nine days are one below the bar');

      await gameState.recordDailyResult(daily('2026-01-20'));

      expect(gameState.achievementState.completedDailyCount, 10);
      expect(gameState.isAchievementUnlocked('daily_10'), isTrue);
      expect(gameState.isAchievementUnlocked('daily_50'), isFalse);
      expect(gameState.isAchievementUnlocked('streak_3'), isFalse,
          reason: 'gaps break the streak, never the participation count');
    });

    test('lifetime volume tiers read the stored totals', () async {
      // 25 km across 25 shifts — each 1 km, under the single-shift
      // tiers' reach — so the tier can only be reading the lifetime sum.
      for (var i = 0; i < 25; i++) {
        await gameState.recordEndlessRun(run(distancePx: 10000));
      }

      expect(gameState.achievementState.lifetimeDistanceMetres, 25000);
      expect(gameState.isAchievementUnlocked('lifetime_25km'), isTrue);
      expect(gameState.isAchievementUnlocked('lifetime_100km'), isFalse);
    });

    test('the volume tier waits for the 25th kilometre', () async {
      // 24999 m — one metre short of the bar — then the metre that lands
      // it. 10 px per metre (RunSummary.pixelsPerMetre).
      await gameState.recordEndlessRun(run(distancePx: 249990));
      expect(gameState.achievementState.lifetimeDistanceMetres, 24999);
      expect(gameState.isAchievementUnlocked('lifetime_25km'), isFalse,
          reason: 'one metre below the bar');

      await gameState.recordEndlessRun(run(distancePx: 10));
      expect(gameState.achievementState.lifetimeDistanceMetres, 25000);
      expect(gameState.isAchievementUnlocked('lifetime_25km'), isTrue,
          reason: 'the 25th kilometre lands it');
    });

    test('finishing the ladder earns its record and pays its bonus once',
        () async {
      for (var rung = 1; rung < GameLevel.ladderLength; rung++) {
        expect(gameState.completeLevel(rung, 0), 0,
            reason: 'only the final rung pays the graduation bonus');
      }
      final bonus = gameState.completeLevel(GameLevel.ladderLength, 0);

      expect(bonus, GameStateService.tutorialGraduationBonus);
      expect(gameState.totalCoins, 500,
          reason: 'a literal pin: every rung paid 0, so the wallet holds '
              'the 500 graduation bonus alone');
      expect(gameState.tutorialComplete, isTrue);
      expect(gameState.isAchievementUnlocked('tutorial_complete'), isTrue);
      expect(
        gameState.takePendingAchievementUnlocks().map((a) => a.id),
        contains('tutorial_complete'),
        reason: 'the completion panel that finished the rung must be able '
            'to banner the record',
      );

      // The save now sits past the rung, so a replay can never double-pay
      // (the branch only runs while the rung is still the current one).
      expect(gameState.completeLevel(GameLevel.ladderLength, 0), 0);
      expect(gameState.totalCoins, 500,
          reason: 'the bonus stays a one-time 500');
    });

    test('a pre-#283 save seeds its close-call counter and retro-awards '
        'from the window', () async {
      // The migration case: the totals block exists (issue #183) but was
      // written before the close-call counter did, and the history —
      // which has carried nearMisses since issue #23 — is the only
      // record of the close calls.
      final history = <Map<String, dynamic>>[
        for (var i = 0; i < 12; i++) run(nearMisses: 1).toJson(),
      ];
      final save = SaveData.createDefault().toJson();
      (save['lifetimeRunTotals'] as Map<String, dynamic>)
          .remove('totalNearMisses');

      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey: jsonEncode(save),
        StorageService.runHistoryKey: jsonEncode(history),
      });
      final storage = StorageService();
      await storage.init();
      final migrated = GameStateService(storage);
      await migrated.loadSaveData();

      expect(migrated.achievementState.totalNearMisses, 12,
          reason: 'the window\'s close calls seed the lifetime counter');
      expect(migrated.isAchievementUnlocked('close_call_10'), isTrue,
          reason: 'twelve close calls retro-award the first tier on load');
      expect(migrated.takePendingAchievementUnlocks(), isEmpty,
          reason: 'a retro-award from a load never banners');

      // The seed reached the disk: a restart reads the stored number
      // straight from the save.
      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();
      expect(reloaded.achievementState.totalNearMisses, 12);
    });

    test('a save already past rung ten retro-earns the ladder record '
        'silently', () async {
      // The migration case for the ladder's own record: the save was
      // finished by a build that had no LICENSED DRIVER to award.
      final save = SaveData.createDefault()
        ..currentLevel = GameLevel.ladderLength + 1;
      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey: jsonEncode(save.toJson()),
      });
      final storage = StorageService();
      await storage.init();
      final migrated = GameStateService(storage);
      await migrated.loadSaveData();

      expect(migrated.tutorialComplete, isTrue);
      expect(migrated.isAchievementUnlocked('tutorial_complete'), isTrue,
          reason: 'the ladder was finished before the record existed');
      expect(migrated.takePendingAchievementUnlocks(), isEmpty,
          reason: 'a retro-award from a load never banners');
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
      expect(state.totalNearMisses, 0);
      expect(state.completedDailyCount, 0);
      expect(state.lifetimeDistanceMetres, 1500,
          reason: 'the lifetime sum, the same single shift');
      expect(state.tutorialComplete, isFalse);
    });
  });
}
