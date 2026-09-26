import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// Mounts [game] headlessly (the pattern flame_test uses) so component
/// `onLoad` hooks run, then returns it.
Future<TaxiGame> mountGame(TaxiGame game) async {
  game.onGameResize(Vector2(400, 800));
  await game.onLoad();
  await game.ready();
  return game;
}

/// The player vehicle's movement contract: the taxi moves only under
/// direct throttle/steer input (issue #26 removed the dead autopilot and
/// pathfinding system, leaving this as the single movement path).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  TaxiGame freshGame() => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      );

  group('player vehicle movement', () {
    test('throttle alone drives the taxi forward', () async {
      final game = await mountGame(freshGame());
      final player = game.player;
      final startY = player.position.y;

      player.startAccelerating();
      for (var i = 0; i < 60; i++) {
        game.update(1 / 60);
      }

      // A second of throttle ramps to full speed and moves the taxi up.
      expect(player.isAccelerating, isTrue);
      expect(player.velocity.y, closeTo(-player.maxSpeed, 0.5));
      expect(player.position.y, lessThan(startY));
    });

    test('releasing the throttle brakes to a stop', () async {
      final game = await mountGame(freshGame());
      final player = game.player;

      player.startAccelerating();
      game.update(1 / 60);
      player.stopAccelerating();
      for (var i = 0; i < 60; i++) {
        game.update(1 / 60);
      }

      expect(player.velocity.y, 0);
    });

    test('steering moves the taxi laterally until the road clamp holds it',
        () async {
      final game = await mountGame(freshGame());
      final player = game.player;

      player.setSteering(1);
      game.update(1 / 60);
      expect(player.velocity.x, player.steeringSpeed);

      for (var i = 0; i < 60; i++) {
        game.update(1 / 60);
      }

      // Long enough to reach the clamp, not just drift towards it.
      final maxX = TaxiGame.roadCenterX +
          TaxiGame.roadWidth / 2 -
          player.vehicleSize.x / 2;
      expect(player.position.x, closeTo(maxX, 0.01));
    });

    test('reset restores the start position and clears inputs', () async {
      final game = await mountGame(freshGame());
      final player = game.player;
      final startX = player.position.x;
      final startY = player.position.y;

      player.startAccelerating();
      player.setSteering(-1);
      game.update(0.5);

      player.reset();

      expect(player.position.x, closeTo(startX, 0.001));
      expect(player.position.y, closeTo(startY, 0.001));
      expect(player.velocity, Vector2.zero());
      expect(player.isAccelerating, isFalse);
      expect(player.steeringInput, 0);
    });
  });
}
