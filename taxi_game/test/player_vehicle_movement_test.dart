import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/player_vehicle.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// Mounts [game] headlessly (the pattern flame_test uses) so component
/// `onLoad` hooks run, then returns it.

/// Advances game time by [seconds], in clamped frames (issue #36): no
/// single frame may consume more than [TaxiGame.maxUpdateDelta], so
/// fast-forwarding a shift means many small frames, never one giant
/// one — exactly the invariant the live game now runs under.
void advanceGameTime(TaxiGame game, double seconds) {
  var remaining = seconds;
  while (remaining > 0) {
    final step = math.min(remaining, TaxiGame.maxUpdateDelta);
    game.update(step);
    remaining -= step;
  }
}

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
      advanceGameTime(game, 0.5);

      player.reset();

      expect(player.position.x, closeTo(startX, 0.001));
      expect(player.position.y, closeTo(startY, 0.001));
      expect(player.velocity, Vector2.zero());
      expect(player.isAccelerating, isFalse);
      expect(player.steeringInput, 0);
    });

    test('a brake straight after throttle squeals again — no zero frame '
        'needed (issue #131)', () async {
      // A real headless AudioService: every platform call it makes is
      // swallowed under flutter test (no audio plugin exists), and the
      // attempts are what it records — audio_service_test's pattern.
      final audio = AudioService();
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        audio: audio,
      ));
      final player = game.player;

      // Full throttle from rest: the default cab tops out at 150 px/s,
      // clear of the 120 px/s squeal threshold. Half a second of ramp
      // is the whole drive — level 1 fails a cab that outruns its fare
      // for much longer than the second the tests here stay on the
      // road, so this test keeps its total driving under that.
      player.setThrottle(1);
      advanceGameTime(game, 0.5);
      expect(-player.velocity.y, greaterThan(PlayerVehicle.brakeSoundMinSpeed));

      // First brake from speed: one squeal, at its falling edge.
      player.setThrottle(-1);
      game.update(1 / 60);
      expect(audio.attemptedPlays['brake'], 1);

      // The issue's flip: brake straight back to full throttle, with no
      // zero-throttle frame in between. On a real stick this is the
      // normal crossing — the thumb is off-centre while steering, and
      // VirtualStick.resolve outputs zero only inside its dead zone — so
      // the pedals change sign without ever resting at zero. Four
      // throttle frames put the 130 px/s the brake left back at the top
      // speed; the latch clears on the first of them.
      player.setThrottle(1);
      advanceGameTime(game, 4 / 60);

      // The second brake squeals again: the throttle re-armed the edge.
      player.setThrottle(-1);
      game.update(1 / 60);
      expect(audio.attemptedPlays['brake'], 2,
          reason: 'the brake-to-throttle flip must re-arm the squeal — '
              'before issue #131 the latch stayed set until a '
              'zero-throttle frame cleared it, and every later brake was '
              'silent until the thumb lifted');

      // And the re-armed edge fires once per crossing, not per frame
      // (the issue #4 half of the contract): a light drag holds the cab
      // above the threshold across the frames after the squeal, so the
      // count staying put is the latch at work, not the speed floor.
      player.setThrottle(1);
      advanceGameTime(game, 4 / 60);
      player.setThrottle(-0.05);
      game.update(1 / 60); // the squeal frame — still at speed
      expect(audio.attemptedPlays['brake'], 3);
      game.update(1 / 60); // held, still above the threshold
      game.update(1 / 60);
      expect(audio.attemptedPlays['brake'], 3,
          reason: 'holding the brake squeals once, at its falling edge');
    });
  });
}
