import 'dart:async' show Completer, Zone, unawaited;
import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// The operations waiting their turn, in call order (issue #230).
  final List<_QueuedWrite> _queuedWrites = <_QueuedWrite>[];

  /// True while one operation — its attempts and retry included — is
  /// running on the platform; nothing else may touch storage until it
  /// settles. Without the queue each operation ran independently, so an
  /// older save whose first attempt failed could retry *after* a newer
  /// save had already landed and overwrite the newer snapshot with the
  /// older one.
  bool _writeInFlight = false;

  /// Completed when the last queued operation settles (see
  /// [pendingWrites]).
  Completer<void>? _writesIdle;

  /// Settles when every queued and in-flight operation has finished. Test
  /// observability for the ordering guarantee above: the fire-and-forget
  /// savers make no promise about *when* a write lands, so a test that
  /// measures platform traffic or reloads after a burst of saves must
  /// wait for the queue.
  @visibleForTesting
  Future<void> get pendingWrites {
    if (!_writeInFlight && _queuedWrites.isEmpty) {
      return Future<void>.value();
    }
    return (_writesIdle ??= Completer<void>()).future;
  }

  /// Runs one persistence operation, retrying once on failure and landing
  /// a terminal failure in the diagnostics tail (issue #230). Returns
  /// whether the operation reached the platform — `false` after both
  /// attempts fail — so a caller that must react to a failed wipe (the
  /// reset, issue #232) can; ordinary savers ignore the answer.
  ///
  /// The mutators on [GameStateService] are fire-and-forget — they redraw
  /// first and save after — so before this guard a refused or throwing
  /// write left only an unhandled-error line, or nothing at all when the
  /// platform answered `false`: the player kept coins, purchases, and PBs
  /// that were not on disk. A retry covers the flaky-transient case; the
  /// log covers the rest, and not throwing keeps a storage failure from
  /// riding a UI callback out as an uncaught async error.
  ///
  /// The operation is queued and only starts when the previous one —
  /// attempts, retry, and all — has settled, so operations land in call
  /// order no matter how slow a retry is. With nothing in flight it
  /// starts right away, keeping the saver's old synchronous reach for
  /// the platform.
  Future<bool> _write(String what, Future<bool> Function() write) {
    final operation = _QueuedWrite(what, write, Zone.current);
    _queuedWrites.add(operation);
    _drainWrites();
    return operation.completer.future;
  }

  /// Starts the next queued operation if nothing is running, or releases
  /// the idle waiters when the queue is empty.
  void _drainWrites() {
    if (_writeInFlight) return;
    if (_queuedWrites.isEmpty) {
      _writesIdle?.complete();
      _writesIdle = null;
      return;
    }
    final operation = _queuedWrites.removeAt(0);
    _writeInFlight = true;
    // Run the operation in the zone that requested it: a widget test
    // builds the service in `setUp` (the outer zone) and awaits a save in
    // the fake-async test body, and a platform future created in the
    // wrong zone never resolves there.
    unawaited(operation.zone.run(() async {
      var succeeded = false;
      try {
        succeeded = await _attemptWrite(operation.what, operation.write);
      } catch (_) {
        // _attemptWrite swallows by contract; a surprise must still settle
        // its caller and release the queue rather than hang it.
      }
      _writeInFlight = false;
      operation.completer.complete(succeeded);
      _drainWrites();
    }));
  }

  /// The one attempt-then-retry body of [_write].
  Future<bool> _attemptWrite(
    String what,
    Future<bool> Function() write,
  ) async {
    Object? error;
    StackTrace? stack;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        if (await write()) return true;
        // `false` is the platform refusing the write — the same failure
        // class as a throw, and worth the same one retry.
        error = StateError('"$what" write was refused');
      } catch (e, s) {
        error = e;
        stack = s;
      }
    }
    Diagnostics.instance.logError('storage', error!, stack);
    return false;
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

  /// Wipe the ended-shift history. Returns whether the remove landed
  /// (issue #232): the reset refuses to write its fresh save beside a
  /// history it could not clear.
  Future<bool> clearRunHistory() =>
      _write('run history', () => _prefs.remove(runHistoryKey));

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

  /// Wipe the completed Daily Shift history. Returns whether the remove
  /// landed, like [clearRunHistory] (issue #232).
  Future<bool> clearDailyHistory() =>
      _write('daily history', () => _prefs.remove(dailyHistoryKey));

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

  /// Wipe the Daily Shift ghost trace. Returns whether the remove landed,
  /// like [clearRunHistory] (issue #232).
  Future<bool> clearDailyGhost() =>
      _write('daily ghost', () => _prefs.remove(dailyGhostKey));

  /// Clear all saved data
  Future<void> clearData() async {
    await _write('save data', () => _prefs.remove(saveDataKey));
  }

  /// Check if save data exists
  bool hasSaveData() {
    return _prefs.containsKey(saveDataKey);
  }
}

/// One storage operation waiting its turn: what it is, how to run it, the
/// zone that asked for it (issue #230), and the result its caller awaits.
class _QueuedWrite {
  _QueuedWrite(this.what, this.write, this.zone);

  final String what;
  final Future<bool> Function() write;
  final Zone zone;
  final Completer<bool> completer = Completer<bool>();
}
