import 'dart:convert';

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
      expect(bests.cleanBankedShifts, 0);
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
        livesLost: 3,
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
        livesLost: 0,
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
        livesLost: 0,
      );
      // The second shift banks but costs a life, so it neither beats a
      // maximum nor adds a clean bank: nothing at all improves.
      expect(
        bests.applyRun(
          score: 100,
          banked: true,
          longestChain: 2,
          distancePx: 3000,
          faresDelivered: 2,
          livesLost: 1,
        ),
        isFalse,
        reason: 'a worse shift sets no record and no clean bank',
      );
      expect(bests.bestBankedScore, 340);
      expect(bests.longestChain, 6);
      expect(bests.furthestDistancePx, 20000);
      expect(bests.mostFaresInOneShift, 10);
      expect(bests.cleanBankedShifts, 1);
    });

    test('a tie keeps the old record, like the score best does', () {
      final bests = PersonalBests();
      bests.applyRun(
        score: 200,
        banked: true,
        longestChain: 3,
        distancePx: 5000,
        faresDelivered: 3,
        livesLost: 2,
      );
      expect(
        bests.applyRun(
          score: 200,
          banked: true,
          longestChain: 3,
          distancePx: 5000,
          faresDelivered: 3,
          livesLost: 2,
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
        cleanBankedShifts: 17,
      );
      final restored = PersonalBests.fromJson(bests.toJson());
      expect(restored.bestBankedScore, 340);
      expect(restored.longestChain, 6);
      expect(restored.furthestDistancePx, 20000);
      expect(restored.mostFaresInOneShift, 10);
      expect(restored.cleanBankedShifts, 17);
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

  group('the clean-bank counter (issue #55)', () {
    test('a clean bank counts, and the count only ever climbs', () {
      final bests = PersonalBests();
      expect(
        bests.applyRun(
          score: 100,
          banked: true,
          longestChain: 1,
          distancePx: 1000,
          faresDelivered: 1,
          livesLost: 0,
        ),
        isTrue,
        reason: 'a clean bank is an improvement worth persisting even '
            'when it sets no maximum',
      );
      expect(bests.cleanBankedShifts, 1);
      bests.applyRun(
        score: 100,
        banked: true,
        longestChain: 1,
        distancePx: 1000,
        faresDelivered: 1,
        livesLost: 0,
      );
      expect(bests.cleanBankedShifts, 2,
          reason: 'no tie rule here — every clean bank counts once');
    });

    test('a bank that cost a life is not a clean bank', () {
      final bests = PersonalBests();
      bests.applyRun(
        score: 500,
        banked: true,
        longestChain: 4,
        distancePx: 8000,
        faresDelivered: 6,
        livesLost: 2,
      );
      expect(bests.cleanBankedShifts, 0);
    });

    test('a wreck is not a bank at all', () {
      final bests = PersonalBests();
      bests.applyRun(
        score: 500,
        banked: false,
        longestChain: 4,
        distancePx: 8000,
        faresDelivered: 6,
        livesLost: 0,
      );
      expect(bests.cleanBankedShifts, 0);
    });

    test('a pre-#55 save loads its missing counter as zero', () {
      final restored = PersonalBests.fromJson({
        'bestBankedScore': 340,
        'longestChain': 6,
        'furthestDistancePx': 20000,
        'mostFaresInOneShift': 10,
        // No cleanBankedShifts key: the field postdates this save.
      });
      expect(restored.cleanBankedShifts, 0);
    });
  });

  group('seeding the maxima from the window (issue #247)', () {
    RunRecord windowRun({
      int score = 120,
      bool banked = true,
      int chain = 2,
      double distancePx = 4000,
      int fares = 3,
      int livesLost = 0,
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
      );
    }

    test('each maximum takes the window\'s larger value, and only a bank '
        'sets the banked score', () {
      final bests = PersonalBests(bestBankedScore: 150);
      final seeded = bests.seedFromWindow([
        // A wreck with the biggest score never sets the banked record,
        // exactly as applyRun judges it — but its distance still counts.
        windowRun(
          score: 500,
          banked: false,
          chain: 2,
          distancePx: 9000,
          fares: 2,
          livesLost: 3,
        ),
        windowRun(
          score: 240,
          banked: true,
          chain: 7,
          distancePx: 8000,
          fares: 9,
        ),
      ]);

      expect(seeded, isTrue);
      expect(bests.bestBankedScore, 240);
      expect(bests.longestChain, 7);
      expect(bests.furthestDistancePx, 9000);
      expect(bests.mostFaresInOneShift, 9);
    });

    test('a save ahead of its window is left alone and reports no change',
        () {
      final bests = PersonalBests(
        bestBankedScore: 340,
        longestChain: 6,
        furthestDistancePx: 20000,
        mostFaresInOneShift: 10,
      );

      final seeded = bests.seedFromWindow([
        windowRun(score: 100, chain: 3, distancePx: 5000, fares: 4),
      ]);

      expect(seeded, isFalse,
          reason: 'post-migration saves always hold the larger numbers');
      expect(bests.bestBankedScore, 340);
      expect(bests.longestChain, 6);
      expect(bests.furthestDistancePx, 20000);
      expect(bests.mostFaresInOneShift, 10);
    });

    test('a load seeds the maxima its save missed and persists them',
        () async {
      // The issue's own case: the save's PB says 150 while the window
      // still holds a banked 240 — the records screen showed 150 against
      // a menu BEST of 240 until the seed. The seed must reach the disk
      // immediately, before the window can trim the record away.
      final save = SaveData.createDefault();
      save.personalBests
        ..bestBankedScore = 150
        ..longestChain = 3
        ..furthestDistancePx = 10000
        ..mostFaresInOneShift = 4;
      SharedPreferences.setMockInitialValues({
        StorageService.runHistoryKey: jsonEncode([
          windowRun(
            score: 240,
            chain: 7,
            distancePx: 22000,
            fares: 9,
          ).toJson(),
        ]),
        StorageService.saveDataKey: jsonEncode(save.toJson()),
      });
      final storage = StorageService();
      await storage.init();
      final loaded = GameStateService(storage);
      await loaded.loadSaveData();

      expect(loaded.personalBests.bestBankedScore, 240);
      expect(loaded.personalBests.longestChain, 7);
      expect(loaded.personalBests.furthestDistancePx, 22000);
      expect(loaded.personalBests.mostFaresInOneShift, 9);

      // A restart finds the seeded block in the save, not the window: the
      // seed is durable, and the second load no-ops.
      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();
      expect(reloaded.personalBests.bestBankedScore, 240);
      expect(reloaded.personalBests.longestChain, 7);
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
      int livesLost = 0,
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
      expect(bests.cleanBankedShifts, 1);
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
      expect(reloaded.personalBests.cleanBankedShifts, 1,
          reason: 'the lifetime clean-bank count rides the save, not the '
              'trimmed history (issue #55)');
    });
  });
}
