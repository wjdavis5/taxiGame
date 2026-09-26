import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/collisions.dart';

import '../taxi_game.dart';
import '../vehicle_sprites.dart';
import 'traffic_vehicle.dart';
import '../systems/pathfinding_system.dart';

/// Player-controlled taxi vehicle
class PlayerVehicle extends PositionComponent
    with HasGameReference<TaxiGame>, CollisionCallbacks {

  static const double maxSpeed = 150.0; // Reduced from 300 - much slower
  static const double acceleration = 400.0;
  static const double deceleration = 600.0;
  static const double steeringSpeed = 300.0; // Increased from 200 - faster steering

  Vector2 velocity = Vector2.zero();
  bool isAccelerating = false;
  bool hasPassenger = false;
  double steeringInput = 0; // -1 (left) to 1 (right)

  // Pathfinding
  final PathfindingSystem pathfinding = PathfindingSystem();
  bool useAutopilot = false; // Toggle between manual and auto navigation

  /// Save-data id of the vehicle being driven; picks the rendered sprite.
  final String vehicleId;

  /// Logical footprint of the vehicle. The hitbox is derived from this, never
  /// from the sprite, so swapping the art cannot change collision behaviour.
  final Vector2 vehicleSize = Vector2(40, 60);

  /// Pre-loaded sprite to render instead of the bundled one (tests inject a
  /// fake here). When null the sprite is loaded from the bundled PNG.
  final Sprite? sprite;

  final Vector2 startPosition;

  PlayerVehicle({
    required this.startPosition,
    String? vehicleId,
    this.sprite,
  }) : vehicleId = vehicleId ?? VehicleSprites.defaultVehicleId,
       super(position: startPosition.clone());

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Set size
    size = vehicleSize;

    // Add hitbox (slightly smaller than visual for fairness). Sized from the
    // logical vehicle box only — never from the sprite.
    final hitbox = RectangleHitbox(
      size: vehicleSize * 0.9,
      position: vehicleSize * 0.05,
    );
    add(hitbox);

    // Center anchor
    anchor = Anchor.center;

    // The bundled sprites are side-view art facing right while the game is
    // top-down and the taxi travels up the screen, so the child is rotated a
    // quarter turn. It is stretched over the logical vehicle box; because it
    // is a separate child, its rotation and art never touch the hitbox.
    final carSprite = sprite ??
        await game.loadSprite(VehicleSprites.playerSpritePath(vehicleId));
    add(SpriteComponent(
      sprite: carSprite,
      size: Vector2(vehicleSize.y, vehicleSize.x),
      position: vehicleSize / 2,
      angle: -math.pi / 2,
      anchor: Anchor.center,
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Check if using autopilot
    if (useAutopilot && pathfinding.isNavigating) {
      _updateAutopilotMovement(dt);
    } else {
      _updateManualMovement(dt);
    }

    // Update position
    position += velocity * dt;

    // Keep the taxi on the road (world x 100..300)
    final minX = TaxiGame.roadCenterX - TaxiGame.roadWidth / 2 + vehicleSize.x / 2;
    final maxX = TaxiGame.roadCenterX + TaxiGame.roadWidth / 2 - vehicleSize.x / 2;
    position.x = position.x.clamp(minX, maxX);
  }

  void _updateManualMovement(double dt) {
    // Forward/backward movement
    if (isAccelerating) {
      // Ramp up gradually (spec: ~0.5s from stop to full speed)
      velocity.y = (velocity.y - acceleration * dt).clamp(-maxSpeed, 0.0);
    } else {
      // Decelerate quickly
      if (velocity.y < 0) {
        velocity.y += deceleration * dt;
        if (velocity.y > 0) {
          velocity.y = 0;
        }
      }
    }

    // Left/right steering
    velocity.x = steeringInput * steeringSpeed;
  }

  void _updateAutopilotMovement(double dt) {
    // Get direction from pathfinding
    final direction = pathfinding.getNavigationDirection(position);

    if (direction != null) {
      // Get speed multiplier (for slowing down near waypoints)
      final speedMult = pathfinding.getSpeedMultiplier(position);

      // Base speed - faster when holding, slower when not
      final baseSpeed = isAccelerating ? maxSpeed : maxSpeed * 0.5;

      // Apply speed multiplier and direction
      velocity = direction * baseSpeed * speedMult;
    } else {
      // No navigation - stop
      velocity = Vector2.zero();
    }
  }

  /// Navigate to a destination using pathfinding
  void navigateTo(Vector2 destination) {
    pathfinding.setDestination(position, destination);
    useAutopilot = true;
  }

  /// Stop autopilot and return to manual control
  void stopNavigation() {
    pathfinding.clear();
    useAutopilot = false;
    velocity = Vector2.zero();
  }

  void startAccelerating() {
    isAccelerating = true;
  }

  void stopAccelerating() {
    isAccelerating = false;
  }

  void setSteering(double input) {
    steeringInput = input.clamp(-1.0, 1.0);
  }

  void reset() {
    position = startPosition.clone();
    velocity = Vector2.zero();
    isAccelerating = false;
    hasPassenger = false;
    steeringInput = 0;
    stopNavigation();
  }

  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);

    // Handle collisions with traffic vehicles
    if (other is TrafficVehicle) {
      // Collision occurred - trigger game over
      game.onLevelFailed();
    }
  }
}
