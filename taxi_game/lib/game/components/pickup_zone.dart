import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../taxi_game.dart';
import 'player_vehicle.dart';
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

    // Add collision detection
    add(CircleHitbox(
      radius: detectionRadius,
      anchor: Anchor.center,
    ));
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

    super.render(canvas);

    // Draw outer glow
    final glowPaint = Paint()
      ..color = Colors.green.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, radius + 10, glowPaint);

    // Draw main circle
    final paint = Paint()
      ..color = Colors.green.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, radius, paint);

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(Offset.zero, radius, borderPaint);

    // Draw passenger icon (simple person shape)
    _drawPassengerIcon(canvas);
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
