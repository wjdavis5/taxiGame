import 'package:flutter/foundation.dart';
import '../game/levels/level.dart';
import '../models/run_record.dart';
import '../models/run_stats.dart';
import '../models/save_data.dart';
import 'storage_service.dart';

/// Manages global game state and notifies listeners of changes
class GameStateService extends ChangeNotifier {
  final StorageService _storageService;
  late SaveData _saveData;

  /// How many ended shifts the on-device history keeps (issue #17). Old
  /// records fall off the front as new ones arrive: a fixed window is all
  /// the tuning instrument needs, and it bounds the prefs payload forever.
  static const int maxRecordedRuns = 200;

  final List<RunRecord> _runHistory = <RunRecord>[];

  GameStateService(this._storageService) {
    _saveData = SaveData.createDefault();
  }

  // Getters
  int get currentLevel => _saveData.currentLevel;

  /// True once the save sits past the last rung of the tutorial ladder
  /// (issue #16): the ladder is finished, and the game's answer to PLAY —
  /// in the menu stat and the level loader alike — is the Endless
  /// handoff, never a replay of the final level.
  bool get tutorialComplete => _saveData.currentLevel > GameLevel.ladderLength;

  int get totalCoins => _saveData.totalCoins;
  int get totalGems => _saveData.totalGems;
  String get selectedVehicle => _saveData.selectedVehicle;
  List<String> get unlockedVehicles => _saveData.unlockedVehicles;
  bool get soundEnabled => _saveData.settings.soundEnabled;
  bool get musicEnabled => _saveData.settings.musicEnabled;

  /// The best score an endless shift has ever ended with (issue #15).
  int get endlessBestScore => _saveData.endlessBestScore;

  /// Every recorded ended shift, oldest first (issue #17). The raw,
  /// per-shift history; see [runStats] for the aggregates.
  List<RunRecord> get runHistory => List.unmodifiable(_runHistory);

  /// The shift history aggregated for tuning (issue #17): totals, medians,
  /// run-length distribution, bank-vs-push ratio.
  RunStats get runStats => RunStats.compute(_runHistory);

  /// Load save data and the shift history from storage
  Future<void> loadSaveData() async {
    final data = await _storageService.loadSaveData();
    if (data != null) {
      _saveData = data;
    }
    // A missing or corrupt history is a fresh one — the same recovery a
    // corrupt save gets, never a crash.
    final history = _storageService.loadRunHistory();
    if (history != null) {
      _runHistory
        ..clear()
        ..addAll(history);
    }
    notifyListeners();
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
  
  /// Complete a level: award coins and, if it was the player's furthest
  /// level, unlock the next one. Replaying an old level only earns coins.
  void completeLevel(int levelNumber, int coinsEarned) {
    addCoins(coinsEarned);
    if (levelNumber == _saveData.currentLevel) {
      _saveData.currentLevel++;
      notifyListeners();
      save();
    }
  }

  /// Records the score an endless shift just ended with against the
  /// personal best (issue #15). Returns true when [score] beats the
  /// stored best — a new PB — and stores it; a tie keeps the old best.
  /// The score counts however the shift ended: banked payouts and
  /// forfeited unbanked scores are both the number a replay tries to
  /// beat.
  bool recordEndlessScore(int score) {
    if (score <= _saveData.endlessBestScore) return false;
    _saveData.endlessBestScore = score;
    notifyListeners();
    save();
    return true;
  }

  /// Adds an ended shift to the on-device history (issue #17), trimming
  /// the oldest records past [maxRecordedRuns], and persists it. Strictly
  /// local — this is the game's only tuning instrument, and it never
  /// leaves the device.
  Future<void> recordEndlessRun(RunRecord record) async {
    _runHistory.add(record);
    if (_runHistory.length > maxRecordedRuns) {
      _runHistory.removeRange(0, _runHistory.length - maxRecordedRuns);
    }
    notifyListeners();
    await _storageService.saveRunHistory(_runHistory);
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
    // The shift history is progress too (issue #17): a reset wipes it with
    // everything else, so the stats screen never shows numbers from a run
    // of a save that no longer exists.
    _runHistory.clear();
    _storageService.clearRunHistory();
    notifyListeners();
    save();
  }
}
