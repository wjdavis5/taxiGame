import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Floating world-space note the passenger "says" when their dropoff has
/// to move (issue #28): the street is one-way, so a kerb the taxi drove
/// past can never be returned to — instead the destination relocates ahead
/// and the passenger says where to meet them. Plays at the kerb they
/// expected, in world space, so it scrolls away behind as the note reads —
/// the same beat the close-call award plays (issue #23): feedback that
/// names itself where it happened.
class PassengerNote extends TextComponent {
  PassengerNote({required Vector2 position})
      : super(
          text: 'Passenger: anywhere ahead is fine',
          anchor: Anchor.center,
          position: position.clone(),
          textRenderer: TextPaint(
            style: const TextStyle(
              color: Color(0xFF90CAF9),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        );

  /// A sentence needs longer on screen than an award does.
  static const double lifetime = 1.8;
  static const double riseSpeed = 30.0;

  double _age = 0;

  @override
  void update(double dt) {
    super.update(dt);

    _age += dt;
    y -= riseSpeed * dt;
    if (_age >= lifetime) removeFromParent();
  }
}
