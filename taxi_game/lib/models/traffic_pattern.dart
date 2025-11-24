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
  static TrafficPattern get light => TrafficPattern(
    name: 'light',
    spawnInterval: 3.0,
    lanes: [
      TrafficLaneConfig(
        laneX: 160,
        speedRange: SpeedRange(min: 100, max: 150),
        spawnProbability: 0.5,
      ),
      TrafficLaneConfig(
        laneX: 240,
        speedRange: SpeedRange(min: 100, max: 150),
        spawnProbability: 0.5,
      ),
    ],
  );

  /// Medium traffic - moderate difficulty
  static TrafficPattern get medium => TrafficPattern(
    name: 'medium',
    spawnInterval: 2.0,
    lanes: [
      TrafficLaneConfig(
        laneX: 160,
        speedRange: SpeedRange(min: 120, max: 180),
        spawnProbability: 0.7,
      ),
      TrafficLaneConfig(
        laneX: 240,
        speedRange: SpeedRange(min: 120, max: 180),
        spawnProbability: 0.7,
      ),
    ],
  );

  /// Heavy traffic - hard difficulty
  static TrafficPattern get heavy => TrafficPattern(
    name: 'heavy',
    spawnInterval: 1.5,
    lanes: [
      TrafficLaneConfig(
        laneX: 160,
        speedRange: SpeedRange(min: 150, max: 220),
        spawnProbability: 0.85,
      ),
      TrafficLaneConfig(
        laneX: 240,
        speedRange: SpeedRange(min: 150, max: 220),
        spawnProbability: 0.85,
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

  const TrafficLaneConfig({
    required this.laneX,
    required this.speedRange,
    required this.spawnProbability,
  });

  factory TrafficLaneConfig.fromJson(Map<String, dynamic> json) {
    return TrafficLaneConfig(
      laneX: (json['laneX'] as num).toDouble(),
      speedRange: SpeedRange.fromJson(json['speedRange']),
      spawnProbability: (json['spawnProbability'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'laneX': laneX,
      'speedRange': speedRange.toJson(),
      'spawnProbability': spawnProbability,
    };
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
