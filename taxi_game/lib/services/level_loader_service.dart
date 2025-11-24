import 'dart:convert';
import 'package:flutter/services.dart';
import '../game/levels/level.dart';

/// Service to load levels from JSON files
class LevelLoaderService {
  /// Cache for loaded levels
  final Map<int, GameLevel> _levelCache = {};

  /// Load a level by number
  Future<GameLevel> loadLevel(int levelNumber) async {
    // Check cache first
    if (_levelCache.containsKey(levelNumber)) {
      return _levelCache[levelNumber]!;
    }

    try {
      // Format level number with leading zeros (001, 002, etc.)
      final levelFile = 'level_${levelNumber.toString().padLeft(3, '0')}.json';
      final jsonString = await rootBundle.loadString('assets/levels/$levelFile');
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;

      final level = GameLevel.fromJson(jsonData);

      // Cache the level
      _levelCache[levelNumber] = level;

      return level;
    } catch (e) {
      // If level file doesn't exist, return a default test level
      print('Error loading level $levelNumber: $e');
      print('Falling back to test level');
      return GameLevel.createTestLevel();
    }
  }

  /// Preload multiple levels
  Future<void> preloadLevels(List<int> levelNumbers) async {
    for (final levelNumber in levelNumbers) {
      await loadLevel(levelNumber);
    }
  }

  /// Clear the cache
  void clearCache() {
    _levelCache.clear();
  }

  /// Check if a level exists
  Future<bool> levelExists(int levelNumber) async {
    try {
      final levelFile = 'level_${levelNumber.toString().padLeft(3, '0')}.json';
      await rootBundle.loadString('assets/levels/$levelFile');
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get total number of available levels
  Future<int> getTotalLevels() async {
    int count = 0;
    for (int i = 1; i <= 100; i++) {
      // Check up to 100 levels
      if (await levelExists(i)) {
        count = i;
      } else {
        break;
      }
    }
    return count;
  }
}
