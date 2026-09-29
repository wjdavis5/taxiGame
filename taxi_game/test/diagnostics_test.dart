import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/services/diagnostics.dart';

/// The on-device diagnostics tail: the telemetry an offline game can
/// have — bounded, persisted across hard kills, and readable only by the
/// player sharing it by hand.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    Diagnostics.instance.resetForTest();
  });

  test('every line is timestamped and the export carries a header', () {
    Diagnostics.instance.log('[run] something happened');

    final exported = Diagnostics.instance.export();
    expect(exported, contains('CAB HUSTLE diagnostics'));
    expect(exported, contains('local only; shared by the player by hand'));
    // The timestamp precedes the message: the timeline is the point.
    expect(
      exported,
      matches(RegExp(r'\d{2}:\d{2}:\d{2}\.\d{3} \[run\] something happened')),
    );
  });

  test('the ring buffer caps, keeping the newest lines', () {
    for (var i = 0; i < Diagnostics.maxLines + 50; i++) {
      Diagnostics.instance.log('line $i');
    }

    final exported = Diagnostics.instance.export();
    final body = exported.split('---\n').last.split('\n');
    expect(body, hasLength(Diagnostics.maxLines),
        reason: 'the buffer holds exactly its cap, no more');
    expect(body.first, contains('line 50'),
        reason: 'the oldest 50 fell off the back');
    expect(body.last, contains('line ${Diagnostics.maxLines + 49}'));
  });

  test('errors land with their stack frames and flush at once', () async {
    Diagnostics.instance.logError(
      'uncaught',
      StateError('boom'),
      StackTrace.current,
    );

    final exported = Diagnostics.instance.export();
    expect(exported, contains('[error:uncaught] Bad state: boom'));
    expect(exported, contains('diagnostics_test.dart'),
        reason: 'the stack frames that name the thrower travel along');

    // The immediate flush put the error on disk: a fresh session sees it.
    // (The flush logError fires is unawaited by design — await it here so
    // the reset below can't race the write.)
    await Diagnostics.instance.flush();
    Diagnostics.instance.resetForTest();
    await Diagnostics.instance.load();
    expect(Diagnostics.instance.export(), contains('Bad state: boom'));
  });

  test('the tail survives a session restart', () async {
    Diagnostics.instance.log('[session-a] right before the kill');
    await Diagnostics.instance.flush();

    Diagnostics.instance.resetForTest();
    await Diagnostics.instance.load();

    expect(
      Diagnostics.instance.export(),
      contains('[session-a] right before the kill'),
    );
  });

  test('the global hooks route debugPrint and framework errors', () {
    Diagnostics.instance.installGlobalHooks();

    debugPrint('[test] a routed line');
    expect(Diagnostics.instance.export(), contains('[test] a routed line'));

    FlutterError.reportError(FlutterErrorDetails(
      exception: StateError('framework boom'),
      stack: StackTrace.current,
      library: 'diagnostics test',
    ));
    expect(Diagnostics.instance.export(),
        contains('[error:flutter] Bad state: framework boom'));

    // The zone-level hook is armed too (and reset restores the default).
    expect(PlatformDispatcher.instance.onError, isNotNull);
    Diagnostics.instance.resetForTest();
    expect(PlatformDispatcher.instance.onError, isNull);
  });

  test('clear wipes the buffer and the storage', () async {
    Diagnostics.instance.log('gone tomorrow');
    await Diagnostics.instance.clear();

    expect(Diagnostics.instance.export(), isNot(contains('gone tomorrow')));
    Diagnostics.instance.resetForTest();
    await Diagnostics.instance.load();
    expect(
      Diagnostics.instance.export(),
      isNot(contains('gone tomorrow')),
      reason: 'the storage copy went with the buffer',
    );
  });
}
