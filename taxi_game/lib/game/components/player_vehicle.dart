import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/collisions.dart';

import '../../data/vehicle_catalog.dart';
import '../taxi_game.dart';
import '../vehicle_sprites.dart';
import '../systems/collision_rules.dart';
import 'road_obstacle.dart';
import 'traffic_vehicle.dart';

/// Player-controlled taxi vehicle
class PlayerVehicle extends PositionComponent
    with HasGameReference<TaxiGame>, CollisionCallbacks {

  /// Universal braking. Deliberately not part of the per-car stats (issue
  /// #9): every car must be able to get out of a bad overtake the same way,
  /// so the four catalog axes stay the whole story.
  static const double deceleration = 600.0;

  /// How much harder a deliberate brake bites than letting go (issue
  /// #29): a full drag-down applies 1x this on top of the release rate —
  /// twice the deceleration — while easing off the stick coasts at the
  /// ordinary release rate. Part of the same universal braking rule.
  static const double brakeBoost = 1.0;

  Vector2 velocity = Vector2.zero();
  bool isAccelerating = false;

  /// Analog throttle from the virtual stick (issue #29): 1 is full
  /// throttle, negative brakes (harder the further the drag), 0 rests.
  /// Nonzero, it wins over the keyboard's binary pedal; the two inputs
  /// otherwise stay independent.
  double throttleInput = 0;

  bool hasPassenger = false;
  double steeringInput = 0; // -1 (left) to 1 (right)

  /// Save-data id of the vehicle being driven; picks the rendered sprite.
  final String vehicleId;

  /// Handling profile in play: resolved from the vehicle catalog by
  /// [vehicleId], so the car equipped in the garage is the car that is
  /// actually driven (issue #9). Tests may inject a profile directly.
  final VehicleStats stats;

  /// Forward top speed, throttle ramp, and full-lock lateral speed, from
  /// [stats]. Per-car since issue #9; before that every car handled alike.
  double get maxSpeed => stats.topSpeed;
  double get acceleration => stats.acceleration;
  double get steeringSpeed => stats.steeringSpeed;

  /// Logical footprint of the vehicle, from [stats] — each car has its own
  /// body since issue #9. The hitbox is derived from this, never from the
  /// sprite, so swapping the art cannot change collision behaviour.
  Vector2 get vehicleSize => Vector2(stats.width, stats.height);

  /// Pre-loaded sprite to render instead of the bundled one (tests inject a
  /// fake here). When null the sprite is loaded from the bundled PNG.
  final Sprite? sprite;

  final Vector2 startPosition;

  PlayerVehicle({
    required this.startPosition,
    String? vehicleId,
    this.sprite,
    VehicleStats? stats,
  })  : vehicleId = vehicleId ?? VehicleSprites.defaultVehicleId,
        stats = stats ?? VehicleCatalog.statsFor(vehicleId),
        super(position: startPosition.clone());

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Set size
    size = vehicleSize;

    // Add hitbox. Tightened to 75% of the logical box (issue #6): grazing
    // contact the art only overlaps must not register. Sized from the
    // logical vehicle box only — never from the sprite — and since issue #9
    // the logical box is per-car, so a bigger body is a bigger target.
    //
    // Solid (issue #24): the taxi must feel small static obstacles —
    // construction cones — even when they sit entirely inside its box,
    // where no polygon edges cross. Flame's containment fallback trusts
    // the outer shape's isSolid, and the taxi is the outer shape in every
    // cone touch.
    final hitbox = RectangleHitbox(
      size: vehicleSize * CollisionRules.playerHitboxScale,
      position: vehicleSize *
          ((1 - CollisionRules.playerHitboxScale) / 2),
    )..isSolid = true;
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

    // Keep the taxi on the road. In an endless run (issue #24) the road
    // has whatever width exists at the taxi's distance, so a taper
    // carries the clamp in with the kerb; the classic level road is fixed.
    final halfWidth = vehicleSize.x / 2;
    final env = isMounted ? game.environment : null;
    final double minX;
    final double maxX;
    if (env != null) {
      // True distance into the run: world y folds back toward the origin
      // as the run deepens (issue #30), so the raw reading loses a whole
      // fold per boundary and would clamp the taxi to the wrong kerb.
      final road =
          env.roadAt(math.max(0.0, game.worldShift - position.y));
      minX = road.leftX + halfWidth;
      maxX = road.rightX - halfWidth;
    } else {
      minX = TaxiGame.roadCenterX - TaxiGame.roadWidth / 2 + halfWidth;
      maxX = TaxiGame.roadCenterX + TaxiGame.roadWidth / 2 - halfWidth;
    }
    position.x = position.x.clamp(minX, maxX);
  }

  /// Throttle ramps speed up, releasing or braking slows it, and
  /// steering sets the lateral velocity directly. This is the only
  /// movement path — the taxi is always under player control. The
  /// lateral half of the equation is scaled by the road's grip (issue
  /// #24): rain cuts full lock's bite, dry street leaves the stats
  /// untouched.
  ///
  /// The throttle is analog since the virtual stick (issue #29): a
  /// partial drag-up ramps proportionally slower toward the same
  /// per-car top speed, and a drag-down brakes up to
  /// [deceleration] * (1 + [brakeBoost]). There is no reverse. With no
  /// stick input the keyboard's binary pedal takes over unchanged.
  void _updateMovement(double dt) {
    final throttle =
        throttleInput != 0 ? throttleInput : (isAccelerating ? 1.0 : 0.0);
    if (throttle > 0) {
      // Ramp up gradually (spec: ~0.5s from stop to full speed at full
      // throttle), scaled by how far the stick is pushed.
      velocity.y = (velocity.y - acceleration * throttle * dt)
          .clamp(-maxSpeed, 0.0);
    } else {
      // Decelerate quickly; a deliberate drag-down bites harder.
      final braking = deceleration * (1.0 - throttle);
      if (velocity.y < 0) {
        velocity.y = math.min(0.0, velocity.y + braking * dt);
      }
    }

    // Left/right steering, on whatever grip the street offers.
    final grip = isMounted ? game.gripMultiplier : 1.0;
    velocity.x = steeringInput * steeringSpeed * grip;
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

  /// Sets the stick's analog throttle (issue #29), clamped to -1..1.
  void setThrottle(double input) {
    throttleInput = input.clamp(-1.0, 1.0);
  }

  void reset() {
    position = startPosition.clone();
    velocity = Vector2.zero();
    isAccelerating = false;
    throttleInput = 0;
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

    // Construction cones (issue #24) are soft obstacles: they cost speed,
    // never a life. One ruling per cone — a held grind against the line
    // does not keep re-punishing.
    if (other is RoadObstacle) {
      if (other.contactedPlayer || !game.isGameActive) return;
      other.contactedPlayer = true;

      final contactPoint = intersectionPoints.isEmpty
          ? (position + other.position) / 2
          : intersectionPoints.first;
      final axis = CollisionRules.impactAxis(position, other.position);
      final report = CollisionRules.buildReport(
        severity: ContactSeverity.scrape,
        vehicleKind: 'traffic cone',
        playerVelocity: velocity,
        playerPosition: position,
        trafficVelocity: Vector2.zero(),
        trafficPosition: other.position,
        contactPoint: contactPoint,
      );
      velocity = velocity * CollisionRules.scrapeSpeedKeep;
      position.add(axis * CollisionRules.scrapePushback);
      game.onScrape(report);
      return;
    }

    // Only traffic is lethal/relevant; zones handle themselves.
    if (other is! TrafficVehicle) return;
    // No rulings while the level is already over or frozen.
    if (!game.isGameActive) return;

    // This episode had its touch: whatever the severity, this vehicle is
    // out of the running for a close call at the pass (issue #23).
    other.contactedPlayer = true;

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
        // The game routes the crash: endless runs spend a life and
        // resume (issue #14), the tutorial ladder fails the level.
        game.onCrash(report);
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
