import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/models/personal_bests.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The personal bests (issue #21): best banked score, longest chain,
/// furthest distance, most fares in one shift. Stored maxima — they
/// never regress — fed by every ended shift, persisted with the save,
/// and readable by old saves as nothing recorded.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PersonalBests.applyRun', () {
    test('a fresh record sheet is all zeros', () {
      final bests = PersonalBests();
      expect(bests.bestBankedScore, 0);
      expect(bests.longestChain, 0);
      expect(bests.furthestDistancePx, 0.0);
      expect(bests.mostFaresInOneShift, 0);
    });

    test('only a bank can set the banked-score record', () {
      final bests = PersonalBests();

      // A wrecked shift with a big forfeited score earns nothing: the
      // score died unbanked, so it never reached the wallet.
      final wreckImproved = bests.applyRun(
        score: 500,
        banked: false,
        longestChain: 4,
        distancePx: 8000,
        faresDelivered: 6,
      );
      expect(bests.bestBankedScore, 0);
      expect(wreckImproved, isTrue,
          reason: 'the shift still set the chain/distance/fares records');

      // A smaller banked shift sets the banked record, because a bank
      // actually paid out.
      bests.applyRun(
        score: 120,
        banked: true,
        longestChain: 1,
        distancePx: 1000,
        faresDelivered: 1,
      );
      expect(bests.bestBankedScore, 120);
    });

    test('every field is a running maximum — records never regress', () {
      final bests = PersonalBests();
      bests.applyRun(
        score: 340,
        banked: true,
        longestChain: 6,
        distancePx: 20000,
        faresDelivered: 10,
      );
      expect(
        bests.applyRun(
          score: 100,
          banked: true,
          longestChain: 2,
          distancePx: 3000,
          faresDelivered: 2,
        ),
        isFalse,
        reason: 'a worse shift sets no record',
      );
      expect(bests.bestBankedScore, 340);
      expect(bests.longestChain, 6);
      expect(bests.furthestDistancePx, 20000);
      expect(bests.mostFaresInOneShift, 10);
    });

    test('a tie keeps the old record, like the score best does', () {
      final bests = PersonalBests();
      bests.applyRun(
        score: 200,
        banked: true,
        longestChain: 3,
        distancePx: 5000,
        faresDelivered: 3,
      );
      expect(
        bests.applyRun(
          score: 200,
          banked: true,
          longestChain: 3,
          distancePx: 5000,
          faresDelivered: 3,
        ),
        isFalse,
      );
    });

    test('JSON round-trips every field', () {
      final bests = PersonalBests(
        bestBankedScore: 340,
        longestChain: 6,
        furthestDistancePx: 20000,
        mostFaresInOneShift: 10,
      );
      final restored = PersonalBests.fromJson(bests.toJson());
      expect(restored.bestBankedScore, 340);
      expect(restored.longestChain, 6);
      expect(restored.furthestDistancePx, 20000);
      expect(restored.mostFaresInOneShift, 10);
    });

    test('a save written before the records existed loads as none', () {
      // A pre-issue-#21 save: no personalBests key at all.
      final save = SaveData.fromJson({
        'currentLevel': 3,
        'totalCoins': 40,
        'totalGems': 0,
        'unlockedVehicles': ['taxi_yellow'],
        'selectedVehicle': 'taxi_yellow',
        'achievements': <String, bool>{},
        'settings': Settings.createDefault().toJson(),
      });

      expect(save.personalBests.bestBankedScore, 0,
          reason: 'a missing key means "nothing recorded", not a corrupt '
              'save');
      expect(save.toJson().containsKey('personalBests'), isTrue,
          reason: 'and it round-trips into new saves');
    });
  });

  group('records through the service (issue #21)', () {
    late GameStateService gameState;

    RunRecord run({
      int score = 120,
      bool banked = true,
      int chain = 2,
      double distancePx = 4000,
      int fares = 3,
    }) {
      return RunRecord(
        endedAtMs: 0,
        distancePx: distancePx,
        score: score,
        faresDelivered: fares,
        longestChain: chain,
        livesLost: 0,
        lifeLossDistancesPx: const [],
        banked: banked,
        durationSeconds: 60,
      );
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      gameState = GameStateService(storage);
      await gameState.loadSaveData();
    });

    test('an ended shift folds into the records', () async {
      await gameState.recordEndlessRun(run(
        score: 340,
        banked: true,
        chain: 5,
        distancePx: 20000,
        fares: 10,
      ));

      final bests = gameState.personalBests;
      expect(bests.bestBankedScore, 340);
      expect(bests.longestChain, 5);
      expect(bests.furthestDistancePx, 20000);
      expect(bests.mostFaresInOneShift, 10);
    });

    test('a wrecked shift never sets the banked record', () async {
      await gameState.recordEndlessRun(run(score: 90, banked: false));

      expect(gameState.personalBests.bestBankedScore, 0);
    });

    test('the records survive an app restart', () async {
      await gameState.recordEndlessRun(run(
        score: 340,
        banked: true,
        chain: 5,
        distancePx: 20000,
        fares: 10,
      ));

      // Simulate an app restart: a brand-new service stack reading the
      // same on-device store.
      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();

      expect(reloaded.personalBests.bestBankedScore, 340);
      expect(reloaded.personalBests.longestChain, 5);
      expect(reloaded.personalBests.furthestDistancePx, 20000);
      expect(reloaded.personalBests.mostFaresInOneShift, 10);
    });
  });
}
