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

/// The virtual stick driven through the real gesture stack (issue #29):
/// drags performed on a live [GameScreen] must move the taxi.
///
/// The HUD polls the game on a repeating timer, so these tests pump fixed
/// durations — never pumpAndSettle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;

  setUp(() async {
    installFakeAudioPlatform();
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  Future<TaxiGame> pumpGameScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          Provider<AudioService>.value(value: AudioService()),
          Provider<HapticsService>.value(value: HapticsService()),
          Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        ],
        child: const MaterialApp(home: GameScreen(endlessSeed: 42)),
      ),
    );
    // One pump resolves the GameWidget's load future, a real-async settle
    // lets the taxi's sprite decode finish (on the first test of a run
    // the fake clock alone never flushes it), then the next pumps run
    // the first live frames.
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // byType matches the exact generic runtimeType.
    final game = tester
        .widget<GameWidget<TaxiGame>>(find.byType(GameWidget<TaxiGame>))
        .game!;
    expect(
      game.isGameActive,
      isTrue,
      reason: 'the endless run must be live before any drag',
    );
    return game;
  }

  testWidgets('gliding up-and-right on the lower half drives the taxi',
      (tester) async {
    final game = await pumpGameScreen(tester);
    expect(game.player.velocity, Vector2.zero());

    // Touch the lower half of the screen (the test canvas is 800x600,
    // the default surface), then glide up-right past the rim.
    final gesture = await tester.startGesture(const Offset(400, 450));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(72, -144));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // Full lock right, hard throttle — and the velocity both axes feed
    // actually moved the taxi.
    expect(game.player.steeringInput, 1.0);
    expect(game.player.throttleInput, greaterThan(0.8));
    expect(game.player.velocity.x, greaterThan(0));
    expect(game.player.velocity.y, lessThan(0));

    // Lifting the thumb lets go of both: the inputs zero immediately and
    // the speed starts bleeding off.
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(game.player.steeringInput, 0);
    expect(game.player.throttleInput, 0);
    final speedAtRelease = -game.player.velocity.y;
    await tester.pump(const Duration(milliseconds: 100));
    expect(-game.player.velocity.y, lessThan(speedAtRelease));
  });

  testWidgets('a vertical glide throttles without steering', (tester) async {
    final game = await pumpGameScreen(tester);

    final gesture = await tester.startGesture(const Offset(400, 450));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, -160));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));

    expect(game.player.throttleInput, 1.0);
    expect(game.player.steeringInput, 0);
    expect(game.player.velocity.x, 0);
    expect(game.player.velocity.y, lessThan(0));

    await gesture.up();
  });

  testWidgets('holding still does not drive — the binary pedal is gone',
      (tester) async {
    final game = await pumpGameScreen(tester);

    final gesture = await tester.startGesture(const Offset(400, 450));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 200));

    expect(game.player.throttleInput, 0,
        reason: 'a parked thumb sits inside the dead zone');
    expect(game.player.velocity.y, 0, reason: 'no drag, no acceleration');
    expect(game.player.velocity.x, 0);

    await gesture.up();
  });

  testWidgets('a touch on the upper half of the screen inputs nothing',
      (tester) async {
    final game = await pumpGameScreen(tester);

    final gesture = await tester.startGesture(const Offset(400, 150));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(72, -72));
    await tester.pump(const Duration(milliseconds: 100));

    expect(game.virtualStick!.isActive, isFalse);
    expect(game.player.steeringInput, 0);
    expect(game.player.throttleInput, 0);
    expect(game.player.velocity, Vector2.zero());

    await gesture.up();
  });
}
