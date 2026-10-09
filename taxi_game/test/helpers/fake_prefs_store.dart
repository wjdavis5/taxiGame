import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// An in-memory prefs store whose writes can fail on demand — the seam
/// for the storage-guard tests (issue #230) and the diagnostics-erase
/// failure (issue #233).
///
/// Extends [InMemorySharedPreferencesStore] so reads, prefixes, and the
/// legacy API's own lookups behave exactly like the mock the rest of the
/// suite installs; only [setValue] and [remove] are intercepted, and
/// every attempt lands in [writtenKeys]/[removedKeys] — failed ones
/// included — so tests can count attempts and prove the retry.
class FailingPrefsStore extends InMemorySharedPreferencesStore {
  FailingPrefsStore() : super.empty();

  /// Upcoming [setValue] calls that throw instead of storing.
  int throwOnWrites = 0;

  /// Upcoming [setValue] calls that answer `false` instead of storing.
  int refuseWrites = 0;

  /// Upcoming [remove] calls that throw instead of removing.
  int throwOnRemoves = 0;

  /// Upcoming [remove] calls that answer `false` instead of removing.
  int refuseRemoves = 0;

  /// Every [setValue] key, in call order — failed attempts included.
  final List<String> writtenKeys = <String>[];

  /// Every [remove] key, in call order — failed attempts included.
  final List<String> removedKeys = <String>[];

  /// When set, the next non-failing [setValue] parks on it before reaching
  /// the store. The hold is single-use: once a call consumes it, later
  /// writes land freely — the window a racing retry needs (issue #230).
  Completer<void>? holdNextWrite;

  /// Completes when a [setValue] reaches [holdNextWrite] and parks.
  final Completer<void> writeHeld = Completer<void>();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    writtenKeys.add(key);
    if (throwOnWrites > 0) {
      throwOnWrites--;
      throw StateError('storage write failed');
    }
    if (refuseWrites > 0) {
      refuseWrites--;
      return false;
    }
    final hold = holdNextWrite;
    if (hold != null) {
      holdNextWrite = null;
      if (!writeHeld.isCompleted) writeHeld.complete();
      await hold.future;
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    removedKeys.add(key);
    if (throwOnRemoves > 0) {
      throwOnRemoves--;
      return Future<bool>.error(StateError('storage remove failed'));
    }
    if (refuseRemoves > 0) {
      refuseRemoves--;
      return Future<bool>.value(false);
    }
    return super.remove(key);
  }
}

/// Installs a [FailingPrefsStore] as the app's prefs backend and returns
/// it. The swap must run when no [SharedPreferences] singleton is cached
/// — [SharedPreferences.setMockInitialValues] clears that cache, and the
/// store assignment follows it. Tests restore the suite's own mock in
/// `tearDown` with `SharedPreferences.setMockInitialValues({})`.
FailingPrefsStore installFailingPrefsStore() {
  final store = FailingPrefsStore();
  SharedPreferences.setMockInitialValues({});
  SharedPreferencesStorePlatform.instance = store;
  return store;
}
