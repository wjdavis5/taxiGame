import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The on-device shift history (issue #17): recorded shifts persist
/// across an app restart, the window stays bounded, a reset wipes it, and
/// corrupt storage reads as a fresh history rather than a crash.
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

  RunRecord run({int score = 100, bool banked = true}) => RunRecord(
        endedAtMs: score * 1000,
        distancePx: 5000,
        score: score,
        faresDelivered: 2,
        longestChain: 3,
        livesLost: banked ? 0 : 3,
        lifeLossDistancesPx: banked ? [] : [1000, 2000, 3000],
        banked: banked,
        durationSeconds: 90,
      );

  /// Simulates an app restart: a brand-new service stack reading the same
  /// on-device store.
  Future<GameStateService> restarted() async {
    final reloadedStorage = StorageService();
    await reloadedStorage.init();
    final reloaded = GameStateService(reloadedStorage);
    await reloaded.loadSaveData();
    return reloaded;
  }

  group('recording shifts', () {
    test('a recorded shift is in the history and survives a restart',
        () async {
      await gameState.recordEndlessRun(run(score: 120));
      await gameState.recordEndlessRun(run(score: 80, banked: false));

      expect(gameState.runHistory.length, 2);
      expect(gameState.runHistory.first.score, 120,
          reason: 'oldest first');
      expect(gameState.runHistory.last.banked, isFalse);

      final reloaded = await restarted();
      expect(reloaded.runHistory.length, 2);
      expect(reloaded.runHistory.first.score, 120);
      expect(reloaded.runHistory.last.score, 80);
    });

    test('recording a shift updates the aggregates for the screen',
        () async {
      expect(gameState.runStats.isEmpty, isTrue);

      await gameState.recordEndlessRun(run(score: 40));
      await gameState.recordEndlessRun(run(score: 90));

      expect(gameState.runStats.runCount, 2);
      expect(gameState.runStats.medianScore, 65.0);
      expect(gameState.runStats.bankedCount, 2);
    });

    test('the history window stays bounded, oldest records falling off',
        () async {
      for (var i = 1; i <= GameStateService.maxRecordedRuns + 10; i++) {
        await gameState.recordEndlessRun(run(score: i));
      }

      expect(gameState.runHistory.length, GameStateService.maxRecordedRuns);
      expect(gameState.runHistory.first.score, 11,
          reason: 'the ten oldest fell off the front');
      expect(gameState.runHistory.last.score,
          GameStateService.maxRecordedRuns + 10);

      final reloaded = await restarted();
      expect(reloaded.runHistory.length, GameStateService.maxRecordedRuns);
      expect(reloaded.runHistory.first.score, 11);
    });

    test('recording shifts never disturbs the save or the wallet',
        () async {
      gameState.addCoins(50);
      await gameState.recordEndlessRun(run(score: 200));

      final reloaded = await restarted();
      expect(reloaded.totalCoins, 50);
      expect(reloaded.endlessBestScore, 0,
          reason: 'the best is the save\'s business, recorded at shift end '
              'by recordEndlessScore — not by the history');
    });
  });

  group('resetting progress', () {
    test('wipes the history along with the save', () async {
      await gameState.recordEndlessRun(run(score: 120));
      gameState.addCoins(30);

      gameState.resetProgress();

      expect(gameState.runHistory, isEmpty);
      expect(gameState.runStats.isEmpty, isTrue);

      final reloaded = await restarted();
      expect(reloaded.runHistory, isEmpty);
      expect(reloaded.totalCoins, 0);
    });

    test('wipes the lifetime totals with everything else (issue #183)',
        () async {
      for (var i = 1; i <= GameStateService.maxRecordedRuns + 1; i++) {
        await gameState.recordEndlessRun(run(score: i));
      }
      expect(gameState.runStats.shiftsEnded,
          GameStateService.maxRecordedRuns + 1);

      gameState.resetProgress();

      expect(gameState.runStats.shiftsEnded, 0);
      expect(gameState.runStats.totalScore, 0);

      final reloaded = await restarted();
      expect(reloaded.runStats.shiftsEnded, 0,
          reason: 'a fresh save carries a fresh totals block');
    });
  });

  group('the lifetime totals (issue #183)', () {
    test('the shift after the trim still counts — nothing freezes or falls',
        () async {
      // The issue's own case, maxRecordedRuns + 1 shifts: shift 1 has
      // fallen off the window, and the rows the issue names — "Shifts
      // ended", "Fares delivered", "Time driven" — must still count it.
      for (var i = 1; i <= GameStateService.maxRecordedRuns + 1; i++) {
        await gameState.recordEndlessRun(run(score: i));
      }

      expect(gameState.runHistory.length, GameStateService.maxRecordedRuns);
      expect(gameState.runHistory.first.score, 2,
          reason: 'shift 1 fell off the front of the window');

      final stats = gameState.runStats;
      expect(stats.runCount, GameStateService.maxRecordedRuns,
          reason: 'the window stays the shares\' denominator');
      expect(stats.shiftsEnded, GameStateService.maxRecordedRuns + 1);
      // run() carries score i, 2 fares, 90 s and 5000 px per shift.
      expect(stats.totalScore, 20301, reason: 'the sum of 1..201');
      expect(stats.totalFares, 2 * (GameStateService.maxRecordedRuns + 1));
      expect(stats.totalDurationSeconds,
          90.0 * (GameStateService.maxRecordedRuns + 1));
      expect(stats.totalDistanceMetres,
          500 * (GameStateService.maxRecordedRuns + 1));
    });

    test('survive a restart — they live in the save, not the window',
        () async {
      for (var i = 1; i <= GameStateService.maxRecordedRuns + 1; i++) {
        await gameState.recordEndlessRun(run(score: i));
      }

      final reloaded = await restarted();
      expect(reloaded.runHistory.length, GameStateService.maxRecordedRuns);
      expect(reloaded.runStats.shiftsEnded,
          GameStateService.maxRecordedRuns + 1);
      expect(reloaded.runStats.totalScore, 20301);
      expect(reloaded.runStats.totalDurationSeconds,
          90.0 * (GameStateService.maxRecordedRuns + 1));
    });

    test('a pre-fix save seeds its totals from the window once', () async {
      // The migration case: a history written by an older build, and a
      // save with no lifetimeRunTotals block — the shape every save in
      // the wild has the first time this build loads it. The seed is the
      // window's own sums, persisted immediately.
      SharedPreferences.setMockInitialValues({
        StorageService.runHistoryKey: jsonEncode(
          [for (var i = 1; i <= 3; i++) run(score: i).toJson()],
        ),
        StorageService.saveDataKey: jsonEncode({
          'currentLevel': 1,
          'totalCoins': 0,
          'totalGems': 0,
          'unlockedVehicles': ['taxi_yellow'],
          'selectedVehicle': 'taxi_yellow',
          'achievements': {},
          'endlessBestScore': 0,
          'controlHintDismissed': true,
          'bankPromptSeen': true,
          'personalBests': {},
          'settings': {
            'soundEnabled': true,
            'musicEnabled': true,
            'vibrationEnabled': true,
            'musicVolume': 0.7,
            'sfxVolume': 0.8,
          },
          // no lifetimeRunTotals — the pre-#183 save shape
        }),
      });
      final storage = StorageService();
      await storage.init();
      final loaded = GameStateService(storage);
      await loaded.loadSaveData();

      expect(loaded.runHistory.length, 3);
      expect(loaded.runStats.shiftsEnded, 3,
          reason: 'seeded from the window: three shifts in it');
      expect(loaded.runStats.totalScore, 6, reason: '1 + 2 + 3');
      expect(loaded.runStats.totalFares, 6);
      expect(loaded.runStats.totalDurationSeconds, 270.0);

      // And the seed reached the disk: a restart finds the stored block,
      // and the window still agrees with it, so the seed no-ops.
      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();
      expect(reloaded.runStats.shiftsEnded, 3);
      expect(reloaded.runStats.totalScore, 6);
    });
  });

  group('corrupt storage', () {
    test('reads as a fresh history instead of crashing', () async {
      SharedPreferences.setMockInitialValues({
        StorageService.runHistoryKey: '{not json at all',
        StorageService.saveDataKey: '{also broken',
      });

      final storage = StorageService();
      await storage.init();
      final gameState = GameStateService(storage);
      await gameState.loadSaveData();

      expect(gameState.runHistory, isEmpty,
          reason: 'a corrupt history starts over, like a corrupt save');
      expect(gameState.currentLevel, 1);
    });

    test('a record missing keys loads with defaults, keeping its neighbours',
        () async {
      // fromJson defaults missing keys rather than throwing, so a record
      // written by an older build costs nothing but its unknowns.
      SharedPreferences.setMockInitialValues({
        StorageService.runHistoryKey: '[{"score": 120}, {}]',
      });

      final storage = StorageService();
      await storage.init();
      final gameState = GameStateService(storage);
      await gameState.loadSaveData();

      expect(gameState.runHistory.length, 2);
      expect(gameState.runHistory.first.score, 120);
      expect(gameState.runHistory.last.score, 0);
    });
  });
}
