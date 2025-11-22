import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/save_data.dart';

/// Handles persistent storage of game data
class StorageService {
  static const String _saveDataKey = 'taxi_game_save_data';
  late SharedPreferences _prefs;
  
  /// Initialize storage
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }
  
  /// Save game data
  Future<void> saveSaveData(SaveData data) async {
    final jsonString = jsonEncode(data.toJson());
    await _prefs.setString(_saveDataKey, jsonString);
  }
  
  /// Load game data
  Future<SaveData?> loadSaveData() async {
    final jsonString = _prefs.getString(_saveDataKey);
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
  
  /// Clear all saved data
  Future<void> clearData() async {
    await _prefs.remove(_saveDataKey);
  }
  
  /// Check if save data exists
  bool hasSaveData() {
    return _prefs.containsKey(_saveDataKey);
  }
}
