import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/fake_audio_platform.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';

/// The run may only end through its own surfaces (issue #81).
///
/// GameScreen is always pushed with a plain `MaterialPageRoute`, which on
/// iOS transitions with the Cupertino page transition — and that comes
/// with the edge back-swipe: a steer that begins at the left bezel
/// dragged the route away and quit the shift mid-flight, no
/// confirmation, the at-risk score forfeited. The screen now wraps its
/// scaffold in `PopScope(canPop: false)`: the route's popDisposition
/// turns `doNotPop`, which disables `TransitionRoute.popGestureEnabled`,
/// and the Cupertino recognizer only adds its pointer while that
/// enabledCallback holds — so the swipe is dead from pointer-down and
/// the touch steers the cab instead. A vetoed pop attempt (the system
/// back button's `maybePop` path) lands in `onPopInvokedWithResult`,
/// which routes to the pause menu that already names the stake; the
/// menu's own quit pops imperatively, and `Navigator.pop` never consults
/// popDisposition, so every deliberate exit keeps working.
///
/// The tests run under a `TargetPlatform.iOS` variant — the edge-swipe
/// recognizer only exists on the Cupertino page transition it selects —
/// and the HUD polls the game on a repeating timer, so they pump fixed
/// durations, never pumpAndSettle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() async {
    installFakeAudioPlatform();
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
    navigatorKey = GlobalKey<NavigatorState>();
  });

  /// Pushes a live endless [GameScreen] as a real second route. The
  /// swipe never exists for a `home:` route (popGestureEnabled returns
  /// false for the first route), so the screen must be pushed over a
  /// marker page the assertions can also use to see a pop land.
  Future<TaxiGame> pushGameScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          Provider<AudioService>.value(value: AudioService()),
          Provider<HapticsService>.value(value: HapticsService()),
          Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(
            key: ValueKey('beneath_game'),
            body: SizedBox.expand(),
          ),
        ),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const GameScreen(endlessSeed: 42),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // One more settling frame: the push transition reaches its end value
    // on the previous pump, but its status only reads completed after the
    // frame after that — and popGestureEnabled (the recognizer's gate)
    // checks the status, not the value.
    await tester.pump(const Duration(milliseconds: 50));

    final game = tester
        .widget<GameWidget<TaxiGame>>(find.byType(GameWidget<TaxiGame>))
        .game!;
    expect(game.isGameActive, isTrue,
        reason: 'the endless run must be live before any input');
    return game;
  }

  testWidgets('an edge swipe cannot pop the game mid-shift (issue #81)',
      (tester) async {
    await pushGameScreen(tester);

    // A left-edge drag, the iOS back-swipe: down inside the recognizer's
    // 20 px start zone, then a slow deliberate pull well past the
    // halfway progress that commits the pop on release (incremental
    // moves with frames between them — the shape a finger makes, and the
    // shape the drag recognizer actually claims). With the fix the
    // recognizer never engages at pointer-down, so the whole drag is
    // just a touch the game never sees as an exit.
    final gesture = await tester.startGesture(const Offset(5.0, 300.0));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(50.0, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(GameScreen), findsOneWidget,
        reason: 'the swipe must not take the route anywhere');
    expect(find.byKey(const ValueKey('beneath_game')), findsNothing,
        reason: 'the page under the game stays covered');
    expect(find.text('PAUSED'), findsNothing,
        reason: 'a dead swipe is no input at all — not even a pause');
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a vetoed back pauses the shift; the menu still quits (issue #81)',
      (tester) async {
    final game = await pushGameScreen(tester);

    // The system back button's path: the app-level pop dispatch runs the
    // route's maybePop, which the PopScope veto turns into
    // onPopInvokedWithResult(false) — the handler's one job.
    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byType(GameScreen), findsOneWidget,
        reason: 'a vetoed pop leaves the route exactly where it was');
    expect(find.text('PAUSED'), findsOneWidget,
        reason: 'the back attempt routes to the pause menu');
    expect(game.paused, isTrue, reason: 'the shift froze behind the menu');

    // And the menu's own way out still works: the quit button pops
    // imperatively, which never consults popDisposition. The reverse
    // transition needs its frames pumped to finish.
    await tester.tap(find.byKey(const ValueKey('pause_quit_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GameScreen), findsNothing,
        reason: 'the pause menu\'s quit still pops the route');
    expect(find.byKey(const ValueKey('beneath_game')), findsOneWidget,
        reason: 'the page under the game is uncovered again');
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
