import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../taxi_game.dart';
import 'player_vehicle.dart';
import '../../models/passenger_data.dart';

/// Visual marker for passenger dropoff location
class DropoffZone extends CircleComponent with HasGameRef<TaxiGame>, CollisionCallbacks {
  final PassengerData passenger;
  final VoidCallback onDropoff;

  bool _isActive = false; // Only active after passenger is picked up
  bool _isCompleted = false;
  double _pulseAnimation = 0.0;

  static const double baseRadius = 30.0;
  static const double detectionRadius = 40.0;

  DropoffZone({
    required Vector2 position,
    required this.passenger,
    required this.onDropoff,
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

    // Check if passenger has been picked up
    if (!_isActive && passenger.isPickedUp) {
      _isActive = true;
    }

    if (!_isActive || _isCompleted) return;

    // Pulse animation
    _pulseAnimation += dt * 2.0;
    radius = baseRadius + (math.sin(_pulseAnimation) * 5.0);
  }

  @override
  void render(Canvas canvas) {
    if (_isCompleted) return;

    super.render(canvas);

    final color = _isActive ? Colors.blue : Colors.grey;
    final opacity = _isActive ? 0.6 : 0.3;

    // Draw outer glow
    final glowPaint = Paint()
      ..color = color.withOpacity(opacity * 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, radius + 10, glowPaint);

    // Draw main circle
    final paint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, radius, paint);

    // Draw border
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(Offset.zero, radius, borderPaint);

    // Draw flag icon
    _drawFlagIcon(canvas, color);
  }

  void _drawFlagIcon(Canvas canvas, Color color) {
    final iconPaint = Paint()
      ..color = _isActive ? Colors.white : Colors.grey.shade400
      ..style = PaintingStyle.fill;

    // Flag pole
    canvas.drawRect(const Rect.fromLTWH(-1, -10, 2, 20), iconPaint);

    // Flag
    final flagPath = Path()
      ..moveTo(0, -10)
      ..lineTo(12, -5)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(flagPath, iconPaint);
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);

    if (!_isActive || _isCompleted) return;

    // Check if player entered the zone with passenger
    if (other is PlayerVehicle && passenger.isPickedUp) {
      _dropoffPassenger();
    }
  }

  void _dropoffPassenger() {
    if (_isCompleted) return;

    _isCompleted = true;
    passenger.isDelivered = true;

    // Call the dropoff callback
    onDropoff();

    // Remove this zone from the game
    removeFromParent();
  }
}
