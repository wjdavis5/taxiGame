import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../taxi_game.dart';
import 'player_vehicle.dart';
import '../../models/fare_type.dart';
import '../../models/passenger_data.dart';

/// Visual marker for passenger pickup location
class PickupZone extends CircleComponent with HasGameReference<TaxiGame>, CollisionCallbacks {
  final PassengerData passenger;
  final VoidCallback onPickup;

  bool _isPickedUp = false;
  double _pulseAnimation = 0.0;

  static const double baseRadius = 30.0;
  static const double detectionRadius = 40.0;

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
    radius = baseRadius + (math.sin(_pulseAnimation) * 5.0);
  }

  @override
  void render(Canvas canvas) {
    if (_isPickedUp) return;

    // The marker wears the fare kind's colour (issue #25): gold for a
    // VIP, purple for a long-haul, orange for an awkward crossing, and
    // the classic green for the everyday ride.
    final color = passenger.fareType.markerColor;

    // Skip CircleComponent's default paint and draw centered on the
    // component (local origin is the top-left corner, not the center).
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);

    // Draw outer glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, radius + 10, glowPaint);

    // Draw main circle
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, radius, paint);

    // Draw border
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(Offset.zero, radius, borderPaint);

    // Draw passenger icon (simple person shape)
    _drawPassengerIcon(canvas);

    canvas.restore();
  }

  void _drawPassengerIcon(Canvas canvas) {
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Head
    canvas.drawCircle(const Offset(0, -5), 6, iconPaint);

    // Body
    final bodyPath = Path()
      ..moveTo(0, 2)
      ..lineTo(-8, 15)
      ..lineTo(-4, 15)
      ..lineTo(0, 8)
      ..lineTo(4, 15)
      ..lineTo(8, 15)
      ..close();
    canvas.drawPath(bodyPath, iconPaint);

    // A crown marks the VIP (issue #25) — the highest-paying fare on the
    // street should be readable at a glance, not just by colour.
    if (passenger.fareType == FareType.vip) {
      final crownPath = Path()
        ..moveTo(-8, -9)
        ..lineTo(-8, -19)
        ..lineTo(-4, -14)
        ..lineTo(0, -21)
        ..lineTo(4, -14)
        ..lineTo(8, -19)
        ..lineTo(8, -9)
        ..close();
      canvas.drawPath(crownPath, iconPaint);
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);

    if (_isPickedUp) return;

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
