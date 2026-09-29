import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Floating world-space announcement of a spent life (issue #14's
/// feedback gap): a non-fatal endless crash freezes the world for a beat
/// and hollows a heart on the HUD, and neither says what happened in
/// words. This pop does — it appears over the taxi in the crash
/// palette's red, rides the crash stall frozen (the world's freeze is
/// the freeze-frame it belongs to), then rises and fades out as the
/// shift resumes, the same beat [CloseCallPop] and the scrape marker
/// play.
class LifeLostPop extends TextComponent {
  LifeLostPop({
    required Vector2 position,
    required int livesLeft,
  }) : super(
          text: livesLeft > 0 ? '-1 LIFE \u00b7 $livesLeft LEFT' : '-1 LIFE',
          anchor: Anchor.center,
          position: position.clone(),
          textRenderer: TextPaint(
            style: const TextStyle(
              color: Color(0xFFFF5252),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        );

  /// A sentence-length announcement: a little longer than an award pop,
  /// shorter than the passenger's relocated-kerb note.
  static const double lifetime = 1.2;
  static const double riseSpeed = 38.0;

  double _age = 0;

  @override
  void update(double dt) {
    super.update(dt);

    _age += dt;
    y -= riseSpeed * dt;
    if (_age >= lifetime) removeFromParent();
  }
}
