import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../taxi_game.dart';
import 'world_one_shot.dart';

/// Floating world-space note the passenger "says" when their dropoff has
/// to move (issue #28): the street is one-way, so a kerb the taxi drove
/// past can never be returned to — instead the destination relocates ahead
/// and the passenger says where to meet them. Plays at the kerb they
/// expected, in world space, so it scrolls away behind as the note reads —
/// the same beat the close-call award plays (issue #23): feedback that
/// names itself where it happened.
///
/// The whole sentence stays on the phone (issue #50): dropoffs always sit
/// at a kerb, near the road's edges, and a note centred there lost half
/// the line off the screen — "Passenger: anywh…". The camera is locked
/// horizontally (vertical-only follow on [TaxiGame.roadCenterX]) and the
/// world fold moves y only, so world x is screen x and clamping the
/// component's x here is exact for the note's whole life.
class PassengerNote extends TextComponent with WorldOneShot {
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
        ) {
    // The constructor's super call has already laid the text out (Flame's
    // TextComponent measures in updateBounds), so the width this clamps
    // with is the width the player sees. The bounds are ordered against
    // the road's centre because the line can measure wider than the
    // viewport: a naive clamp(lo, hi) throws when lo passes hi, and
    // pinning both bounds to the centre instead reads the over-wide line
    // centred on the road — clipped evenly at both edges, never lost off
    // one side.
    const roadWidth = 2 * TaxiGame.roadCenterX;
    final half = width / 2;
    x = x.clamp(
      math.min(edgeMargin + half, TaxiGame.roadCenterX),
      math.max(roadWidth - edgeMargin - half, TaxiGame.roadCenterX),
    );
  }

  /// How far the sentence keeps clear of the screen's edges, in px.
  static const double edgeMargin = 8.0;

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
