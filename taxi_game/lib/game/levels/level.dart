import 'package:flame/components.dart';
import '../../models/traffic_pattern.dart';

/// Represents a game level with all its data
class GameLevel {
  /// How many rungs the tutorial ladder has (issue #16). The ten hand-made
  /// levels in `assets/levels/` are the onboarding that teaches Endless —
  /// hold-and-steer, pickup and dropoff, the fare timer, the chain
  /// multiplier, and finally banking — after which the game hands off to
  /// an endless shift. Must match what ships in `assets/levels/`; the
  /// ladder test loads the real assets and holds the two in sync.
  static const int ladderLength = 10;

  final int levelNumber;
  final String name;
  final List<Vector2> pickupPoints;
  final List<Vector2> dropoffPoints;
  final int coinReward;
  final LevelDifficulty difficulty;
  final TrafficPattern trafficPattern;

  /// Whether this level teaches banking (issue #16): every dropoff that
  /// still leaves fares undelivered offers the timed bank-or-push choice,
  /// exactly as an endless dropoff does. Banking converts the chain score
  /// to coins 1:1 and settles the level as a success; pushing on chases a
  /// bigger score at the risk of a crash forfeiting it. The last two rungs
  /// set this — a new player reaches Endless having already made the
  /// choice.
  final bool bankPromptEnabled;

  GameLevel({
    required this.levelNumber,
    required this.name,
    required this.pickupPoints,
    required this.dropoffPoints,
    required this.coinReward,
    required this.difficulty,
    this.bankPromptEnabled = false,
    TrafficPattern? trafficPattern,
  }) : trafficPattern = trafficPattern ?? TrafficPattern.light;

  /// Creates a simple test level for initial development
  factory GameLevel.createTestLevel() {
    return GameLevel(
      levelNumber: 1,
      name: 'Test Level',
      pickupPoints: [Vector2(85, -300)], // Left curb
      dropoffPoints: [Vector2(315, -800)], // Right curb, further up
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
          .map((p) => Vector2((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList(),
      dropoffPoints: (json['dropoffPoints'] as List)
          .map((p) => Vector2((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList(),
      coinReward: json['coinReward'] as int,
      difficulty: LevelDifficulty.values.byName(json['difficulty'] as String),
      // Levels written before the banking lesson predate the flag; a
      // missing key means "this rung does not teach banking".
      bankPromptEnabled: (json['bankPrompt'] as bool?) ?? false,
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
      'bankPrompt': bankPromptEnabled,
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
