import 'package:flame/components.dart';
import '../../models/waypoint.dart';

/// Handles pathfinding and navigation for the player vehicle
class PathfindingSystem {
  NavigationPath? currentPath;
  Vector2? targetDestination;

  // Navigation parameters
  static const double waypointReachedDistance = 15.0; // How close to waypoint to consider "reached"
  static const double slowDownDistance = 50.0; // Distance to start slowing down

  /// Set a new destination and create path
  void setDestination(Vector2 from, Vector2 to, {int pathSegments = 10}) {
    targetDestination = to;

    // For now, create a simple straight path
    // In the future, this could use A* or other algorithms
    currentPath = NavigationPath.straight(from, to, segments: pathSegments);
  }

  /// Update navigation and return desired direction
  /// Returns null if no active navigation
  Vector2? getNavigationDirection(Vector2 currentPosition) {
    if (currentPath == null || currentPath!.isComplete) {
      return null;
    }

    final waypoint = currentPath!.currentWaypoint;
    if (waypoint == null) {
      return null;
    }

    // Check if we've reached the current waypoint
    final distance = currentPosition.distanceTo(waypoint.position);
    if (distance < waypointReachedDistance) {
      // Move to next waypoint
      if (!currentPath!.advance()) {
        // Path complete
        return null;
      }
    }

    // Get direction to current waypoint
    final nextWaypoint = currentPath!.currentWaypoint;
    if (nextWaypoint == null) {
      return null;
    }

    final direction = (nextWaypoint.position - currentPosition).normalized();
    return direction;
  }

  /// Get speed multiplier based on distance to waypoint
  /// Returns 1.0 for normal speed, lower values for slowing down
  double getSpeedMultiplier(Vector2 currentPosition) {
    if (currentPath == null || currentPath!.isComplete) {
      return 1.0;
    }

    final waypoint = currentPath!.currentWaypoint;
    if (waypoint == null) {
      return 1.0;
    }

    // Slow down as we approach waypoints
    final distance = currentPosition.distanceTo(waypoint.position);

    if (waypoint.type == WaypointType.slowDown || waypoint.type == WaypointType.stop) {
      // Gradual slowdown
      if (distance < slowDownDistance) {
        return (distance / slowDownDistance).clamp(0.3, 1.0);
      }
    }

    return 1.0;
  }

  /// Check if we've reached the final destination
  bool hasReachedDestination(Vector2 currentPosition) {
    if (targetDestination == null) {
      return false;
    }

    final distance = currentPosition.distanceTo(targetDestination!);
    return distance < waypointReachedDistance;
  }

  /// Get distance to destination
  double? getDistanceToDestination(Vector2 currentPosition) {
    if (targetDestination == null) {
      return null;
    }

    return currentPosition.distanceTo(targetDestination!);
  }

  /// Clear current navigation
  void clear() {
    currentPath = null;
    targetDestination = null;
  }

  /// Check if currently navigating
  bool get isNavigating => currentPath != null && !currentPath!.isComplete;

  /// Get progress towards destination (0.0 to 1.0)
  double get progress => currentPath?.progress ?? 0.0;
}
