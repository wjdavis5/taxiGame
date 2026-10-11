import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/data/vehicle_catalog.dart';
import 'package:taxi_game/models/city_license.dart';
import 'package:taxi_game/models/fare_type.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The City License board (issue #278): a local challenge board of
/// replayable named objectives across banking, close calls, fare kinds,
/// weather, and vehicle tradeoffs. These tests pin every family's rules,
/// that completion persists and is never consumed, that every entry is a
/// real objective with a real witness run, and that no entry carries a
/// network path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  LicenseRun run({
    int score = 0,
    bool banked = false,
    int livesLost = 0,
    int nearMisses = 0,
    Map<String, int> acceptedByKind = const {},
    String vehicleId = 'taxi_yellow',
    int seed = 0,
    double distancePx = 0,
  }) =>
      LicenseRun(
        score: score,
        banked: banked,
        livesLost: livesLost,
        nearMisses: nearMisses,
        acceptedByKind: acceptedByKind,
        vehicleId: vehicleId,
        seed: seed,
        distancePx: distancePx,
      );

  /// The first seed whose first [distancePx] px contain enough [met]
  /// weather. The search is the honest way to build a witness: weather is
  /// a pure function of the seed, and a hard-coded seed would pin the
  /// generator instead of the rule.
  int seedWhere(
    bool Function(LicenseRun run) met, {
    double distancePx = 40000,
  }) {
    for (var seed = 0; seed < 1000; seed++) {
      final candidate = run(seed: seed, distancePx: distancePx);
      if (met(candidate)) return seed;
    }
    fail('no seed produced the wanted weather — the generator changed');
  }

  group('the board covers every family with real entries', () {
    test('the five families all carry objectives', () {
      for (final family in LicenseFamily.values) {
        expect(
          CityLicense.board.where((rule) => rule.family == family),
          isNotEmpty,
          reason: '${family.label} is one of the acceptance criteria',
        );
      }
    });

    test('every entry is a named objective, never a placeholder', () {
      const placeholderWords = [
        'TBD',
        'TODO',
        'PLACEHOLDER',
        'COMING SOON',
        'XXX',
        'LOREM',
      ];
      for (final rule in CityLicense.board) {
        expect(rule.id.trim(), isNotEmpty);
        expect(rule.title.trim(), isNotEmpty);
        expect(rule.brief.trim(), isNotEmpty);
        for (final word in placeholderWords) {
          expect(rule.title.toUpperCase(), isNot(contains(word)));
          expect(rule.brief.toUpperCase(), isNot(contains(word)));
        }
      }
      final ids = CityLicense.board.map((rule) => rule.id).toSet();
      expect(ids.length, CityLicense.board.length,
          reason: 'stable ids must be unique — they are the save keys');
    });

    test('every brief names the threshold its rule enforces', () {
      // The rule reads its threshold field and the card quotes it, so a
      // re-tuned number that leaves the old text behind fails here: the
      // card can never lie with the suite green.
      for (final rule in CityLicense.board) {
        expect(rule.brief, contains('${rule.threshold}'),
            reason: '${rule.id} enforces ${rule.threshold}; its card must '
                'name the number the rule reads');
      }
    });

    test('the vehicle rules name cars the garage actually sells', () {
      for (final rule in CityLicense.board) {
        final id = rule.requiredVehicleId;
        if (id == null) continue;
        expect(VehicleCatalog.byId(id), isNotNull,
            reason: '${rule.id} names an unknown car "$id"');
      }
    });

    test('the fare-kind rules name the merged contract vocabulary', () {
      final known = FareType.values.map((type) => type.name).toSet();
      for (final rule in CityLicense.board) {
        final kind = rule.fareKind;
        if (kind == null) continue;
        expect(known, contains(kind),
            reason: '${rule.id} names an unknown fare kind "$kind"');
      }
    });
  });

  group('banking', () {
    test('CLEAN BANK wants a bank with no crash', () {
      expect(LicenseRule.cleanBank.isMet(run(banked: true)), isTrue);
      expect(
          LicenseRule.cleanBank.isMet(run(banked: true, livesLost: 1)), isFalse,
          reason: 'a bank after a crash is not clean');
      expect(LicenseRule.cleanBank.isMet(run(score: 5000)), isFalse,
          reason: 'a wrecked shift never banked');
    });

    test('BIG BANK wants 4000 banked, not merely earned', () {
      expect(
          LicenseRule.bigBank.isMet(run(banked: true, score: 4000)), isTrue);
      expect(
          LicenseRule.bigBank.isMet(run(banked: true, score: 3999)), isFalse);
      expect(LicenseRule.bigBank.isMet(run(score: 5000)), isFalse,
          reason: 'the bar is the bank, not the at-risk score');
    });
  });

  group('close calls', () {
    test('TIGHT THREAD wants 8 cleared passes', () {
      expect(LicenseRule.tightThread.isMet(run(nearMisses: 8)), isTrue);
      expect(LicenseRule.tightThread.isMet(run(nearMisses: 7)), isFalse);
    });

    test('NEEDLE THREAD wants 15', () {
      expect(LicenseRule.needleThread.isMet(run(nearMisses: 15)), isTrue);
      expect(LicenseRule.needleThread.isMet(run(nearMisses: 14)), isFalse);
    });
  });

  group('fare kinds', () {
    test('VIP RUN wants 2 boarded VIP fares', () {
      expect(LicenseRule.vipRun.isMet(run(acceptedByKind: const {'vip': 2})),
          isTrue);
      expect(LicenseRule.vipRun.isMet(run(acceptedByKind: const {'vip': 1})),
          isFalse);
      expect(
          LicenseRule.vipRun
              .isMet(run(acceptedByKind: const {'standard': 9})),
          isFalse);
    });

    test('LONG HAULER wants 2 boarded long-hauls', () {
      expect(
          LicenseRule.longHaulRun
              .isMet(run(acceptedByKind: const {'longHaul': 2})),
          isTrue);
      expect(
          LicenseRule.longHaulRun
              .isMet(run(acceptedByKind: const {'longHaul': 1})),
          isFalse);
    });

    test('FAR SIDE wants 3 boarded far-side fares', () {
      expect(
          LicenseRule.farSideRun
              .isMet(run(acceptedByKind: const {'awkward': 3})),
          isTrue);
      expect(
          LicenseRule.farSideRun
              .isMet(run(acceptedByKind: const {'awkward': 2})),
          isFalse);
    });
  });

  group('weather', () {
    test('RAIN RUN wants 300 m in the rain, measured from the seed', () {
      final seed = seedWhere((r) => r.rainMetres >= 300);
      expect(LicenseRule.rainRun.isMet(run(seed: seed, distancePx: 40000)),
          isTrue);
      expect(
          LicenseRule.rainRun.isMet(run(seed: seed, distancePx: 5000)),
          isFalse,
          reason: 'the calm open is always clear (issue #24)');
    });

    test('FOG RUN wants 300 m in fog', () {
      final seed = seedWhere((r) => r.fogMetres >= 300);
      expect(LicenseRule.fogRun.isMet(run(seed: seed, distancePx: 40000)),
          isTrue);
      expect(LicenseRule.fogRun.isMet(run(seed: 0, distancePx: 5000)), isFalse);
    });

    test('NIGHT SHIFT wants 300 m after dark', () {
      // Night begins 31 200 px in (0.52 of the 60 000 px day, issue #24).
      expect(
          LicenseRule.nightRun.isMet(run(distancePx: 34500)), isTrue,
          reason: '330 m past the 3.12 km night line');
      expect(LicenseRule.nightRun.isMet(run(distancePx: 33000)), isFalse,
          reason: '180 m after dark is short of the bar');
      expect(LicenseRule.nightRun.isMet(run(distancePx: 30000)), isFalse,
          reason: 'daylight completes nothing');
    });

    test('a run that never reached the weather front completes nothing',
        () {
      final calm = run(seed: 12345, distancePx: 5000);
      expect(calm.rainMetres, 0);
      expect(calm.fogMetres, 0);
      expect(calm.nightMetres, 0);
    });
  });

  group('vehicle tradeoffs', () {
    test('COMPACT PRECISION wants 8 close calls in the City Compact', () {
      expect(
          LicenseRule.compactThread
              .isMet(run(vehicleId: 'compact_red', nearMisses: 8)),
          isTrue);
      expect(
          LicenseRule.compactThread
              .isMet(run(vehicleId: 'taxi_yellow', nearMisses: 8)),
          isFalse,
          reason: 'the car is half the objective');
      expect(
          LicenseRule.compactThread
              .isMet(run(vehicleId: 'compact_red', nearMisses: 7)),
          isFalse);
    });

    test('EXECUTIVE DISCIPLINE wants 3000 banked in The Executive', () {
      expect(
          LicenseRule.executiveBank.isMet(
              run(vehicleId: 'luxury_white', banked: true, score: 3000)),
          isTrue);
      expect(
          LicenseRule.executiveBank.isMet(
              run(vehicleId: 'luxury_white', banked: true, score: 2999)),
          isFalse);
      expect(
          LicenseRule.executiveBank
              .isMet(run(vehicleId: 'taxi_yellow', banked: true, score: 5000)),
          isFalse);
    });
  });

  group('no placeholder can hide in a rule with no witness', () {
    test('every rule is met by a constructible run', () {
      final rainSeed = seedWhere((r) => r.rainMetres >= 300);
      final fogSeed = seedWhere((r) => r.fogMetres >= 300);
      final witnesses = <LicenseRule, LicenseRun>{
        LicenseRule.cleanBank: run(banked: true),
        LicenseRule.bigBank: run(banked: true, score: 4000),
        LicenseRule.tightThread: run(nearMisses: 8),
        LicenseRule.needleThread: run(nearMisses: 15),
        LicenseRule.vipRun: run(acceptedByKind: const {'vip': 2}),
        LicenseRule.longHaulRun: run(acceptedByKind: const {'longHaul': 2}),
        LicenseRule.farSideRun: run(acceptedByKind: const {'awkward': 3}),
        LicenseRule.rainRun: run(seed: rainSeed, distancePx: 40000),
        LicenseRule.fogRun: run(seed: fogSeed, distancePx: 40000),
        LicenseRule.nightRun: run(distancePx: 40000),
        LicenseRule.compactThread:
            run(vehicleId: 'compact_red', nearMisses: 8),
        LicenseRule.executiveBank:
            run(vehicleId: 'luxury_white', banked: true, score: 3000),
      };
      for (final rule in CityLicense.board) {
        final witness = witnesses[rule];
        expect(witness, isNotNull, reason: '${rule.id} has no witness run');
        expect(rule.isMet(witness!), isTrue,
            reason: '${rule.id} is not met by its own witness');
      }
    });
  });

  group('replayable: completion is a record, never a consumption', () {
    test('a completed objective stays on the board and can be met again', () {
      final first = CityLicense.completedBy(run(banked: true));
      expect(first, contains(LicenseRule.cleanBank));

      // The board is unchanged by a completion — nothing is removed — and
      // the same run meets the same rule again on any later attempt.
      expect(CityLicense.board, contains(LicenseRule.cleanBank));
      expect(CityLicense.completedBy(run(banked: true)),
          contains(LicenseRule.cleanBank));
      expect(
          CityLicense.completedBy(run(banked: true, livesLost: 0)),
          contains(LicenseRule.cleanBank),
          reason: 'the bar can be cleared again after it is cleared once');
    });

    test('nextOpen walks the board in order and stops at the first open one',
        () {
      expect(CityLicense.nextOpen(const {}), LicenseRule.cleanBank);
      expect(CityLicense.nextOpen(const {'cleanBank'}), LicenseRule.bigBank);
      expect(
          CityLicense.nextOpen(
              CityLicense.board.map((rule) => rule.id).toSet()),
          isNull);
    });
  });

  group('completion persists in the save', () {
    test('a finished shift marks its objectives, and they survive a restart',
        () async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await gameStateService.recordEndlessRun(const RunRecord(
        endedAtMs: 0,
        distancePx: 34500,
        score: 1200,
        faresDelivered: 10,
        nearMisses: 8,
        longestChain: 3,
        livesLost: 0,
        lifeLossDistancesPx: [],
        banked: true,
        durationSeconds: 300,
        acceptedByKind: {'vip': 2},
        vehicleId: 'compact_red',
      ));

      expect(gameStateService.isLicenseObjectiveComplete('cleanBank'), isTrue);
      expect(gameStateService.isLicenseObjectiveComplete('tightThread'), isTrue);
      expect(gameStateService.isLicenseObjectiveComplete('vipRun'), isTrue);
      expect(
          gameStateService.isLicenseObjectiveComplete('compactThread'), isTrue,
          reason: 'the record carries the car the shift was driven in');
      expect(gameStateService.isLicenseObjectiveComplete('nightRun'), isTrue,
          reason: 'the driven span ran past the night line');
      expect(gameStateService.isLicenseObjectiveComplete('bigBank'), isFalse,
          reason: '1200 banked is short of 4000');
      expect(gameStateService.isLicenseObjectiveComplete('executiveBank'),
          isFalse,
          reason: 'the wrong car cannot complete a car objective');
      expect(gameStateService.completedLicenseObjectiveCount,
          gameStateService.completedLicenseObjectiveIds.length);

      // The save is queued (issue #230); the reload must read the settled
      // state, not a snapshot from mid-queue.
      await storageService.pendingWrites;

      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();

      expect(reloaded.isLicenseObjectiveComplete('cleanBank'), isTrue,
          reason: 'completion is on-device progress: it survives a restart');
      expect(reloaded.isLicenseObjectiveComplete('compactThread'), isTrue);
      expect(reloaded.completedLicenseObjectiveIds,
          containsAll(<String>['cleanBank', 'tightThread', 'vipRun']));
    });

    test('a later attempt never un-completes an objective', () async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await gameStateService.recordEndlessRun(const RunRecord(
        endedAtMs: 0,
        distancePx: 9000,
        score: 300,
        faresDelivered: 3,
        longestChain: 2,
        livesLost: 0,
        lifeLossDistancesPx: [],
        banked: true,
        durationSeconds: 120,
      ));
      expect(gameStateService.isLicenseObjectiveComplete('cleanBank'), isTrue);

      // A wrecked, careless run afterwards: the board is a record of what
      // happened, so the clean bank stays complete.
      await gameStateService.recordEndlessRun(const RunRecord(
        endedAtMs: 0,
        distancePx: 4000,
        score: 0,
        faresDelivered: 1,
        longestChain: 1,
        livesLost: 3,
        lifeLossDistancesPx: [1000, 2000, 3000],
        banked: false,
        durationSeconds: 60,
      ));
      expect(gameStateService.isLicenseObjectiveComplete('cleanBank'), isTrue,
          reason: 'a replay may complete an objective again, never clear it');
    });

    test('the completed count counts board ids, never stray save entries',
        () async {
      final save = SaveData.createDefault()
        ..licenseObjectives['cleanBank'] = true
        // An id no build of this board knows: a future objective, or a
        // hand edit. It must not inflate the progress line.
        ..licenseObjectives['future_objective'] = true;
      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey: jsonEncode(save.toJson()),
      });
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);
      await gameStateService.loadSaveData();

      expect(gameStateService.completedLicenseObjectiveCount, 1,
          reason: 'one board id is complete; the stray entry is not one');
      expect(gameStateService.completedLicenseObjectiveIds,
          containsAll(<String>['cleanBank', 'future_objective']),
          reason: 'the map keeps whatever it holds; only the count is '
              'scoped to the board');
    });

    test('a save written before the board loads as an empty board', () {
      // A pre-issue-#278 save: no licenseObjectives key at all.
      final save = SaveData.fromJson({
        'currentLevel': 3,
        'totalCoins': 40,
        'totalGems': 0,
        'unlockedVehicles': ['taxi_yellow'],
        'selectedVehicle': 'taxi_yellow',
        'achievements': <String, bool>{},
        'settings': Settings.createDefault().toJson(),
      });

      expect(save.licenseObjectives, isEmpty,
          reason: 'a missing key means "nothing completed yet", not a '
              'corrupt save');
      expect(save.toJson()['licenseObjectives'], isNotNull,
          reason: 'and it round-trips into new saves');
    });

    test('the completed map round-trips through JSON', () {
      final save = SaveData.createDefault()
        ..licenseObjectives['cleanBank'] = true
        ..licenseObjectives['rainRun'] = true;
      final restored = SaveData.fromJson(
          jsonDecode(jsonEncode(save.toJson())) as Map<String, dynamic>);
      expect(restored.licenseObjectives,
          {'cleanBank': true, 'rainRun': true});
    });
  });

  group('no network, account, or leaderboard path (issue #278)', () {
    test('no shipped license surface carries network machinery', () {
      // The board's whole point is that every objective is local: the
      // save holds completion and the weather is computed from the run's
      // own seed. A denylist heuristic, not a proof, like the gauntlet's.
      const denied = <String>[
        'package:http',
        'package:dio',
        'web_socket_channel',
        'HttpClient',
        'WebSocket',
        'RawSocket',
        'InternetAddress',
        'Socket(',
        'Uri.https',
        'Uri.http',
        'Image.network',
        'NetworkImage',
      ];
      final files = <File>[
        File('lib/models/city_license.dart'),
        File('lib/ui/screens/city_license_screen.dart'),
      ];
      for (final file in files) {
        expect(file.existsSync(), isTrue, reason: 'missing ${file.path}');
        final text = file.readAsStringSync();
        for (final token in denied) {
          expect(text.contains(token), isFalse,
              reason: '${file.path} carries "$token"');
        }
      }
    });

    test('the board names no account or leaderboard path', () {
      const denied = <String>[
        'dart:io',
        'dart:html',
        'leaderboard',
        'account',
        'signIn',
        'oauth',
      ];
      final text = File('lib/models/city_license.dart').readAsStringSync();
      for (final token in denied) {
        expect(text.contains(token), isFalse,
            reason: 'lib/models/city_license.dart carries "$token"');
      }
    });
  });
}
