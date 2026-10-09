import 'dart:math' as math;

import 'package:flame/components.dart';

/// Defines a traffic pattern for spawning vehicles
class TrafficPattern {
  final String name;
  final double spawnInterval; // Seconds between spawns
  final List<TrafficLaneConfig> lanes;

  const TrafficPattern({
    required this.name,
    required this.spawnInterval,
    required this.lanes,
  });

  /// Light traffic - easy difficulty
  static TrafficPattern get light => const TrafficPattern(
    name: 'light',
    spawnInterval: 4.0, // Increased from 3.0 - spawn less often
    lanes: [
      TrafficLaneConfig(
        laneX: 140, // Left lane - moved more to left
        speedRange: SpeedRange(min: 80, max: 120), // Slower traffic
        spawnProbability: 0.3, // Reduced from 0.5 - spawn less
        oncoming: true,
      ),
      TrafficLaneConfig(
        laneX: 260, // Right lane - moved more to right
        speedRange: SpeedRange(min: 80, max: 120), // Slower traffic
        spawnProbability: 0.2, // Even less in right lane to avoid blocking
        oncoming: false,
      ),
    ],
  );

  /// Medium traffic - moderate difficulty
  static TrafficPattern get medium => const TrafficPattern(
    name: 'medium',
    spawnInterval: 2.0,
    lanes: [
      TrafficLaneConfig(
        laneX: 160,
        speedRange: SpeedRange(min: 120, max: 180),
        spawnProbability: 0.7,
        oncoming: true,
      ),
      TrafficLaneConfig(
        laneX: 240,
        speedRange: SpeedRange(min: 120, max: 180),
        spawnProbability: 0.7,
        oncoming: false,
      ),
    ],
  );

  /// Heavy traffic - hard difficulty
  static TrafficPattern get heavy => const TrafficPattern(
    name: 'heavy',
    spawnInterval: 1.5,
    lanes: [
      TrafficLaneConfig(
        laneX: 160,
        speedRange: SpeedRange(min: 150, max: 220),
        spawnProbability: 0.85,
        oncoming: true,
      ),
      TrafficLaneConfig(
        laneX: 240,
        speedRange: SpeedRange(min: 150, max: 220),
        spawnProbability: 0.85,
        oncoming: false,
      ),
    ],
  );

  factory TrafficPattern.fromJson(Map<String, dynamic> json) {
    return TrafficPattern(
      name: json['name'] as String,
      spawnInterval: (json['spawnInterval'] as num).toDouble(),
      lanes: (json['lanes'] as List)
          .map((l) => TrafficLaneConfig.fromJson(l))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'spawnInterval': spawnInterval,
      'lanes': lanes.map((l) => l.toJson()).toList(),
    };
  }
}

/// Configuration for a single traffic lane
class TrafficLaneConfig {
  final double laneX; // X position of this lane
  final SpeedRange speedRange;
  final double spawnProbability; // 0.0 to 1.0

  /// Whether this lane's traffic drives toward the player (oncoming) or in
  /// the same direction (slower, to be overtaken).
  final bool oncoming;

  const TrafficLaneConfig({
    required this.laneX,
    required this.speedRange,
    required this.spawnProbability,
    required this.oncoming,
  });

  factory TrafficLaneConfig.fromJson(Map<String, dynamic> json) {
    final laneX = (json['laneX'] as num).toDouble();
    return TrafficLaneConfig(
      laneX: laneX,
      speedRange: SpeedRange.fromJson(json['speedRange']),
      spawnProbability: (json['spawnProbability'] as num).toDouble(),
      // Default: left half of the road (and the center line) is oncoming,
      // the right lane flows with the player.
      oncoming: json['oncoming'] as bool? ?? laneX <= 200,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'laneX': laneX,
      'speedRange': speedRange.toJson(),
      'spawnProbability': spawnProbability,
      'oncoming': oncoming,
    };
  }
}

/// Drives one spawn wave's per-lane probability rolls (issue #216).
///
/// The live spawner and the tuning simulator must consume the RNG in the
/// same order: the same seed has to draw the same road the player drives,
/// or the harness stops measuring what ships. That order lives here, in
/// the one place both call — one `nextDouble()` per lane, in lane order,
/// *before* any gate that can skip the lane's spawn, so a skipped lane
/// still spends its roll. [onRolled] runs immediately for a lane whose
/// roll passed, keeping the speed and type draws inside it interleaved
/// with the next lane's probability roll, exactly the live spawner's
/// order.
void forEachRolledLane(
  math.Random random,
  List<TrafficLaneConfig> lanes,
  void Function(TrafficLaneConfig lane) onRolled,
) {
  for (final lane in lanes) {
    if (random.nextDouble() <= lane.spawnProbability) {
      onRolled(lane);
    }
  }
}

/// Speed range for traffic vehicles
class SpeedRange {
  final double min;
  final double max;

  const SpeedRange({required this.min, required this.max});

  factory SpeedRange.fromJson(Map<String, dynamic> json) {
    return SpeedRange(
      min: (json['min'] as num).toDouble(),
      max: (json['max'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'min': min,
      'max': max,
    };
  }
}

/// Types of traffic vehicles
enum TrafficVehicleType {
  sedan,
  truck,
  sportsCar,
  suv,
  bus,
}

/// Extension to get properties for each vehicle type
extension TrafficVehicleTypeExtension on TrafficVehicleType {
  /// The vehicle's name as the player reads it in a sentence — 'sports
  /// car', not the enum identifier 'sportsCar' (issue #151). The crash
  /// headline, the scrape marker, and the contact explanations
  /// interpolate this string into player-facing text; passing [name]
  /// there leaked "You hit the sportsCar flat out." and "Scraped a
  /// suv!" onto the CRASH! panel and the road.
  String get displayName {
    switch (this) {
      case TrafficVehicleType.sedan:
        return 'sedan';
      case TrafficVehicleType.truck:
        return 'truck';
      case TrafficVehicleType.sportsCar:
        return 'sports car';
      case TrafficVehicleType.suv:
        return 'SUV';
      case TrafficVehicleType.bus:
        return 'bus';
    }
  }

  Vector2 get size {
    switch (this) {
      case TrafficVehicleType.sedan:
        return Vector2(40, 60);
      case TrafficVehicleType.truck:
        return Vector2(45, 80);
      case TrafficVehicleType.sportsCar:
        return Vector2(38, 55);
      case TrafficVehicleType.suv:
        return Vector2(42, 70);
      case TrafficVehicleType.bus:
        return Vector2(50, 100);
    }
  }

  double get speedMultiplier {
    switch (this) {
      case TrafficVehicleType.sedan:
        return 1.0;
      case TrafficVehicleType.truck:
        return 0.7;
      case TrafficVehicleType.sportsCar:
        return 1.3;
      case TrafficVehicleType.suv:
        return 0.9;
      case TrafficVehicleType.bus:
        return 0.6;
    }
  }
}
