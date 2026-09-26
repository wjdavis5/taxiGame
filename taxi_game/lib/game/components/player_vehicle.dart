import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/collisions.dart';

import '../taxi_game.dart';
import '../vehicle_sprites.dart';
import '../systems/collision_rules.dart';
import 'traffic_vehicle.dart';

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

    // Add hitbox. Tightened to 75% of the logical box (issue #6): grazing
    // contact the art only overlaps must not register. Sized from the
    // logical vehicle box only — never from the sprite.
    final hitbox = RectangleHitbox(
      size: vehicleSize * CollisionRules.playerHitboxScale,
      position: vehicleSize *
          ((1 - CollisionRules.playerHitboxScale) / 2),
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

    _updateMovement(dt);

    // Update position
    position += velocity * dt;

    // Keep the taxi on the road (world x 100..300)
    final minX = TaxiGame.roadCenterX - TaxiGame.roadWidth / 2 + vehicleSize.x / 2;
    final maxX = TaxiGame.roadCenterX + TaxiGame.roadWidth / 2 - vehicleSize.x / 2;
    position.x = position.x.clamp(minX, maxX);
  }

  /// Throttle ramps speed up, releasing it brakes; steering sets the
  /// lateral velocity directly. This is the only movement path — the taxi
  /// is always under player control.
  void _updateMovement(double dt) {
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
  }

  /// Judged on contact start (one ruling per touch episode) instead of
  /// every overlapping tick, so a scrape applies once and a sustained
  /// grind does not re-fire the ruling every frame.
  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);

    // Only traffic is lethal/relevant; zones handle themselves.
    if (other is! TrafficVehicle) return;
    // No rulings while the level is already over or frozen.
    if (!game.isGameActive) return;

    final contactPoint = intersectionPoints.isEmpty
        ? (position + other.position) / 2
        : intersectionPoints.first;

    // Fairness rule (issue #6): judge the touch by how fast the two
    // vehicles close along the impact axis, not by the mere fact of
    // overlap. Brushing a car at low speed must not end the run.
    final axis = CollisionRules.impactAxis(position, other.position);
    final approachSpeed = CollisionRules.approachSpeed(
      playerVelocity: velocity,
      trafficVelocity: other.velocity,
      impactAxis: axis,
    );
    final severity = CollisionRules.severityFor(approachSpeed);
    final report = CollisionRules.buildReport(
      severity: severity,
      vehicleKind: other.vehicleType.name,
      playerVelocity: velocity,
      playerPosition: position,
      trafficVelocity: other.velocity,
      trafficPosition: other.position,
      contactPoint: contactPoint,
    );

    switch (severity) {
      case ContactSeverity.crash:
        game.onLevelFailed(report);
      case ContactSeverity.scrape:
        _applyScrape(axis, report);
    }
  }

  /// Low-speed glancing contact: keep the run alive, shed most of the
  /// speed, push the taxi out of overlap so the same touch does not grind,
  /// and let the game surface feedback naming what was hit.
  void _applyScrape(Vector2 axis, CrashReport report) {
    velocity = velocity * CollisionRules.scrapeSpeedKeep;
    position.add(axis * CollisionRules.scrapePushback);
    game.onScrape(report);
  }
}
