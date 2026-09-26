import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
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

/// Vehicles load their sprite asynchronously inside [onLoad] and only then
/// queue the sprite child, so keep settling the tree until the child shows up.
Future<void> settleSprite(PositionComponent vehicle, TaxiGame game) async {
  for (var i = 0; i < 500; i++) {
    await game.ready();
    if (vehicle.children.whereType<SpriteComponent>().isNotEmpty) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('vehicle never materialized its sprite child');
}

SpriteComponent spriteOf(PositionComponent vehicle) =>
    vehicle.children.whereType<SpriteComponent>().single;

RectangleHitbox hitboxOf(PositionComponent vehicle) =>
    vehicle.children.whereType<RectangleHitbox>().single;

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

  group('PlayerVehicle', () {
    test('renders its sprite instead of canvas primitives', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));
      final player = game.player;
      await settleSprite(player, game);

      final spriteComponent = spriteOf(player);
      expect(spriteComponent.sprite, isNotNull);
      // taxi_yellow.png decodes to a 33x14 image.
      expect(spriteComponent.sprite!.image.width, 33);
      expect(spriteComponent.sprite!.image.height, 14);
      // The side-view art faces right; a quarter turn points it up the
      // screen, the direction the taxi drives.
      expect(spriteComponent.angle, closeTo(-math.pi / 2, 1e-9));
    });

    test('hitbox stays tied to the logical box, not the sprite', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));
      final player = game.player;
      await settleSprite(player, game);

      // 75% of the logical box (issue #6 tightened it in the player's
      // favour), still centred.
      expect(hitboxOf(player).size, Vector2(40, 60) * 0.75);
      expect(
        hitboxOf(player).position,
        Vector2(40, 60) * (1 - 0.75) / 2,
      );
      // The sprite art is 33x14 — nothing like the 40x60 hitbox footprint —
      // proving collision geometry is independent of the art.
      expect(spriteOf(player).sprite!.srcSize, Vector2(33, 14));
    });

    test('selectedVehicle drives which sprite renders', () async {
      gameState.unlockVehicle('sedan_blue', 0);
      gameState.selectVehicle('sedan_blue');

      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));
      await settleSprite(game.player, game);

      expect(gameState.selectedVehicle, 'sedan_blue');
      expect(game.player.vehicleId, 'sedan_blue');

      // sedan_blue.png decodes to a 29x13 image — a different sprite than
      // the default taxi (33x14), so what appears on screen changed.
      final rendered = spriteOf(game.player).sprite!;
      expect(rendered.image.width, 29);
      expect(rendered.image.height, 13);
    });

    test('an unknown vehicle id falls back to the default taxi', () async {
      gameState.unlockVehicle('sport_taxi', 0);
      gameState.selectVehicle('sport_taxi');

      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));
      await settleSprite(game.player, game);

      // The id no longer maps to a shipped sprite; rendering must not break.
      final rendered = spriteOf(game.player).sprite!;
      expect(rendered.image.width, 33);
      expect(rendered.image.height, 14);
    });
  });

  group('TrafficVehicle', () {
    test('renders a sprite with the hitbox decoupled from the art', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));

      final bus = TrafficVehicle(
        position: Vector2(260, 0),
        vehicleType: TrafficVehicleType.bus,
        baseSpeed: 100,
        // Drives down the screen: oncoming traffic.
        path: [Vector2(260, 100), Vector2(260, 200)],
      );
      game.world.add(bus);
      await settleSprite(bus, game);

      final spriteComponent = spriteOf(bus);
      expect(spriteComponent.sprite, isNotNull);
      expect(spriteComponent.angle, closeTo(-math.pi / 2, 1e-9));
      // Oncoming traffic still faces the player...
      expect(bus.angle, math.pi);
      // ...while the hitbox keeps the logical footprint (80% of 50x100,
      // tightened in the player's favour by issue #6), independent of the
      // sprite art.
      expect(hitboxOf(bus).size, Vector2(50, 100) * 0.80);
    });

    test('same-direction traffic faces up the screen', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));

      final car = TrafficVehicle(
        position: Vector2(260, 0),
        vehicleType: TrafficVehicleType.sedan,
        baseSpeed: 100,
        // Drives up the screen, same direction as the player.
        path: [Vector2(260, -100), Vector2(260, -200)],
      );
      game.world.add(car);
      await settleSprite(car, game);

      expect(car.angle, 0);
      expect(spriteOf(car).sprite, isNotNull);
    });
  });
}
