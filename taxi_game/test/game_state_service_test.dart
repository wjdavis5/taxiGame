import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/data/vehicle_catalog.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';

import 'helpers/fake_prefs_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storageService;
  late GameStateService gameStateService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storageService = StorageService();
    await storageService.init();
    gameStateService = GameStateService(storageService);
    await gameStateService.loadSaveData();
  });

  test('defaults load correctly', () {
    expect(gameStateService.currentLevel, 1);
    expect(gameStateService.totalCoins, 0);
    expect(gameStateService.selectedVehicle, 'taxi_yellow');
    expect(gameStateService.soundEnabled, isTrue);
    expect(gameStateService.musicEnabled, isTrue);
    // A first-time player still gets the stick-control hint (issue #37).
    expect(gameStateService.controlHintDismissed, isFalse);
  });

  test('addCoins updates balance', () {
    gameStateService.addCoins(50);
    expect(gameStateService.totalCoins, 50);
  });

  test('unlockVehicle spends coins and unlocks vehicle', () {
    gameStateService.addCoins(100);
    final unlocked = gameStateService.unlockVehicle('sport_taxi', 50);

    expect(unlocked, isTrue);
    expect(gameStateService.totalCoins, 50);
    expect(gameStateService.unlockedVehicles, contains('sport_taxi'));
  });

  test('a repeat unlock of an owned car never charges again (issue #221)',
      () {
    // The double-BUY window: two invocations land before the garage
    // rebuilds, and the old order spent the cost before it checked
    // ownership — the player paid twice for one car. The repeat call is
    // the purchase it repeats, so it reports true and costs nothing.
    gameStateService.addCoins(100);

    expect(gameStateService.unlockVehicle('sport_taxi', 50), isTrue);
    expect(gameStateService.unlockVehicle('sport_taxi', 50), isTrue);
    expect(gameStateService.totalCoins, 50,
        reason: 'one car, one charge');
  });

  test('an unaffordable first unlock still refuses', () {
    expect(gameStateService.unlockVehicle('sport_taxi', 50), isFalse);
    expect(gameStateService.totalCoins, 0);
    expect(gameStateService.unlockedVehicles, isNot(contains('sport_taxi')));
  });

  test('the spend and the unlock ride a single save (issue #230)', () async {
    // The old path saved the spend inside spendCoins and the unlock after
    // it: two flushes, either of which the OS could complete alone. One
    // save carries both sides now. Cars 2 and 4 are unlocked first so the
    // measured purchase earns no achievement — the cars_2/cars_4 awards
    // carry their own save and would muddy the count.
    final store = installFailingPrefsStore();
    final storage = StorageService();
    await storage.init();
    final service = GameStateService(storage);
    await service.loadSaveData();

    service.addCoins(100000);
    for (final id in ['compact_red', 'sedan_blue', 'minivan_gray']) {
      expect(service.unlockVehicle(id, VehicleCatalog.byId(id)!.price),
          isTrue);
    }
    store.writtenKeys.clear();

    expect(
      service.unlockVehicle('suv_green', VehicleCatalog.byId('suv_green')!.price),
      isTrue,
    );
    expect(
      store.writtenKeys
          .where((k) => k == 'flutter.${StorageService.saveDataKey}'),
      hasLength(1),
      reason: 'the spend and unlock are one transaction, so one save',
    );
  });

  test('unlocked and selected vehicles survive a reload', () async {
    final sedanPrice = VehicleCatalog.byId('sedan_blue')!.price;
    gameStateService.addCoins(sedanPrice);
    expect(gameStateService.unlockVehicle('sedan_blue', sedanPrice), isTrue);
    gameStateService.selectVehicle('sedan_blue');

    // Simulate an app restart: a brand-new service stack reading the same
    // on-device store.
    final reloadedStorage = StorageService();
    await reloadedStorage.init();
    final reloaded = GameStateService(reloadedStorage);
    await reloaded.loadSaveData();

    expect(reloaded.totalCoins, 0);
    expect(reloaded.unlockedVehicles, contains('sedan_blue'));
    expect(reloaded.selectedVehicle, 'sedan_blue');
  });

  test('completeLevel awards coins and unlocks the next level', () {
    gameStateService.completeLevel(1, 50);

    expect(gameStateService.totalCoins, 50);
    expect(gameStateService.currentLevel, 2);
  });

  test('replaying an old level earns coins but does not re-advance', () {
    gameStateService.completeLevel(1, 50);
    gameStateService.completeLevel(1, 50);

    expect(gameStateService.totalCoins, 100);
    expect(gameStateService.currentLevel, 2);
  });

  test('toggle settings flips the flags', () {
    gameStateService.toggleSound();
    gameStateService.toggleMusic();

    expect(gameStateService.soundEnabled, isFalse);
    expect(gameStateService.musicEnabled, isFalse);
  });

  // Issue #83: a reset used to swap in `SaveData.createDefault()`, whose
  // factory settings turn sound, music, and vibration back on — and the
  // reset's notifyListeners then handed `true` to the composition root's
  // audio listener, so the menu music started right after the dialog
  // closed. Settings are preference, not progress: they ride over to the
  // fresh save while everything below still wipes.
  test('reset progress keeps the settings toggles off (issue #83)', () async {
    gameStateService.addCoins(75);
    gameStateService.completeLevel(1, 75);
    gameStateService.toggleSound();
    gameStateService.toggleMusic();
    gameStateService.toggleVibration();

    await gameStateService.resetProgress();

    // The progress itself is gone...
    expect(gameStateService.currentLevel, 1);
    expect(gameStateService.totalCoins, 0);
    // ...but the toggles the player turned off stay off: the reset must
    // not restart the menu music it silenced.
    expect(gameStateService.soundEnabled, isFalse);
    expect(gameStateService.musicEnabled, isFalse);
    expect(gameStateService.vibrationEnabled, isFalse);

    // Simulate an app restart: a brand-new service stack reading the same
    // on-device store. The kept settings must be the ones the reset
    // persisted, not defaults resurrected by the next launch.
    final reloadedStorage = StorageService();
    await reloadedStorage.init();
    final reloaded = GameStateService(reloadedStorage);
    await reloaded.loadSaveData();

    expect(reloaded.soundEnabled, isFalse);
    expect(reloaded.musicEnabled, isFalse);
    expect(reloaded.vibrationEnabled, isFalse);
  });

  group('endless personal best (issue #15)', () {
    test('a new player has no best score', () {
      expect(gameStateService.endlessBestScore, 0);
    });

    test('the first ended shift is always a new best', () {
      expect(gameStateService.recordEndlessScore(120), isTrue);
      expect(gameStateService.endlessBestScore, 120);
    });

    test('a lower score does not beat the best and does not store it', () {
      gameStateService.recordEndlessScore(120);

      expect(gameStateService.recordEndlessScore(90), isFalse);
      expect(gameStateService.endlessBestScore, 120);
    });

    test('a tie keeps the old best', () {
      gameStateService.recordEndlessScore(120);

      expect(gameStateService.recordEndlessScore(120), isFalse);
      expect(gameStateService.endlessBestScore, 120);
    });

    test('the best survives an app restart', () async {
      gameStateService.recordEndlessScore(340);

      // Simulate an app restart: a brand-new service stack reading the
      // same on-device store.
      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();

      expect(reloaded.endlessBestScore, 340);
    });

    test('a save written before the best existed loads as no best', () {
      // A pre-issue-#15 save: no endlessBestScore key at all.
      final save = SaveData.fromJson({
        'currentLevel': 3,
        'totalCoins': 40,
        'totalGems': 0,
        'unlockedVehicles': ['taxi_yellow'],
        'selectedVehicle': 'taxi_yellow',
        'achievements': <String, bool>{},
        'settings': Settings.createDefault().toJson(),
      });

      expect(save.endlessBestScore, 0,
          reason: 'a missing key means "no shift ever ended", not a '
              'corrupt save');
      expect(save.toJson()['endlessBestScore'], 0,
          reason: 'and it round-trips into new saves');
    });
  });
}
