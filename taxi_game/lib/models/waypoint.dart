import 'package:flame/components.dart';

/// Represents a waypoint in a navigation path
class Waypoint {
  final Vector2 position;
  final WaypointType type;
  final String? label;

  const Waypoint({
    required this.position,
    this.type = WaypointType.normal,
    this.label,
  });

  /// Distance to another waypoint
  double distanceTo(Waypoint other) {
    return position.distanceTo(other.position);
  }

  /// Distance to a position
  double distanceToPosition(Vector2 pos) {
    return position.distanceTo(pos);
  }

  /// Create from JSON
  factory Waypoint.fromJson(Map<String, dynamic> json) {
    return Waypoint(
      position: Vector2(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
      type: WaypointType.values.byName(json['type'] as String? ?? 'normal'),
      label: json['label'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'x': position.x,
      'y': position.y,
      'type': type.name,
      if (label != null) 'label': label,
    };
  }

  @override
  String toString() => 'Waypoint(${position.x}, ${position.y}, $type)';
}

/// Type of waypoint
enum WaypointType {
  normal, // Regular waypoint
  pickup, // Pickup location
  dropoff, // Dropoff location
  slowDown, // Slow down point (e.g., before turn)
  stop, // Full stop point
}

/// A path consisting of multiple waypoints
class NavigationPath {
  final List<Waypoint> waypoints;
  int currentIndex = 0;

  NavigationPath({required this.waypoints});

  /// Get current waypoint
  Waypoint? get currentWaypoint {
    if (currentIndex < waypoints.length) {
      return waypoints[currentIndex];
    }
    return null;
  }

  /// Get next waypoint
  Waypoint? get nextWaypoint {
    final next = currentIndex + 1;
    if (next < waypoints.length) {
      return waypoints[next];
    }
    return null;
  }

  /// Move to next waypoint
  bool advance() {
    if (currentIndex < waypoints.length - 1) {
      currentIndex++;
      return true;
    }
    return false;
  }

  /// Check if path is complete
  bool get isComplete => currentIndex >= waypoints.length;

  /// Reset to start
  void reset() {
    currentIndex = 0;
  }

  /// Get progress (0.0 to 1.0)
  double get progress {
    if (waypoints.isEmpty) return 1.0;
    return currentIndex / waypoints.length;
  }

  /// Create a simple straight path between two points
  factory NavigationPath.straight(Vector2 start, Vector2 end, {int segments = 5}) {
    final waypoints = <Waypoint>[];
    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final x = start.x + (end.x - start.x) * t;
      final y = start.y + (end.y - start.y) * t;
      waypoints.add(Waypoint(position: Vector2(x, y)));
    }
    return NavigationPath(waypoints: waypoints);
  }

  /// Create from JSON
  factory NavigationPath.fromJson(Map<String, dynamic> json) {
    return NavigationPath(
      waypoints: (json['waypoints'] as List)
          .map((w) => Waypoint.fromJson(w))
          .toList(),
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'waypoints': waypoints.map((w) => w.toJson()).toList(),
    };
  }
}
