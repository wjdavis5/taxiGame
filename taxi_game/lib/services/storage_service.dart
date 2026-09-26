import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/daily_result.dart';
import '../models/ghost_trace.dart';
import '../models/run_record.dart';
import '../models/save_data.dart';

/// Handles persistent storage of game data
class StorageService {
  static const String saveDataKey = 'taxi_game_save_data';

  /// The on-device shift history (issue #17), kept under its own key so
  /// the growing list never rides along on every coin save.
  static const String runHistoryKey = 'taxi_game_run_history';

  /// The completed Daily Shift history (issue #19), under its own key for
  /// the same reason — and strictly local, like everything else: the
  /// daily's shared course is derived from the date, never fetched.
  static const String dailyHistoryKey = 'taxi_game_daily_history';

  /// The Daily Shift ghost (issue #20) — the best run's sampled position
  /// trace for one day's course, under its own key. Exactly one trace is
  /// ever stored: a trace from an earlier day is dead (that course never
  /// returns), so the payload stays bounded at one trace forever.
  static const String dailyGhostKey = 'taxi_game_daily_ghost';
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

  /// Persist the completed Daily Shift history (issue #19), oldest first.
  Future<void> saveDailyHistory(List<DailyResult> results) async {
    final jsonString =
        jsonEncode(results.map((result) => result.toJson()).toList());
    await _prefs.setString(dailyHistoryKey, jsonString);
  }

  /// Load the completed Daily Shift history, oldest first. Null when none
  /// was ever written; corrupt data returns null — the daily history
  /// starts over rather than crashing the app, exactly like a corrupt
  /// save or a corrupt shift history.
  List<DailyResult>? loadDailyHistory() {
    final jsonString = _prefs.getString(dailyHistoryKey);
    if (jsonString == null) return null;
    try {
      final list = jsonDecode(jsonString) as List;
      return list
          .map((entry) => DailyResult.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return null;
    }
  }

  /// Wipe the completed Daily Shift history.
  Future<void> clearDailyHistory() async {
    await _prefs.remove(dailyHistoryKey);
  }

  /// Persist the Daily Shift ghost trace (issue #20) — the single stored
  /// trace, whichever day it belongs to.
  Future<void> saveDailyGhost(GhostTrace trace) async {
    await _prefs.setString(dailyGhostKey, jsonEncode(trace.toJson()));
  }

  /// Load the Daily Shift ghost trace, or null when none was ever
  /// written. Corrupt data returns null — the ghost is lost, not the
  /// app — exactly like a corrupt save or a corrupt history.
  GhostTrace? loadDailyGhost() {
    final jsonString = _prefs.getString(dailyGhostKey);
    if (jsonString == null) return null;
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return GhostTrace.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  /// Wipe the Daily Shift ghost trace.
  Future<void> clearDailyGhost() async {
    await _prefs.remove(dailyGhostKey);
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
