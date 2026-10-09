import 'dart:convert';
import 'package:flutter/services.dart';
import '../game/levels/level.dart';

/// Thrown when a level the bundle should ship cannot be read or parsed
/// (issue #229).
///
/// The loader used to answer a failure with [GameLevel.createTestLevel]:
/// a corrupted or schema-shifted asset silently became level 1, the game
/// drove it under whatever level header the save named, and completing
/// the stand-in still unlocked the next rung. A typed failure keeps that
/// from ever being mistaken for real content or real progress.
class LevelLoadException implements Exception {
  LevelLoadException(this.levelNumber, this.assetPath, this.cause);

  /// The level the caller asked for.
  final int levelNumber;

  /// The asset the bundle was asked for.
  final String assetPath;

  /// The read/parse failure underneath.
  final Object cause;

  @override
  String toString() =>
      'LevelLoadException: level $levelNumber ($assetPath) could not be '
      'loaded: $cause';
}

/// Service to load levels from JSON files
class LevelLoaderService {
  /// Cache for loaded levels
  final Map<int, GameLevel> _levelCache = {};

  /// Names of every asset the bundle actually ships, loaded once. Level
  /// existence is checked against this manifest rather than by probing
  /// each file: a probe of a missing level throws inside the asset
  /// bundle, and that error report can escape the catch as a late zone
  /// failure (surfaced by the issue #16 widget tests).
  Set<String>? _bundledAssets;

  String _levelAssetPath(int levelNumber) =>
      'assets/levels/level_${levelNumber.toString().padLeft(3, '0')}.json';

  /// Load a level by number.
  ///
  /// A level the bundle declares but cannot read or parse **throws** a
  /// [LevelLoadException] rather than substituting
  /// [GameLevel.createTestLevel] (issue #229): the silent substitution
  /// drove a real save through a stand-in level and still unlocked the
  /// next rung when it completed. The caller decides how to surface the
  /// failure.
  Future<GameLevel> loadLevel(int levelNumber) async {
    // Check cache first
    if (_levelCache.containsKey(levelNumber)) {
      return _levelCache[levelNumber]!;
    }

    final path = _levelAssetPath(levelNumber);
    try {
      final jsonString = await rootBundle.loadString(path);
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;

      final level = GameLevel.fromJson(jsonData);

      // Cache the level
      _levelCache[levelNumber] = level;

      return level;
    } catch (error) {
      throw LevelLoadException(levelNumber, path, error);
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

  /// Check if a level exists — that the bundle actually ships it, per the
  /// asset manifest. Only if the manifest itself cannot be read (never
  /// true for the shipped bundle) does this fall back to probing the file.
  Future<bool> levelExists(int levelNumber) async {
    final path = _levelAssetPath(levelNumber);
    final assets = await _bundledAssetNames();
    if (assets.isNotEmpty) return assets.contains(path);
    return _probeLevelAsset(path);
  }

  Future<Set<String>> _bundledAssetNames() async {
    final cached = _bundledAssets;
    if (cached != null) return cached;
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return _bundledAssets = manifest.listAssets().toSet();
    } catch (e) {
      return const <String>{};
    }
  }

  Future<bool> _probeLevelAsset(String path) async {
    try {
      await rootBundle.loadString(path);
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
