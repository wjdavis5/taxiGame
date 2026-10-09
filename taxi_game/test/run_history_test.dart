import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/models/daily_result.dart';
import 'package:taxi_game/models/ghost_trace.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/diagnostics.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';

import 'helpers/fake_prefs_store.dart';

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

      await gameState.resetProgress();

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

      await gameState.resetProgress();

      expect(gameState.runStats.shiftsEnded, 0);
      expect(gameState.runStats.totalScore, 0);

      final reloaded = await restarted();
      expect(reloaded.runStats.shiftsEnded, 0,
          reason: 'a fresh save carries a fresh totals block');
    });

    test('the awaited reset clears the store before the fresh save lands '
        '(issue #232)', () async {
      // The old reset fired three unawaited clears and the save at once:
      // a kill (or one lost remove) could leave the fresh save beside the
      // old history — the stats screen showing shifts a save that no
      // longer exists never counted. The awaited contract is observable
      // on the store: the clears land, then the one save.
      final store = installFailingPrefsStore();
      final fakeStorage = StorageService();
      await fakeStorage.init();
      final service = GameStateService(fakeStorage);
      await service.loadSaveData();
      await service.recordEndlessRun(run(score: 120));
      // The first load of an absent save clears the record keys too
      // (issue #218), so the reset is measured by the growth of the log.
      final clearsBeforeReset = store.removedKeys.length;

      await service.resetProgress();

      expect(store.removedKeys.length, greaterThan(clearsBeforeReset),
          reason: 'the wipe reached the store, not just the cache');
      expect(store.removedKeys.last,
          'flutter.${StorageService.dailyGhostKey}',
          reason: 'the three clears run in order, ending with the ghost');
      expect(store.writtenKeys.last,
          'flutter.${StorageService.saveDataKey}',
          reason: 'the fresh save is written after the clears');
      final storedSave = await fakeStorage.loadSaveData();
      expect(storedSave!.totalCoins, 0);
      expect(storedSave.currentLevel, 1);
    });

    test('a clear that cannot land abandons the reset (issue #232)', () async {
      // Throwing the clears alone is not enough: the terminal failure was
      // swallowed, so the reset still wrote the fresh save beside the
      // records it could not remove — a default save next to the old
      // history, the exact split state #218 removed for a corrupt save.
      // A clear that reports failure must stop the reset before memory
      // changes and before the fresh save lands.
      final store = installFailingPrefsStore();
      final fakeStorage = StorageService();
      await fakeStorage.init();
      final service = GameStateService(fakeStorage);
      await service.loadSaveData();
      service.addCoins(30);
      await service.save();
      final saveWritesBefore = store.writtenKeys
          .where((k) => k == 'flutter.${StorageService.saveDataKey}')
          .length;
      Diagnostics.instance.resetForTest();
      addTearDown(Diagnostics.instance.resetForTest);

      // Every remove attempt is refused — both attempts of the first
      // clear, and of any clear that follows.
      store.throwOnRemoves = 6;

      await service.resetProgress();

      expect(Diagnostics.instance.export(), contains('[error:reset]'),
          reason: 'an abandoned reset is recorded, not silent');
      // The old save survives on disk...
      final stored = await fakeStorage.loadSaveData();
      expect(stored!.totalCoins, 30);
      // ... no fresh save was written over it...
      expect(
        store.writtenKeys
            .where((k) => k == 'flutter.${StorageService.saveDataKey}')
            .length,
        saveWritesBefore,
        reason: 'the fresh save must not land when a clear failed',
      );
      // ... and memory still holds the old save, coherent with disk.
      expect(service.totalCoins, 30);
    });

    test('a later clear failure restores the removed run history '
        '(issue #232)', () async {
      // The first clear landed and the daily-history clear failed both
      // attempts. The first-round fix returned false but left the run
      // history deleted under the old save that still lists its runs — a
      // reset that never happened, minus the history. The transaction
      // puts back what an earlier step removed before it abandons.
      final store = installFailingPrefsStore();
      final fakeStorage = StorageService();
      await fakeStorage.init();
      final service = GameStateService(fakeStorage);
      await service.loadSaveData();
      service.addCoins(30);
      await service.save();
      await service.recordEndlessRun(run(score: 120));
      await service.recordDailyResult(DailyResult(
        dateKey: DailyShift.todayKey,
        score: 340,
        banked: true,
        completedAtMs: 1780000000000,
      ));
      await service.recordDailyGhostRun(
        dateKey: DailyShift.todayKey,
        score: 340,
        banked: true,
        vehicleId: 'taxi_yellow',
        samples: const [100, 0, 105, -20],
      );
      Diagnostics.instance.resetForTest();
      addTearDown(Diagnostics.instance.resetForTest);
      final before = await store.getAll();
      final runHistoryJson = before['flutter.${StorageService.runHistoryKey}'];
      final dailyHistoryJson =
          before['flutter.${StorageService.dailyHistoryKey}'];
      final ghostJson = before['flutter.${StorageService.dailyGhostKey}'];
      final saveJson = before['flutter.${StorageService.saveDataKey}'];
      store.writtenKeys.clear();

      // Park the transaction on its first clear so the failure can be
      // armed once that clear has passed its checks: it lands, and both
      // attempts of the daily-history clear then fail.
      final hold = store.holdNextRemove = Completer<void>();
      final resetting = service.resetProgress();
      await store.removeHeld.future;
      store.throwOnRemoves = 2;
      hold.complete();
      await resetting;

      expect(Diagnostics.instance.export(), contains('[error:reset]'),
          reason: 'an abandoned reset is recorded, not silent');
      final after = await store.getAll();
      expect(after['flutter.${StorageService.runHistoryKey}'], runHistoryJson,
          reason: 'the rollback rewrote the run history the first clear '
              'removed');
      expect(after['flutter.${StorageService.dailyHistoryKey}'],
          dailyHistoryJson,
          reason: 'the failed remove left the daily history in the store');
      expect(after['flutter.${StorageService.dailyGhostKey}'], ghostJson,
          reason: 'the transaction never reached the ghost');
      expect(after['flutter.${StorageService.saveDataKey}'], saveJson,
          reason: 'no fresh save may land on an abandoned reset');
      expect(
        store.writtenKeys
            .where((k) => k == 'flutter.${StorageService.saveDataKey}'),
        isEmpty,
        reason: 'the fresh save never reached the platform',
      );
      // Memory is untouched, coherent with the old save still on disk.
      expect(service.totalCoins, 30);
      expect(service.runHistory, hasLength(1));
      expect(service.dailyHistory, hasLength(1));
      expect(service.todayGhost, isNotNull);
      // The readback through the service (issue #232): the legacy prefs
      // cache mutates ahead of the platform call, so the failed
      // daily-history remove evicted it from the cache while the store
      // kept it. The rollback must have put the cache back with it.
      expect((await fakeStorage.loadSaveData())!.totalCoins, 30,
          reason: 'the save reads back old through the cache too');
      expect(fakeStorage.loadRunHistory(), hasLength(1));
      expect(fakeStorage.loadDailyHistory(), hasLength(1),
          reason: 'the failed clear evicted the cache; the rollback '
              'restored it with the store');
      expect(fakeStorage.loadDailyGhost(), isNotNull);
    });

    test('a failed fresh save rolls all three records back (issue #232)',
        () async {
      // Every clear landed and the fresh save's two attempts both failed.
      // The first-round fix never looked at that answer: the reset
      // returned with fresh memory and deleted records beside the old
      // durable save. The transaction restores the three records and
      // abandons with memory untouched.
      final store = installFailingPrefsStore();
      final fakeStorage = StorageService();
      await fakeStorage.init();
      final service = GameStateService(fakeStorage);
      await service.loadSaveData();
      service.addCoins(30);
      await service.save();
      await service.recordEndlessRun(run(score: 120));
      await service.recordDailyResult(DailyResult(
        dateKey: DailyShift.todayKey,
        score: 340,
        banked: true,
        completedAtMs: 1780000000000,
      ));
      await service.recordDailyGhostRun(
        dateKey: DailyShift.todayKey,
        score: 340,
        banked: true,
        vehicleId: 'taxi_yellow',
        samples: const [100, 0, 105, -20],
      );
      Diagnostics.instance.resetForTest();
      addTearDown(Diagnostics.instance.resetForTest);
      final before = await store.getAll();
      final runHistoryJson = before['flutter.${StorageService.runHistoryKey}'];
      final dailyHistoryJson =
          before['flutter.${StorageService.dailyHistoryKey}'];
      final ghostJson = before['flutter.${StorageService.dailyGhostKey}'];
      final saveJson = before['flutter.${StorageService.saveDataKey}'];

      // The fresh save's attempt and its one retry, both refused; the
      // clears before it all landed.
      store.throwOnWrites = 2;
      await service.resetProgress();

      expect(Diagnostics.instance.export(), contains('[error:reset]'),
          reason: 'the abandoned reset is recorded, not silent');
      final after = await store.getAll();
      expect(after['flutter.${StorageService.runHistoryKey}'], runHistoryJson,
          reason: 'the rollback rewrote the removed run history');
      expect(after['flutter.${StorageService.dailyHistoryKey}'],
          dailyHistoryJson,
          reason: 'the rollback rewrote the removed daily history');
      expect(after['flutter.${StorageService.dailyGhostKey}'], ghostJson,
          reason: 'the rollback rewrote the removed ghost');
      expect(after['flutter.${StorageService.saveDataKey}'], saveJson,
          reason: 'the old save is the only one on disk');
      expect(service.totalCoins, 30);
      expect(service.runHistory, hasLength(1));
      expect(service.dailyHistory, hasLength(1));
      expect(service.todayGhost, isNotNull);
      // The refused setString cached the fresh save (issue #232): the
      // readback through the service must show the old save the rollback
      // put back, not the cache's fresh copy.
      expect((await fakeStorage.loadSaveData())!.totalCoins, 30,
          reason: 'the rollback undid the refused setString\'s cache entry');
      expect(fakeStorage.loadRunHistory(), hasLength(1));
      expect(fakeStorage.loadDailyHistory(), hasLength(1));
      expect(fakeStorage.loadDailyGhost(), isNotNull);
    });

    test('a write issued mid-reset waits for the whole transaction '
        '(issue #232)', () async {
      // The old reset awaited its three clears as separate queue entries,
      // so a write issued behind the first clear could run between the
      // clears. The transaction is one entry: nothing touches storage
      // until every step — the fresh save included — has settled.
      final store = installFailingPrefsStore();
      final fakeStorage = StorageService();
      await fakeStorage.init();
      final service = GameStateService(fakeStorage);
      await service.loadSaveData();
      await service.recordEndlessRun(run(score: 120));
      store.writtenKeys.clear();

      // Park the transaction on its first clear.
      final hold = store.holdNextRemove = Completer<void>();
      final resetting = service.resetProgress();
      await store.removeHeld.future;
      expect(store.writtenKeys, isEmpty,
          reason: 'the transaction is parked before its fresh save');

      // A history write issued while the transaction is in flight.
      final racing = fakeStorage.saveRunHistory(const <RunRecord>[]);
      await Future<void>.delayed(Duration.zero);
      expect(store.writtenKeys, isEmpty,
          reason: 'the racing write may not touch the store until the '
              'transaction settles');

      hold.complete();
      await resetting;
      await racing;

      expect(
        store.writtenKeys
            .where((k) => k == 'flutter.${StorageService.saveDataKey}'),
        hasLength(1),
        reason: 'the transaction wrote its one fresh save',
      );
      expect(store.writtenKeys.last, 'flutter.${StorageService.runHistoryKey}',
          reason: 'the racing write ran only after the transaction — its '
              'fresh save included — had settled');
    });

    test('a save issued mid-reset cannot resurrect the old save (issue '
        '#246)', () async {
      // The old shape kept `_saveData` on the doomed save while the
      // reset transaction ran, so a mutator save in the window — a
      // settings toggle, say — encoded the old save and queued behind
      // the wipe: the next launch loaded the progress the player just
      // erased. The save must snapshot the fresh save in the window and
      // wait for the transaction, and the toggle must still land.
      final store = installFailingPrefsStore();
      final fakeStorage = StorageService();
      await fakeStorage.init();
      final service = GameStateService(fakeStorage);
      await service.loadSaveData();
      service.addCoins(30);
      await service.save();
      await service.recordEndlessRun(run(score: 120));
      expect(service.soundEnabled, isTrue, reason: 'precondition: default on');
      store.writtenKeys.clear();

      // Park the transaction on its first clear, the #232 serialization
      // test's recipe.
      final hold = store.holdNextRemove = Completer<void>();
      final resetting = service.resetProgress();
      await store.removeHeld.future;
      expect(store.writtenKeys, isEmpty,
          reason: 'the transaction is parked before its fresh save');

      // A settings toggle inside the window saves, as every mutator does.
      service.toggleSound();
      await Future<void>.delayed(Duration.zero);

      hold.complete();
      await resetting;
      await fakeStorage.pendingWrites;

      final stored = await fakeStorage.loadSaveData();
      expect(stored!.totalCoins, 0,
          reason: 'the fresh save, not the old one, is the last word on '
              'disk');
      expect(stored.currentLevel, 1);
      expect(stored.settings.soundEnabled, isFalse,
          reason: 'a toggle from inside the window is still persisted');
      expect(store.writtenKeys.last, 'flutter.${StorageService.saveDataKey}',
          reason: 'the deferred write still carries the fresh save');
      final storedHistory = fakeStorage.loadRunHistory();
      expect(storedHistory ?? const <RunRecord>[], isEmpty,
          reason: 'the wiped history stays wiped');
      // Memory agrees with the disk: the fresh save is the live one.
      expect(service.totalCoins, 0);
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

    test('a corrupt save does not resurrect its history as phantom stats',
        () async {
      // The save is dead but the history it wrote survives: nothing in
      // that window belongs to the fresh save, so loading must not seed
      // counters, awards, or a ghost from it (issue #218). Five clean
      // banks would seed the lifetime counter and retro-award
      // bank_clean_5 if the dead window were read.
      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey: '{not json at all',
        StorageService.runHistoryKey: jsonEncode(
          [for (var i = 0; i < 5; i++) run(score: 10 * (i + 1)).toJson()],
        ),
        // A real ghost beside the dead save: without one the "no ghost"
        // assertion below would pass vacuously.
        StorageService.dailyGhostKey: jsonEncode(const GhostTrace(
          dateKey: '2026-09-26',
          score: 480,
          banked: true,
          vehicleId: 'sedan_blue',
          samples: [200, 0, 205, -60],
        ).toJson()),
      });

      final storage = StorageService();
      await storage.init();
      final gameState = GameStateService(storage);
      await gameState.loadSaveData();

      expect(gameState.runHistory, isEmpty,
          reason: 'the history of a save that no longer exists is cleared');
      expect(gameState.runStats.shiftsEnded, 0,
          reason: 'the lifetime totals must not seed from the dead window');
      expect(gameState.achievementState.cleanBankedShifts, 0,
          reason: 'the clean-bank counter must not seed from the dead '
              'window');
      expect(gameState.isAchievementUnlocked('bank_clean_5'), isFalse,
          reason: 'no award may be retro-earned by a dead save');
      expect(gameState.todayGhost, isNull,
          reason: 'a fresh save has no ghost to race');
      expect(storage.loadDailyGhost(), isNull,
          reason: 'the dead save ghost is cleared from disk too');

      // And the dead window is gone from disk, not just memory: the
      // restart cannot re-seed from it either.
      final reloaded = await restarted();
      expect(reloaded.runHistory, isEmpty);
      expect(reloaded.achievementState.cleanBankedShifts, 0);
      expect(reloaded.todayGhost, isNull);
    });

    test('a record missing keys loads with defaults, keeping its neighbours',
        () async {
      // fromJson defaults missing keys rather than throwing, so a record
      // written by an older build costs nothing but its unknowns. The
      // save is a real one: a missing save clears its history with
      // everything else (issue #218), and this test is about the record
      // shape alone.
      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey: jsonEncode(SaveData.createDefault().toJson()),
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
