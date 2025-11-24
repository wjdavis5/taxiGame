import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/material.dart';

import '../taxi_game.dart';
import 'traffic_vehicle.dart';
import '../systems/pathfinding_system.dart';

/// Player-controlled taxi vehicle
class PlayerVehicle extends PositionComponent
    with HasGameReference<TaxiGame>, CollisionCallbacks {

  static const double maxSpeed = 300.0;
  static const double acceleration = 400.0;
  static const double deceleration = 600.0;

  Vector2 velocity = Vector2.zero();
  bool isAccelerating = false;
  bool hasPassenger = false;

  // Pathfinding
  final PathfindingSystem pathfinding = PathfindingSystem();
  bool useAutopilot = false; // Toggle between manual and auto navigation
  
  // Visual properties
  final Color vehicleColor = Colors.yellow;
  final Vector2 vehicleSize = Vector2(40, 60);
  
  PlayerVehicle({required Vector2 position}) : super(position: position);
  
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // Set size
    size = vehicleSize;
    
    // Add hitbox (slightly smaller than visual for fairness)
    final hitbox = RectangleHitbox(
      size: vehicleSize * 0.9,
      position: vehicleSize * 0.05,
    );
    add(hitbox);
    
    // Center anchor
    anchor = Anchor.center;
  }
  
  @override
  void update(double dt) {
    super.update(dt);

    // Check if using autopilot
    if (useAutopilot && pathfinding.isNavigating) {
      _updateAutopilotMovement(dt);
    } else {
      _updateManualMovement(dt);
    }

    // Update position
    position += velocity * dt;

    // Keep within bounds (horizontally)
    if (position.x < vehicleSize.x / 2) {
      position.x = vehicleSize.x / 2;
    } else if (position.x > game.size.x - vehicleSize.x / 2) {
      position.x = game.size.x - vehicleSize.x / 2;
    }
  }

  void _updateManualMovement(double dt) {
    // Manual control - original behavior
    if (isAccelerating) {
      velocity.y = -maxSpeed; // Move upward (forward in game)
    } else {
      // Decelerate quickly
      if (velocity.y < 0) {
        velocity.y += deceleration * dt;
        if (velocity.y > 0) {
          velocity.y = 0;
        }
      }
    }
  }

  void _updateAutopilotMovement(double dt) {
    // Get direction from pathfinding
    final direction = pathfinding.getNavigationDirection(position);

    if (direction != null) {
      // Get speed multiplier (for slowing down near waypoints)
      final speedMult = pathfinding.getSpeedMultiplier(position);

      // Base speed - faster when holding, slower when not
      final baseSpeed = isAccelerating ? maxSpeed : maxSpeed * 0.5;

      // Apply speed multiplier and direction
      velocity = direction * baseSpeed * speedMult;
    } else {
      // No navigation - stop
      velocity = Vector2.zero();
    }
  }

  /// Navigate to a destination using pathfinding
  void navigateTo(Vector2 destination) {
    pathfinding.setDestination(position, destination);
    useAutopilot = true;
  }

  /// Stop autopilot and return to manual control
  void stopNavigation() {
    pathfinding.clear();
    useAutopilot = false;
    velocity = Vector2.zero();
  }
  
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // Draw vehicle body (simple rectangle)
    final paint = Paint()
      ..color = vehicleColor
      ..style = PaintingStyle.fill;
    
    final rect = Rect.fromLTWH(0, 0, vehicleSize.x, vehicleSize.y);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(rrect, paint);
    
    // Draw windows (darker rectangles)
    final windowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    
    // Front window
    canvas.drawRect(
      Rect.fromLTWH(5, 5, vehicleSize.x - 10, 15),
      windowPaint,
    );
    
    // Rear window
    canvas.drawRect(
      Rect.fromLTWH(5, vehicleSize.y - 20, vehicleSize.x - 10, 15),
      windowPaint,
    );
    
    // Draw wheels (simple circles)
    final wheelPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    
    // Left wheels
    canvas.drawCircle(Offset(8, 10), 4, wheelPaint);
    canvas.drawCircle(Offset(8, vehicleSize.y - 10), 4, wheelPaint);
    
    // Right wheels
    canvas.drawCircle(Offset(vehicleSize.x - 8, 10), 4, wheelPaint);
    canvas.drawCircle(Offset(vehicleSize.x - 8, vehicleSize.y - 10), 4, wheelPaint);
  }
  
  void startAccelerating() {
    isAccelerating = true;
  }
  
  void stopAccelerating() {
    isAccelerating = false;
  }
  
  void reset() {
    position = Vector2(200, 600);
    velocity = Vector2.zero();
    isAccelerating = false;
    hasPassenger = false;
    stopNavigation();
  }
  
  @override
  void onCollision(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollision(intersectionPoints, other);

    // Handle collisions with traffic vehicles
    if (other is TrafficVehicle) {
      // Collision occurred - trigger game over
      game.onLevelFailed();
    }
  }
}
