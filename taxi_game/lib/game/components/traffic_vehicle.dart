import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'dart:math';

import '../taxi_game.dart';
import '../vehicle_sprites.dart';
import '../../models/traffic_pattern.dart';

/// AI-controlled traffic vehicle that follows a path
class TrafficVehicle extends PositionComponent
    with HasGameReference<TaxiGame>, CollisionCallbacks {

  final TrafficVehicleType vehicleType;
  final double baseSpeed;
  final List<Vector2> path;

  int currentWaypointIndex = 0;
  Vector2 velocity = Vector2.zero();
  bool shouldRemove = false;

  /// Logical footprint of the vehicle. The hitbox is derived from this, never
  /// from the sprite, so swapping the art cannot change collision behaviour.
  late final Vector2 vehicleSize;
  late final double speed;

  /// Pre-loaded sprite to render instead of the bundled one (tests inject a
  /// fake here). When null the sprite is loaded from the bundled PNG.
  final Sprite? sprite;

  TrafficVehicle({
    required Vector2 position,
    required this.vehicleType,
    required this.baseSpeed,
    required this.path,
    this.sprite,
  }) : super(position: position) {
    vehicleSize = vehicleType.size;
    speed = baseSpeed * vehicleType.speedMultiplier;
  }

  /// Factory method to create a random traffic vehicle
  factory TrafficVehicle.random({
    required Vector2 position,
    required double baseSpeed,
    required List<Vector2> path,
    Random? random,
  }) {
    final rng = random ?? Random();
    const types = TrafficVehicleType.values;
    final randomType = types[rng.nextInt(types.length)];

    return TrafficVehicle(
      position: position,
      vehicleType: randomType,
      baseSpeed: baseSpeed,
      path: path,
    );
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Set size
    size = vehicleSize;

    // Add hitbox (slightly smaller than visual for fairness). Sized from the
    // logical vehicle box only — never from the sprite.
    final hitbox = RectangleHitbox(
      size: vehicleSize * 0.85,
      position: vehicleSize * 0.075,
    );
    add(hitbox);

    // Center anchor
    anchor = Anchor.center;

    // Set initial direction
    if (path.length > 1) {
      _updateVelocityTowardsWaypoint();
    }

    // The sprite is drawn facing up; oncoming vehicles (moving down the
    // screen) face the player.
    if (velocity.y > 0) {
      angle = pi;
    }

    // The bundled sprites are side-view art facing right while the game is
    // top-down and traffic travels along the road, so the child is rotated a
    // quarter turn and stretched over the logical vehicle box. Because it is
    // a separate child, its art and rotation never touch the hitbox.
    final carSprite = sprite ??
        await game.loadSprite(VehicleSprites.trafficSpritePath(vehicleType));
    add(SpriteComponent(
      sprite: carSprite,
      size: Vector2(vehicleSize.y, vehicleSize.x),
      position: vehicleSize / 2,
      angle: -pi / 2,
      anchor: Anchor.center,
    ));
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Move along path
    if (path.isNotEmpty && currentWaypointIndex < path.length) {
      final targetWaypoint = path[currentWaypointIndex];
      final distanceToWaypoint = position.distanceTo(targetWaypoint);

      // Check if we've reached current waypoint
      if (distanceToWaypoint < 10.0) {
        currentWaypointIndex++;
        if (currentWaypointIndex < path.length) {
          _updateVelocityTowardsWaypoint();
        }
      }

      // Update position
      position += velocity * dt;
    } else {
      // Path exhausted - despawn instead of idling forever at the path end
      shouldRemove = true;
      removeFromParent();
      return;
    }

    // Check if vehicle is off screen (below player view)
    if (position.y > game.camera.viewfinder.position.y + 1000) {
      shouldRemove = true;
      removeFromParent();
    }
  }

  void _updateVelocityTowardsWaypoint() {
    if (currentWaypointIndex >= path.length) return;

    final targetWaypoint = path[currentWaypointIndex];
    final direction = (targetWaypoint - position).normalized();
    velocity = direction * speed;
  }
}
