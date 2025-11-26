import 'package:flutter/material.dart';
import 'package:flame/components.dart';
import '../../models/traffic_pattern.dart';

/// Represents a game level with all its data
class GameLevel {
  final int levelNumber;
  final String name;
  final List<Vector2> pickupPoints;
  final List<Vector2> dropoffPoints;
  final int coinReward;
  final LevelDifficulty difficulty;
  final TrafficPattern trafficPattern;

  GameLevel({
    required this.levelNumber,
    required this.name,
    required this.pickupPoints,
    required this.dropoffPoints,
    required this.coinReward,
    required this.difficulty,
    TrafficPattern? trafficPattern,
  }) : trafficPattern = trafficPattern ?? TrafficPattern.light;

  /// Creates a simple test level for initial development
  factory GameLevel.createTestLevel() {
    return GameLevel(
      levelNumber: 1,
      name: 'Test Level',
      pickupPoints: [Vector2(120, -300)], // Left side
      dropoffPoints: [Vector2(280, -800)], // Right side, further up
      coinReward: 50,
      difficulty: LevelDifficulty.easy,
      trafficPattern: TrafficPattern.light,
    );
  }

  /// Load level from JSON data
  factory GameLevel.fromJson(Map<String, dynamic> json) {
    return GameLevel(
      levelNumber: json['levelNumber'] as int,
      name: json['name'] as String,
      pickupPoints: (json['pickupPoints'] as List)
          .map((p) => Vector2(p[0] as double, p[1] as double))
          .toList(),
      dropoffPoints: (json['dropoffPoints'] as List)
          .map((p) => Vector2(p[0] as double, p[1] as double))
          .toList(),
      coinReward: json['coinReward'] as int,
      difficulty: LevelDifficulty.values.byName(json['difficulty'] as String),
      trafficPattern: json['trafficPattern'] != null
          ? TrafficPattern.fromJson(json['trafficPattern'])
          : TrafficPattern.light,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'levelNumber': levelNumber,
      'name': name,
      'pickupPoints': pickupPoints.map((p) => [p.x, p.y]).toList(),
      'dropoffPoints': dropoffPoints.map((p) => [p.x, p.y]).toList(),
      'coinReward': coinReward,
      'difficulty': difficulty.name,
      'trafficPattern': trafficPattern.toJson(),
    };
  }
}

enum LevelDifficulty {
  easy,
  medium,
  hard,
  expert,
}
