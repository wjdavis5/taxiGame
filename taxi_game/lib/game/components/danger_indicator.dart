import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../systems/collision_rules.dart';

/// Visible warning state drawn on a traffic vehicle the player is closing
/// on dangerously (issue #6 telegraphing).
///
/// Added as a child of the [TrafficVehicle]. The vehicle centres the
/// indicator on itself and counter-rotates it each update, so this
/// component only owns its look and pulse animation.
class DangerIndicator extends PositionComponent with HasVisibility {
  DangerIndicator({required Vector2 vehicleSize})
      : outlineSize = vehicleSize * CollisionRules.trafficHitboxScale,
        super(anchor: Anchor.center);

  /// Matches the vehicle's hitbox so the warning outlines exactly the box
  /// that would do the hitting.
  final Vector2 outlineSize;

  final Paint _outlinePaint = Paint()
    ..color = Colors.red
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;

  static final TextPaint _exclamationPaint = TextPaint(
    style: const TextStyle(
      color: Colors.red,
      fontSize: 22,
      fontWeight: FontWeight.w900,
    ),
  );

  late final RectangleComponent _outline;
  late final TextComponent _exclamation;
  double _phase = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    _outline = RectangleComponent(
      size: outlineSize.clone(),
      anchor: Anchor.center,
      paint: _outlinePaint,
    );
    add(_outline);

    // Floating above the roofline, in this component's (counter-rotated)
    // frame, so it always appears above the vehicle on screen.
    _exclamation = TextComponent(
      text: '!',
      textRenderer: _exclamationPaint,
      anchor: Anchor.center,
      position: Vector2(0, -(outlineSize.y / 2 + 14)),
    );
    add(_exclamation);
  }

  @override
  void update(double dt) {
    super.update(dt);

    _phase = (_phase + dt * 5.0) % (2 * math.pi);
    final pulse = (math.sin(_phase) + 1) / 2; // 0..1

    // The exclamation mark throbs and the outline breathes, so the warning
    // reads as "imminent" even in peripheral vision.
    final scale = 0.9 + 0.25 * pulse;
    _exclamation.scale.setValues(scale, scale);
    _outlinePaint.strokeWidth = 2.0 + 1.5 * pulse;
  }
}
