import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A bounded, on-device record of what the game was doing in the moments
/// before something went wrong — the telemetry an offline game can have
/// without breaking its own zero-network promise.
///
/// Everything lands in a ring buffer ([maxLines] entries, oldest dropped)
/// that is periodically flushed to `shared_preferences`, so a hard
/// native kill still leaves the last written moments on disk for the
/// next launch. Nothing ever leaves the device through this service: the
/// only way out is the player sharing [export] by hand through the OS
/// share sheet ([ShareService.shareText]) — the same user-driven channel
/// the score card uses.
///
/// What feeds it:
/// - [installGlobalHooks] routes every `debugPrint` (the game's crash,
///   near-miss, run, heartbeat, and lifecycle lines) plus uncaught
///   framework and zone errors into the buffer;
/// - anything else can call [log]/[logError] directly.
///
/// A singleton by design: it is the app's log sink, alive for the whole
/// process like the log it is, and read directly (`Diagnostics.instance`)
/// so no provider plumbing stands between a crash and its record.
class Diagnostics {
  Diagnostics._();

  /// The app's one sink.
  static final Diagnostics instance = Diagnostics._();

  /// Buffer depth. Enough to hold several minutes of heartbeats plus a
  /// burst of errors; small enough that the flushed string stays trivial
  /// to persist.
  static const int maxLines = 400;

  /// Where the tail persists between sessions.
  static const String _prefsKey = 'diagnostics_tail';

  final List<String> _lines = <String>[];
  Timer? _flushDebounce;
  bool _hooksInstalled = false;

  DebugPrintCallback? _originalDebugPrint;
  FlutterExceptionHandler? _originalFlutterError;

  /// Loads the previous session's tail. Call once at startup, before the
  /// hooks — the first lines of this session should append to the tail
  /// that survived the last one.
  Future<void> load() async {
    if (_lines.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey) ?? '';
      if (stored.isNotEmpty) {
        _lines.addAll(stored.split('\n'));
      }
    } catch (_) {
      // An unreadable tail is a fresh log; a diagnostics system must
      // never be the thing that crashes.
    }
  }

  /// Appends one entry, timestamped to the millisecond — the timeline is
  /// the whole point when the question is "how long after moving did it
  /// die".
  void log(String message) {
    final now = DateTime.now();
    final stamp = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    _lines.add('$stamp $message');
    while (_lines.length > maxLines) {
      _lines.removeAt(0);
    }
    _scheduleFlush();
  }

  /// Appends an error with its stack's first frames — the frames that
  /// name the thrower. Errors flush immediately: they are the likeliest
  /// last line before a hard kill.
  void logError(String kind, Object error, StackTrace? stack) {
    final frames = stack?.toString().split('\n').take(12).join('\n');
    log('[error:$kind] $error'
        '${frames == null ? '' : '\n$frames'}');
    unawaited(flush());
  }

  /// Routes the framework's error reporters and every `debugPrint`
  /// through [log]. Idempotent. The original handlers stay in the chain
  /// so console output and debug-tool behaviour are unchanged.
  void installGlobalHooks() {
    if (_hooksInstalled) return;
    _hooksInstalled = true;

    _originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      // Framework noise can be chatty; it is telemetry, so it is all
      // worth having — the ring buffer bounds the cost.
      if (message != null && message.isNotEmpty) log(message);
      _originalDebugPrint?.call(message, wrapWidth: wrapWidth);
    };

    _originalFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      logError('flutter', details.exception, details.stack);
      _originalFlutterError?.call(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      logError('uncaught', error, stack);
      // Handled: the app keeps running with the error on record. The
      // default reporter only dumps to console, which we just preserved
      // through the debugPrint hook.
      return true;
    };
  }

  /// The persisted tail, headed with a session marker — what the share
  /// sheet hands out.
  String export() {
    final buffer = StringBuffer()
      ..writeln('CAB HUSTLE diagnostics — ${DateTime.now()}')
      ..writeln('mode=${kReleaseMode ? 'release' : 'debug'} '
          'platform=${defaultTargetPlatform.name}')
      ..writeln('local only; shared by the player by hand')
      ..writeln('---');
    buffer.writeAll(_lines, '\n');
    return buffer.toString();
  }

  /// Flushes the buffer to storage now. Ordinary lines flush on a short
  /// debounce instead — a write per line would thrash prefs during a
  /// chatty frame, and the debounce still lands every burst.
  Future<void> flush() async {
    _flushDebounce?.cancel();
    _flushDebounce = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _lines.join('\n'));
    } catch (_) {}
  }

  /// Wipes buffer and storage — the settings screen's clear button.
  Future<void> clear() async {
    _lines.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  /// Restores the global handlers and empties the buffer — test hygiene,
  /// so one test's hooks never leak into the next.
  @visibleForTesting
  void resetForTest() {
    _flushDebounce?.cancel();
    _flushDebounce = null;
    if (_hooksInstalled) {
      if (_originalDebugPrint != null) debugPrint = _originalDebugPrint!;
      if (_originalFlutterError != null) {
        FlutterError.onError = _originalFlutterError;
      }
      PlatformDispatcher.instance.onError = null;
    }
    _hooksInstalled = false;
    _lines.clear();
  }

  void _scheduleFlush() {
    _flushDebounce ??= Timer(const Duration(milliseconds: 1500), () {
      _flushDebounce = null;
      unawaited(flush());
    });
  }
}
