import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/run_record.dart';
import '../models/save_data.dart';

/// Handles persistent storage of game data
class StorageService {
  static const String saveDataKey = 'taxi_game_save_data';

  /// The on-device shift history (issue #17), kept under its own key so
  /// the growing list never rides along on every coin save.
  static const String runHistoryKey = 'taxi_game_run_history';
  late SharedPreferences _prefs;

  /// Initialize storage
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Save game data
  Future<void> saveSaveData(SaveData data) async {
    final jsonString = jsonEncode(data.toJson());
    await _prefs.setString(saveDataKey, jsonString);
  }

  /// Load game data
  Future<SaveData?> loadSaveData() async {
    final jsonString = _prefs.getString(saveDataKey);
    if (jsonString != null) {
      try {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return SaveData.fromJson(json);
      } catch (e) {
        // If data is corrupted, return null to use default
        return null;
      }
    }
    return null;
  }

  /// Persist the ended-shift history (issue #17), oldest first.
  Future<void> saveRunHistory(List<RunRecord> runs) async {
    final jsonString =
        jsonEncode(runs.map((record) => record.toJson()).toList());
    await _prefs.setString(runHistoryKey, jsonString);
  }

  /// Load the ended-shift history, oldest first. Null when none was ever
  /// written; an empty list only comes back from a stored empty history.
  /// Corrupt data returns null — the history starts over rather than
  /// crashing the app, exactly like a corrupt save.
  List<RunRecord>? loadRunHistory() {
    final jsonString = _prefs.getString(runHistoryKey);
    if (jsonString == null) return null;
    try {
      final list = jsonDecode(jsonString) as List;
      return list
          .map((entry) => RunRecord.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return null;
    }
  }

  /// Wipe the ended-shift history.
  Future<void> clearRunHistory() async {
    await _prefs.remove(runHistoryKey);
  }

  /// Clear all saved data
  Future<void> clearData() async {
    await _prefs.remove(saveDataKey);
  }

  /// Check if save data exists
  bool hasSaveData() {
    return _prefs.containsKey(saveDataKey);
  }
}
