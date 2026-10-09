import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/daily_result.dart';
import '../models/ghost_trace.dart';
import '../models/run_record.dart';
import '../models/save_data.dart';
import 'diagnostics.dart';

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

  /// Runs one persistence operation, retrying once on failure and landing
  /// a terminal failure in the diagnostics tail (issue #230).
  ///
  /// The mutators on [GameStateService] are fire-and-forget — they redraw
  /// first and save after — so before this guard a refused or throwing
  /// write left only an unhandled-error line, or nothing at all when the
  /// platform answered `false`: the player kept coins, purchases, and PBs
  /// that were not on disk. A retry covers the flaky-transient case; the
  /// log covers the rest, and not throwing keeps a storage failure from
  /// riding a UI callback out as an uncaught async error.
  Future<void> _write(String what, Future<bool> Function() write) async {
    Object? error;
    StackTrace? stack;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (await write()) return;
        // `false` is the platform refusing the write — the same failure
        // class as a throw, and worth the same one retry.
        error = StateError('"$what" write was refused');
      } catch (e, s) {
        error = e;
        stack = s;
      }
    }
    Diagnostics.instance.logError('storage', error!, stack);
  }

  /// Save game data
  Future<void> saveSaveData(SaveData data) async {
    final jsonString = jsonEncode(data.toJson());
    await _write(
      'save data',
      () => _prefs.setString(saveDataKey, jsonString),
    );
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
    await _write(
      'run history',
      () => _prefs.setString(runHistoryKey, jsonString),
    );
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
    await _write('run history', () => _prefs.remove(runHistoryKey));
  }

  /// Persist the completed Daily Shift history (issue #19), oldest first.
  Future<void> saveDailyHistory(List<DailyResult> results) async {
    final jsonString =
        jsonEncode(results.map((result) => result.toJson()).toList());
    await _write(
      'daily history',
      () => _prefs.setString(dailyHistoryKey, jsonString),
    );
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
    await _write('daily history', () => _prefs.remove(dailyHistoryKey));
  }

  /// Persist the Daily Shift ghost trace (issue #20) — the single stored
  /// trace, whichever day it belongs to.
  Future<void> saveDailyGhost(GhostTrace trace) async {
    await _write(
      'daily ghost',
      () => _prefs.setString(dailyGhostKey, jsonEncode(trace.toJson())),
    );
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
    await _write('daily ghost', () => _prefs.remove(dailyGhostKey));
  }

  /// Clear all saved data
  Future<void> clearData() async {
    await _write('save data', () => _prefs.remove(saveDataKey));
  }

  /// Check if save data exists
  bool hasSaveData() {
    return _prefs.containsKey(saveDataKey);
  }
}
