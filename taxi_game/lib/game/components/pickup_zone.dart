import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../taxi_game.dart';
import 'fare_glyph.dart';
import 'player_vehicle.dart';
import '../../models/passenger_data.dart';

/// Visual marker for passenger pickup location
class PickupZone extends CircleComponent with HasGameReference<TaxiGame>, CollisionCallbacks {
  final PassengerData passenger;
  final VoidCallback onPickup;

  bool _isPickedUp = false;
  double _pulseAnimation = 0.0;

  // The pulse breathes this private brush radius, never the component's
  // own `radius`: CircleComponent's radius setter rewrites `size`, and
  // under anchor.center every resize slides the top-left local origin
  // that the fixed-offset children hang from — the detection
  // CircleHitbox at (baseRadius, baseRadius), the special-fare label at
  // (baseRadius, 2·baseRadius + 18) — while render() keeps the drawn
  // marker dead on the kerb, so the detection circle drifted up to 5 px
  // per axis off the marker the player aims at and the label wobbled
  // with it (issue #143). The component stays baseRadius square for
  // life; only the brush shrinks and grows.
  double _drawRadius = baseRadius;

  static const double baseRadius = 30.0;
  static const double detectionRadius = 40.0;

  // The marker's paints, cached as fields (issue #256): every colour
  // below is the fare kind's, constant for this zone's life, and the old
  // renderer rebuilt three circle paints and two glyph paints per frame.
  late final Paint _glowPaint = Paint()
    ..color = passenger.fareType.markerColor.withValues(alpha: 0.3)
    ..style = PaintingStyle.fill;
  late final Paint _bodyPaint = Paint()
    ..color = passenger.fareType.markerColor.withValues(alpha: 0.6)
    ..style = PaintingStyle.fill;
  late final Paint _borderPaint = Paint()
    ..color = passenger.fareType.markerColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;
  late final Paint _glyphInk = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  late final Paint _glyphRim = Paint()
    ..color = Colors.black.withValues(alpha: 0.85)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeJoin = StrokeJoin.round;

  PickupZone({
    required Vector2 position,
    required this.passenger,
    required this.onPickup,
  }) : super(
          position: position,
          radius: baseRadius,
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Add collision detection, centered on the visible circle
    add(CircleHitbox(
      radius: detectionRadius,
      position: Vector2.all(baseRadius),
      anchor: Anchor.center,
    ));

    // The fare kind is legible from driving distance (issue #25): a
    // special fare names itself under its marker, in its own colour, so
    // the player can weigh the deal and steer past it without ever
    // touching the kerb. Standard fares stay unlabelled — no marker
    // should shout about an ordinary ride.
    if (!passenger.fareType.isStandard) {
      add(TextComponent(
        text: passenger.fareType.zoneLabel,
        anchor: Anchor.center,
        position: Vector2(baseRadius, 2 * baseRadius + 18),
        textRenderer: TextPaint(
          style: TextStyle(
            color: passenger.fareType.markerColor,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (_isPickedUp) return;

    // Pulse animation
    _pulseAnimation += dt * 2.0;
    _drawRadius = baseRadius + (math.sin(_pulseAnimation) * 5.0);
  }

  @override
  void render(Canvas canvas) {
    if (_isPickedUp) return;

    // The marker wears the fare kind's colour (issue #25): gold for a
    // VIP, purple for a long-haul, orange for an awkward crossing, and
    // the classic green for the everyday ride. Colour is secondary
    // emphasis now (issue #35): the glyph below is what sorts the kinds
    // when hue cannot. The kind's colours are baked into the cached
    // paints (issue #256).
    //
    // Skip CircleComponent's default paint and draw centered on the
    // component (local origin is the top-left corner, not the center).
    // Every circle below reads _drawRadius, the pulsing brush — size
    // never moves, so this translate lands on the same kerb all shift.
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);

    // Draw outer glow
    canvas.drawCircle(Offset.zero, _drawRadius + 10, _glowPaint);

    // Draw main circle
    canvas.drawCircle(Offset.zero, _drawRadius, _bodyPaint);

    // Draw border
    canvas.drawCircle(Offset.zero, _drawRadius, _borderPaint);

    // Draw the fare kind's glyph (issue #35).
    _drawKindGlyph(canvas);

    canvas.restore();
  }

  /// The kind glyph (issue #35): a ring for the everyday ride, a crown in
  /// a ring for the VIP, a double chevron up for the long-haul, crossed
  /// arrows for the awkward crossing. Solid white over a dark rim, so the
  /// four kinds sort in greyscale against any of the marker fills.
  void _drawKindGlyph(Canvas canvas) {
    paintFareGlyph(
      canvas,
      passenger.fareType,
      ink: _glyphInk,
      rim: _glyphRim,
    );
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);

    if (_isPickedUp) return;

    // A settled run boards nobody (issue #71): the world keeps ticking
    // under the end-of-run panel, and a rolling cab must not take on
    // work the ending already closed.
    if (game.isShiftOver) return;

    // Check if player entered the zone
    if (other is PlayerVehicle) {
      _pickupPassenger();
    }
  }

  void _pickupPassenger() {
    if (_isPickedUp) return;

    _isPickedUp = true;
    passenger.isPickedUp = true;

    // Call the pickup callback
    onPickup();

    // Remove this zone from the game
    removeFromParent();
  }
}
