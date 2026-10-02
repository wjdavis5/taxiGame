import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../systems/collision_rules.dart';

/// Floating world-space label naming what the taxi just scraped
/// (issue #6 contact legibility). Rises and shrinks, then removes itself.
/// The [vehicleKind] is the player-facing display name with its a/an
/// chosen by sound (issue #151): 'Scraped an SUV!', never
/// 'Scraped a suv!'.
class ScrapeMarker extends TextComponent {
  ScrapeMarker({
    required Vector2 position,
    required String vehicleKind,
  }) : super(
          text:
              'Scraped ${CollisionRules.articleFor(vehicleKind)} $vehicleKind!',
          anchor: Anchor.center,
          position: position,
          textRenderer: TextPaint(
            style: const TextStyle(
              color: Color(0xFFFFC93C),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        );

  static const double lifetime = 0.8;
  static const double riseSpeed = 40.0;

  double _age = 0;

  @override
  void update(double dt) {
    super.update(dt);

    _age += dt;
    final t = (_age / lifetime).clamp(0.0, 1.0);
    y -= riseSpeed * dt;
    final s = 1.0 - 0.35 * t;
    scale.setValues(s, s);
    if (_age >= lifetime) removeFromParent();
  }
}
