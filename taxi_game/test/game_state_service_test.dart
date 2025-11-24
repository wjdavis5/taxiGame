import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';

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

  test('toggle settings flips the flags', () {
    gameStateService.toggleSound();
    gameStateService.toggleMusic();

    expect(gameStateService.soundEnabled, isFalse);
    expect(gameStateService.musicEnabled, isFalse);
  });
}
