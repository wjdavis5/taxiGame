import 'package:flutter/foundation.dart';
import '../models/save_data.dart';
import 'storage_service.dart';

/// Manages global game state and notifies listeners of changes
class GameStateService extends ChangeNotifier {
  final StorageService _storageService;
  late SaveData _saveData;
  
  GameStateService(this._storageService) {
    _saveData = SaveData.createDefault();
  }
  
  // Getters
  int get currentLevel => _saveData.currentLevel;
  int get totalCoins => _saveData.totalCoins;
  int get totalGems => _saveData.totalGems;
  String get selectedVehicle => _saveData.selectedVehicle;
  List<String> get unlockedVehicles => _saveData.unlockedVehicles;
  bool get soundEnabled => _saveData.settings.soundEnabled;
  bool get musicEnabled => _saveData.settings.musicEnabled;
  
  /// Load save data from storage
  Future<void> loadSaveData() async {
    final data = await _storageService.loadSaveData();
    if (data != null) {
      _saveData = data;
      notifyListeners();
    }
  }
  
  /// Save current data to storage
  Future<void> save() async {
    await _storageService.saveSaveData(_saveData);
  }
  
  /// Add coins to player's total
  void addCoins(int amount) {
    _saveData.totalCoins += amount;
    notifyListeners();
    save();
  }
  
  /// Spend coins (returns true if successful)
  bool spendCoins(int amount) {
    if (_saveData.totalCoins >= amount) {
      _saveData.totalCoins -= amount;
      notifyListeners();
      save();
      return true;
    }
    return false;
  }
  
  /// Complete current level and unlock next
  void completeLevel(int coinsEarned) {
    addCoins(coinsEarned);
    if (_saveData.currentLevel == currentLevel) {
      _saveData.currentLevel++;
      notifyListeners();
      save();
    }
  }
  
  /// Unlock a vehicle
  bool unlockVehicle(String vehicleId, int cost) {
    if (spendCoins(cost)) {
      if (!_saveData.unlockedVehicles.contains(vehicleId)) {
        _saveData.unlockedVehicles.add(vehicleId);
        notifyListeners();
        save();
      }
      return true;
    }
    return false;
  }
  
  /// Select a vehicle
  void selectVehicle(String vehicleId) {
    if (_saveData.unlockedVehicles.contains(vehicleId)) {
      _saveData.selectedVehicle = vehicleId;
      notifyListeners();
      save();
    }
  }
  
  /// Check if vehicle is unlocked
  bool isVehicleUnlocked(String vehicleId) {
    return _saveData.unlockedVehicles.contains(vehicleId);
  }
  
  /// Toggle sound
  void toggleSound() {
    _saveData.settings.soundEnabled = !_saveData.settings.soundEnabled;
    notifyListeners();
    save();
  }
  
  /// Toggle music
  void toggleMusic() {
    _saveData.settings.musicEnabled = !_saveData.settings.musicEnabled;
    notifyListeners();
    save();
  }
  
  /// Reset all progress (for testing)
  void resetProgress() {
    _saveData = SaveData.createDefault();
    notifyListeners();
    save();
  }
}
