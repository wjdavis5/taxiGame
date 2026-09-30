import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/material.dart';
import 'dart:math';

import '../taxi_game.dart';
import '../vehicle_sprites.dart';
import '../systems/collision_rules.dart';
import '../../models/traffic_pattern.dart';
import 'danger_indicator.dart';

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

  /// Result of this frame's danger telegraph check (issue #6).
  DangerAssessment _danger = const DangerAssessment.safe();
  bool get isTelegraphing => _danger.isDangerous;
  double get dangerTimeToImpact => _danger.timeToImpact;

  /// True once this vehicle has touched the player this episode — a
  /// scrape or a crash ruled in [PlayerVehicle.onCollisionStart]. A pass
  /// that follows a touch is not a *near* miss (issue #23): the contact
  /// already happened and named itself.
  bool contactedPlayer = false;

  /// Whether this vehicle's centre was ahead of the taxi's (smaller y)
  /// at the start of their **current contact episode**, re-decided at
  /// every touch by [PlayerVehicle.onCollisionStart] (issues #74, #80
  /// and #85). The pace cap paces a car the taxi rides behind, and
  /// where the touch *happened* — not where the bodies have drifted
  /// within the episode — is what decides that: a rear-ender that
  /// slides through a stopped cab must never start pacing it
  /// mid-grind. The decision is per episode, not per lifetime: the
  /// day the order genuinely swaps — the car falls back and rear-ends
  /// the taxi, or the taxi catches a past rear-ender — the next touch
  /// is judged on the geometry it starts from. And an episode spans
  /// the whole grind, containment stretch included — both hitboxes
  /// are solid, so Flame never splits a pass in two (#85).
  bool aheadAtContactStart = false;

  /// True once this vehicle has been judged for a close call at the pass
  /// (issue #23) — judged exactly once, however the ruling went, so no
  /// vehicle can pay twice.
  bool _nearMissJudged = false;

  late final DangerIndicator _dangerIndicator;

  /// The telegraph visual; exposed so tests (and callers) can read its
  /// visibility directly.
  DangerIndicator get dangerIndicator => _dangerIndicator;

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

    // Add hitbox. Tightened to 80% of the logical box (issue #6, in the
    // player's favour). Sized from the logical vehicle box only — never
    // from the sprite.
    //
    // Solid (issue #85): several traffic boxes clear the cab's scaled
    // one in both dimensions — a sedan's by a sliver, a bus's by 5 px
    // either side and 17.5 nose-to-tail — so part of any drive-through
    // parks the cab's whole hitbox inside this one, where no edges
    // cross. Flame's containment fallback keeps such an overlap as one
    // continuous collision only while the outer shape is solid; hollow
    // here, a rear-ender's pass split in two, the second half fired a
    // fresh onCollisionStart, and the per-episode ahead/behind ruling
    // (#80) — re-decided at that new touch, with the passer's centre
    // already past the cab's — read it "ahead" and pinned the cab to
    // the passer's speed (#74 reborn). Mirrors the taxi's own solid
    // hitbox (the outer shape of its cone touches) and the cones'.
    final hitbox = RectangleHitbox(
      size: vehicleSize * CollisionRules.trafficHitboxScale,
      position:
          vehicleSize * ((1 - CollisionRules.trafficHitboxScale) / 2),
    )..isSolid = true;
    add(hitbox);

    // Warning state for when the player closes on this vehicle dangerously.
    // Hidden until the telegraph check in [update] says otherwise.
    _dangerIndicator = DangerIndicator(vehicleSize: vehicleSize);
    _dangerIndicator.isVisible = false;
    add(_dangerIndicator);

    // Center anchor
    anchor = Anchor.center;

    // Set initial direction
    if (path.length > 1) {
      _updateVelocityTowardsWaypoint();
    }

    // The sprite is drawn facing up; oncoming vehicles (moving down the
    // screen) face the player. The flip is decided by the path's
    // direction of travel ([_travelsDownScreen]), never by the velocity
    // this frame: the spawner's straight paths begin at the spawn point
    // itself, so the first waypoint contributes a zero offset and the
    // initial velocity is zero (issue #72) — judging by it left every
    // spawned oncoming car tail-first, facing up-screen while it drove
    // down the road.
    if (_travelsDownScreen()) {
      angle = pi;
    }

    // The bundled sprites are top-down art facing up the screen (issue
    // #47) — the direction same-direction traffic travels, with the π flip
    // above turning oncoming cars to face the player — and each PNG's
    // canvas already carries its vehicle's logical proportions, so the
    // child is stretched straight over the vehicle box with no rotation of
    // its own. Because it is a separate child, its art never touches the
    // hitbox.
    final carSprite = sprite ??
        await game.loadSprite(VehicleSprites.trafficSpritePath(vehicleType));
    add(SpriteComponent(
      sprite: carSprite,
      size: vehicleSize,
      position: vehicleSize / 2,
      anchor: Anchor.center,
    ));
  }

  @override
  void render(Canvas canvas) {
    // Headlights (issue #24): on a night shift every car throws light
    // ahead of itself, so traffic reads as lit vehicles instead of shapes
    // in the dark. Additive glows at the front corners. In this local
    // space the front edge is always −y: same-direction traffic draws
    // unrotated, and oncoming traffic's π rotation already maps local −y
    // to its world-facing direction.
    final darkness = game.isMounted ? game.darkness : 0.0;
    if (darkness > 0.12) {
      final alpha = 0.55 * ((darkness - 0.12) / 0.88).clamp(0.0, 1.0);
      final glow = Paint()
        ..color = const Color(0xFFFFE9B0).withValues(alpha: alpha)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      for (final sideX in [size.x * 0.25, size.x * 0.75]) {
        canvas.drawCircle(Offset(sideX, 3), 4.5, glow);
      }
    }

    super.render(canvas);
  }

  @override
  void update(double dt) {
    super.update(dt);

    _updateDangerTelegraph();

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
      return;
    }

    _updateNearMissWatch();
  }

  void _updateVelocityTowardsWaypoint() {
    if (currentWaypointIndex >= path.length) return;

    final targetWaypoint = path[currentWaypointIndex];
    final offset = targetWaypoint - position;
    // A waypoint on top of the vehicle has no direction; stay put rather
    // than normalise a zero vector into NaN.
    if (offset.length < 0.001) {
      velocity = Vector2.zero();
      return;
    }
    velocity = offset.normalized() * speed;
  }

  /// Whether this vehicle's path carries it down the screen (toward
  /// positive y) — the oncoming direction, whose cars render flipped to
  /// face the player. Derived from the first waypoint whose offset from
  /// the current position clears the same epsilon
  /// [_updateVelocityTowardsWaypoint] guards with, so a path that
  /// begins on top of the vehicle — the spawner's straight paths do
  /// (issue #72) — still flips: the zero-offset waypoint is skipped,
  /// not mistaken for "no direction at all".
  bool _travelsDownScreen() {
    for (final waypoint in path) {
      final offset = waypoint - position;
      if (offset.length < 0.001) continue;
      return offset.normalized().y > 0;
    }
    return false;
  }

  /// Telegraphing (issue #6): warn while the player is on course to hit
  /// this vehicle within [CollisionRules.warningLeadTime]. The player is
  /// guaranteed to exist while the game is active — [TaxiGame.loadLevel]
  /// adds it before setting the flag.
  void _updateDangerTelegraph() {
    if (!game.isGameActive) {
      _danger = const DangerAssessment.safe();
    } else {
      final player = game.player;
      _danger = CollisionRules.assessDanger(
        playerPosition: player.position,
        playerVelocity: player.velocity,
        playerSize: player.vehicleSize,
        vehiclePosition: position,
        vehicleVelocity: velocity,
        vehicleSize: vehicleSize,
      );
    }

    _dangerIndicator.isVisible = _danger.isDangerous;
    if (_danger.isDangerous) {
      // Keep the warning centred on the car and upright on screen even
      // when the vehicle itself is flipped to face the player (oncoming).
      _dangerIndicator.position = vehicleSize / 2;
      _dangerIndicator.angle = -angle;
    }
  }

  /// Close-call watch (issue #23): the frame this vehicle first sits
  /// at-or-behind the player — the pass moment, since the taxi only ever
  /// travels up-screen so the relationship flips exactly once — is the
  /// one chance to judge the pass, and it is taken however it rules.
  /// Judged vehicles never re-arm, and ones the player touched are
  /// disqualified before geometry is consulted. The game owns the ruling
  /// ([NearMissRules.isCloseCall]) and the feedback.
  void _updateNearMissWatch() {
    if (_nearMissJudged || !game.isGameActive) return;
    if (game.player.position.y > position.y) return;

    _nearMissJudged = true;
    if (!contactedPlayer) {
      game.onNearMiss(this);
    }
  }
}
