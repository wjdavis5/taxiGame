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

  // Cone paints, shared by every cone (issue #256): the old renderer
  // allocated four paints per cone per frame for colours that never
  // change, and nothing mutates these after construction.
  static final Paint _basePaint = Paint()..color = const Color(0xFFB85C00);
  static final Paint _bodyPaint = Paint()..color = const Color(0xFFFF7A1A);
  static final Paint _bandPaint =
      Paint()..color = Colors.white.withValues(alpha: 0.9);
  static final Paint _shadowPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.25)
    ..style = PaintingStyle.fill;

  /// The body triangle, built once per cone (issue #256): its geometry is
  /// a pure function of [size], fixed at construction.
  late final Path _bodyPath = Path()
    ..moveTo(size.x / 2, 1)
    ..lineTo(size.x - 2, size.y - 2)
    ..lineTo(2, size.y - 2)
    ..close();

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
      _basePaint,
    );

    // Cone body: a bright orange triangle (the path is cached, issue #256)
    canvas.drawPath(_bodyPath, _bodyPaint);

    // Reflective band
    canvas.drawRect(
      Rect.fromLTWH(4.5, size.y * 0.55, size.x - 9, 2.5),
      _bandPaint,
    );

    // Subtle shadow for depth on the road
    canvas.drawOval(
      Rect.fromLTWH(0, size.y - 3, size.x, 3),
      _shadowPaint,
    );
  }
}
