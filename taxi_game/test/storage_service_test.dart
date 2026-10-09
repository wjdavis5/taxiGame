import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/diagnostics.dart';
import 'package:taxi_game/services/storage_service.dart';

import 'helpers/fake_prefs_store.dart';

/// The storage guard (issue #230): writes are fire-and-forget from the
/// gameplay mutators, so a failure has to be retried once and, when it
/// still fails, land in the diagnostics tail — never vanish behind a
/// `false` or an unhandled async error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FailingPrefsStore store;

  setUp(() {
    store = installFailingPrefsStore();
    Diagnostics.instance.resetForTest();
  });

  tearDown(() {
    Diagnostics.instance.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  String key(String name) => 'flutter.$name';

  Future<StorageService> ready() async {
    final storage = StorageService();
    await storage.init();
    return storage;
  }

  test('a write that throws once is retried and lands, without a log line',
      () async {
    final storage = await ready();
    store.throwOnWrites = 1;

    await storage.saveSaveData(SaveData.createDefault());

    expect(
      store.writtenKeys.where((k) => k == key(StorageService.saveDataKey)),
      hasLength(2),
      reason: 'one attempt plus the one retry',
    );
    // The retry really reached the store — the SharedPreferences cache
    // holds the value either way, so only the store proves it landed.
    expect(
      (await store.getAll()).containsKey(key(StorageService.saveDataKey)),
      isTrue,
    );
    expect(Diagnostics.instance.export(), isNot(contains('[error:storage]')),
        reason: 'a recovered write is not an error the player must carry');
  });

  test('a write that throws twice is logged and does not escape', () async {
    final storage = await ready();
    store.throwOnWrites = 2;

    // Completing at all is half the assertion: the fire-and-forget caller
    // must not see an unhandled async error.
    await storage.saveSaveData(SaveData.createDefault());

    expect(
      store.writtenKeys.where((k) => k == key(StorageService.saveDataKey)),
      hasLength(2),
      reason: 'attempt plus one retry, then give up',
    );
    expect(Diagnostics.instance.export(), contains('[error:storage]'));
    expect(
      (await store.getAll()).containsKey(key(StorageService.saveDataKey)),
      isFalse,
    );
  });

  test('a write the platform refuses (false) gets the same retry', () async {
    final storage = await ready();
    store.refuseWrites = 1;

    await storage.saveRunHistory(const <RunRecord>[]);

    expect(
      store.writtenKeys.where((k) => k == key(StorageService.runHistoryKey)),
      hasLength(2),
      reason: 'a false answer is a failure like a throw',
    );
    expect(
      (await store.getAll()).containsKey(key(StorageService.runHistoryKey)),
      isTrue,
    );
  });

  test('a write refused twice is logged with the key named', () async {
    final storage = await ready();
    store.refuseWrites = 2;

    await storage.saveRunHistory(const <RunRecord>[]);

    expect(Diagnostics.instance.export(),
        contains('"run history" write was refused'));
  });

  test('a clear that throws twice is logged and does not escape', () async {
    final storage = await ready();
    await storage.saveRunHistory(const <RunRecord>[]);
    store.throwOnRemoves = 2;

    await storage.clearRunHistory();

    expect(
      store.removedKeys.where((k) => k == key(StorageService.runHistoryKey)),
      hasLength(2),
    );
    expect(Diagnostics.instance.export(), contains('[error:storage]'));
  });
}
