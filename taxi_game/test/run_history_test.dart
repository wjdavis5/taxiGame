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
