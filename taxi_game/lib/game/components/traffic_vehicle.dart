import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/material.dart';
import 'dart:math';

import '../taxi_game.dart';
import '../../models/traffic_pattern.dart';

/// AI-controlled traffic vehicle that follows a path
class TrafficVehicle extends PositionComponent
    with HasGameRef<TaxiGame>, CollisionCallbacks {

  final TrafficVehicleType vehicleType;
  final double baseSpeed;
  final List<Vector2> path;

  int currentWaypointIndex = 0;
  Vector2 velocity = Vector2.zero();
  bool shouldRemove = false;

  // Visual properties based on vehicle type
  late final Vector2 vehicleSize;
  late final Color vehicleColor;
  late final double speed;

  TrafficVehicle({
    required Vector2 position,
    required this.vehicleType,
    required this.baseSpeed,
    required this.path,
  }) : super(position: position) {
    vehicleSize = vehicleType.size;
    speed = baseSpeed * vehicleType.speedMultiplier;
    vehicleColor = _getColorForType(vehicleType);
  }

  /// Factory method to create a random traffic vehicle
  factory TrafficVehicle.random({
    required Vector2 position,
    required double baseSpeed,
    required List<Vector2> path,
    Random? random,
  }) {
    final rng = random ?? Random();
    final types = TrafficVehicleType.values;
    final randomType = types[rng.nextInt(types.length)];

    return TrafficVehicle(
      position: position,
      vehicleType: randomType,
      baseSpeed: baseSpeed,
      path: path,
    );
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Set size
    size = vehicleSize;

    // Add hitbox (slightly smaller than visual for fairness)
    final hitbox = RectangleHitbox(
      size: vehicleSize * 0.85,
      position: vehicleSize * 0.075,
    );
    add(hitbox);

    // Center anchor
    anchor = Anchor.center;

    // Set initial direction
    if (path.length > 1) {
      _updateVelocityTowardsWaypoint();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Move along path
    if (path.isNotEmpty && currentWaypointIndex < path.length) {
      final targetWaypoint = path[currentWaypointIndex];
      final distanceToWaypoint = position.distanceTo(targetWaypoint);

      // Check if we've reached current waypoint
      if (distanceToWaypoint < 10.0) {
        currentWaypointIndex++;
        if (currentWaypointIndex < path.length) {
          _updateVelocityTowardsWaypoint();
        }
      }

      // Update position
      position += velocity * dt;
    }

    // Check if vehicle is off screen (below player view)
    if (position.y > gameRef.camera.viewfinder.position.y + 1000) {
      shouldRemove = true;
      removeFromParent();
    }
  }

  void _updateVelocityTowardsWaypoint() {
    if (currentWaypointIndex >= path.length) return;

    final targetWaypoint = path[currentWaypointIndex];
    final direction = (targetWaypoint - position).normalized();
    velocity = direction * speed;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Draw vehicle body
    final paint = Paint()
      ..color = vehicleColor
      ..style = PaintingStyle.fill;

    final rect = Rect.fromLTWH(0, 0, vehicleSize.x, vehicleSize.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.drawRRect(rrect, paint);

    // Draw windows (darker)
    final windowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.fill;

    // Front window
    canvas.drawRect(
      Rect.fromLTWH(4, 4, vehicleSize.x - 8, vehicleSize.y * 0.2),
      windowPaint,
    );

    // Rear window (only if not a bus)
    if (vehicleType != TrafficVehicleType.bus) {
      canvas.drawRect(
        Rect.fromLTWH(4, vehicleSize.y - (vehicleSize.y * 0.2) - 4,
                     vehicleSize.x - 8, vehicleSize.y * 0.2),
        windowPaint,
      );
    }

    // Draw wheels
    final wheelPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final wheelRadius = 3.0;

    // Left wheels
    canvas.drawCircle(Offset(6, 8), wheelRadius, wheelPaint);
    canvas.drawCircle(Offset(6, vehicleSize.y - 8), wheelRadius, wheelPaint);

    // Right wheels
    canvas.drawCircle(Offset(vehicleSize.x - 6, 8), wheelRadius, wheelPaint);
    canvas.drawCircle(Offset(vehicleSize.x - 6, vehicleSize.y - 8), wheelRadius, wheelPaint);

    // Special markings for different vehicle types
    if (vehicleType == TrafficVehicleType.bus) {
      // Draw multiple windows for bus
      final windowHeight = vehicleSize.y * 0.15;
      for (var i = 0; i < 3; i++) {
        canvas.drawRect(
          Rect.fromLTWH(
            4,
            vehicleSize.y * 0.25 + (i * windowHeight * 1.5),
            vehicleSize.x - 8,
            windowHeight,
          ),
          windowPaint,
        );
      }
    }
  }

  static Color _getColorForType(TrafficVehicleType type) {
    switch (type) {
      case TrafficVehicleType.sedan:
        return Colors.blue;
      case TrafficVehicleType.truck:
        return Colors.brown;
      case TrafficVehicleType.sportsCar:
        return Colors.red;
      case TrafficVehicleType.suv:
        return Colors.green.shade700;
      case TrafficVehicleType.bus:
        return Colors.orange;
    }
  }
}
