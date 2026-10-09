import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/main.dart';
import 'package:taxi_game/services/diagnostics.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/main_menu_screen.dart';

/// Startup robustness (issue #231): every await before `runApp` used to
/// be unguarded, so a platform failure — storage that will not open, an
/// orientation lock that refuses — aborted `main()` and left the launch
/// storyboard on screen forever. Now a storage failure reaches a real
/// error surface with a retry, and a cosmetic failure is logged and
/// startup continues.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Diagnostics.instance.resetForTest();
    // Awaiting an unmocked SystemChannels.platform call inside a widget
    // test never completes — the orientation lock included. Answer every
    // call harmlessly; the orientation test overrides this with its
    // refusal.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      return null;
    });
  });

  tearDown(() {
    Diagnostics.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('a storage failure reaches a retry surface, not a softlock',
      (tester) async {
    await startApp(storageFactory: _ThrowingStorage.new);
    await tester.pump();

    expect(find.byKey(const Key('startup_failure_title')), findsOneWidget);
    expect(find.byKey(const Key('startup_failure_retry')), findsOneWidget);
    expect(Diagnostics.instance.export(), contains('[error:startup]'),
        reason: 'the launch failure is on record for support');
    // Discharge the log debounce: the binding checks for pending timers
    // before user tearDowns run.
    await Diagnostics.instance.flush();
  });

  testWidgets('the retry boots the game once storage opens', (tester) async {
    // One instance through the retry: the second init succeeds, as a
    // storage container that opens after a first refusal does.
    final flaky = _FlakyStorage();
    await startApp(storageFactory: () => flaky);
    await tester.pump();
    expect(find.byKey(const Key('startup_failure_retry')), findsOneWidget,
        reason: 'the first boot failed');

    await tester.tap(find.byKey(const Key('startup_failure_retry')));
    // Two frames: the tap's async retry boots the graph, then the
    // replacement app mounts.
    await tester.pump();
    await tester.pump();

    expect(find.byType(MainMenuScreen), findsOneWidget,
        reason: 'a transient failure must not be a dead end');
    await Diagnostics.instance.flush();
  });

  testWidgets('a refused orientation lock is logged and does not stop boot',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        throw PlatformException(code: 'orientation_refused');
      }
      return null;
    });

    await startApp();
    await tester.pump();

    expect(find.byType(MainMenuScreen), findsOneWidget,
        reason: 'presentation failure is not a launch failure');
    expect(Diagnostics.instance.export(), contains('[error:orientation]'));
    expect(Diagnostics.instance.export(), isNot(contains('[error:startup]')));
    await Diagnostics.instance.flush();
  });
}

/// Storage that cannot open at all — a corrupted container or a platform
/// channel that refuses.
class _ThrowingStorage extends StorageService {
  @override
  Future<void> init() async {
    throw StateError('storage container could not be opened');
  }
}

/// Storage that fails its first boot and opens on the retry.
class _FlakyStorage extends StorageService {
  bool _failed = false;

  @override
  Future<void> init() async {
    if (!_failed) {
      _failed = true;
      throw StateError('first boot failed');
    }
    return super.init();
  }
}
