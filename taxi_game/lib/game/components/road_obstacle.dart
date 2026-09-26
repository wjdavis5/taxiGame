import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// A construction cone (issue #24): the physical body of a work-zone cone
/// line. Cones are soft — brushing one sheds speed and shoves the taxi
/// away, it never costs a life — but a line of them across a lane is a
/// wall the taxi must go around, not through.
///
/// Cones are children of their road chunk, so chunk culling (issue #11)
/// removes them for free; nothing here ever needs its own bookkeeping.
class RoadObstacle extends PositionComponent {
  /// Set after the player's first touch on this cone, so a held grind
  /// against the line penalises once per cone — the same one-ruling
  /// principle [TrafficVehicle.contactedPlayer] uses.
  bool contactedPlayer = false;

  /// Logical footprint. The hitbox is thinner than the drawn cone so the
  /// art can overlap a grazing pass without the physics feeling it.
  static final Vector2 coneSize = Vector2(16, 16);

  RoadObstacle({required Vector2 position})
      : super(
          position: position,
          size: coneSize.clone(),
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Solid: a cone is small enough to sit *entirely inside* a vehicle's
    // hitbox, and Flame's polygon test only crosses edges — full
    // containment needs one side solid or the touch never registers.
    add(RectangleHitbox(
      size: coneSize * 0.7,
      position: coneSize * ((1 - 0.7) / 2),
    )..isSolid = true);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Base: dark orange square
    canvas.drawRect(
      Rect.fromLTWH(2, 2, size.x - 4, size.y - 4),
      Paint()..color = const Color(0xFFB85C00),
    );

    // Cone body: a bright orange triangle
    final body = Path()
      ..moveTo(size.x / 2, 1)
      ..lineTo(size.x - 2, size.y - 2)
      ..lineTo(2, size.y - 2)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFFF7A1A));

    // Reflective band
    canvas.drawRect(
      Rect.fromLTWH(4.5, size.y * 0.55, size.x - 9, 2.5),
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );

    // Subtle shadow for depth on the road
    canvas.drawOval(
      Rect.fromLTWH(0, size.y - 3, size.x, 3),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill,
    );
  }
}
