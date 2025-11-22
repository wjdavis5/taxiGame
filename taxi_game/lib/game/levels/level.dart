import 'package:flutter/material.dart';

/// Represents a game level with all its data
class GameLevel {
  final int levelNumber;
  final String name;
  final List<Vector2> pickupPoints;
  final List<Vector2> dropoffPoints;
  final int coinReward;
  final LevelDifficulty difficulty;
  
  GameLevel({
    required this.levelNumber,
    required this.name,
    required this.pickupPoints,
    required this.dropoffPoints,
    required this.coinReward,
    required this.difficulty,
  });
  
  /// Creates a simple test level for initial development
  factory GameLevel.createTestLevel() {
    return GameLevel(
      levelNumber: 1,
      name: 'Test Level',
      pickupPoints: [const Offset(200, 400) as Vector2],
      dropoffPoints: [const Offset(200, 100) as Vector2],
      coinReward: 50,
      difficulty: LevelDifficulty.easy,
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
    };
  }
}

enum LevelDifficulty {
  easy,
  medium,
  hard,
  expert,
}

/// Simple Vector2 class for positions (will be replaced by Flame's Vector2)
class Vector2 {
  final double x;
  final double y;
  
  const Vector2(this.x, this.y);
  
  static final zero = Vector2(0, 0);
}
