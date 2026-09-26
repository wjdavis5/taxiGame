import 'package:flame/components.dart';
import 'dart:math';

import '../taxi_game.dart';
import 'traffic_vehicle.dart';
import '../../models/traffic_pattern.dart';
import '../systems/difficulty_curve.dart';

/// Manages spawning of traffic vehicles based on patterns
class TrafficSpawner extends Component with HasGameReference<TaxiGame> {
  /// Level mode: a fixed per-level pattern for the whole level.
  TrafficSpawner({required TrafficPattern pattern})
      : _fixedPattern = pattern,
        _profileOf = null,
        _distanceOf = null,
        random = Random();

  /// Endless mode (issue #11): density and speed come from a continuous
  /// profile curve evaluated at the run's current distance, and the RNG is
  /// injectable so the same seed reproduces the same traffic exactly.
  TrafficSpawner.distanceBased({
    required TrafficProfile Function(double distance) profileOf,
    required double Function() distanceOf,
    Random? random,
  })  : _fixedPattern = null,
        _profileOf = profileOf,
        _distanceOf = distanceOf,
        random = random ?? Random();

  final TrafficPattern? _fixedPattern;
  final TrafficProfile Function(double distance)? _profileOf;
  final double Function()? _distanceOf;

  /// The RNG driving every spawn decision. Seeded in endless mode.
  final Random random;

  double _timeSinceLastSpawn = 0.0;
  bool _isActive = true;

  final List<TrafficVehicle> _activeVehicles = [];

  // Spawn area (ahead of camera view)
  static const double spawnDistanceAhead = 500.0;

  /// Factory constructors for common patterns
  factory TrafficSpawner.light() => TrafficSpawner(pattern: TrafficPattern.light);
  factory TrafficSpawner.medium() => TrafficSpawner(pattern: TrafficPattern.medium);
  factory TrafficSpawner.heavy() => TrafficSpawner(pattern: TrafficPattern.heavy);

  /// The traffic pressure in effect right now: the level's fixed pattern,
  /// or the distance curve for endless runs.
  TrafficProfile get _profile {
    final profileOf = _profileOf;
    if (profileOf != null) return profileOf(_distanceOf!());
    final pattern = _fixedPattern!;
    return TrafficProfile(
      spawnInterval: pattern.spawnInterval,
      lanes: pattern.lanes,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (!_isActive) return;

    _timeSinceLastSpawn += dt;

    // Spawn new vehicles based on interval
    if (_timeSinceLastSpawn >= _profile.spawnInterval) {
      _timeSinceLastSpawn = 0.0;
      _spawnVehicles(_profile);
    }

    // Clean up vehicles that are off-screen
    _activeVehicles.removeWhere((vehicle) => vehicle.shouldRemove);
  }

  void _spawnVehicles(TrafficProfile profile) {
    // Try to spawn a vehicle in each lane based on probability
    for (final laneConfig in profile.lanes) {
      if (random.nextDouble() <= laneConfig.spawnProbability) {
        _spawnVehicleInLane(laneConfig);
      }
    }
  }

  void _spawnVehicleInLane(TrafficLaneConfig laneConfig) {
    // Calculate spawn position (ahead of player/camera)
    final spawnY = game.camera.viewfinder.position.y - spawnDistanceAhead;
    final spawnX = laneConfig.laneX;

    // Generate random speed within range. Same-direction traffic drives
    // slower than the player so it can be overtaken.
    var speed = laneConfig.speedRange.min +
        random.nextDouble() * (laneConfig.speedRange.max - laneConfig.speedRange.min);
    if (!laneConfig.oncoming) {
      speed *= 0.5;
    }

    // Oncoming traffic drives down toward the player; same-direction
    // traffic drives up and gets caught from behind.
    final path = _createStraightPath(
      Vector2(spawnX, spawnY),
      oncoming: laneConfig.oncoming,
    );

    // Create or reuse vehicle
    final vehicle = TrafficVehicle.random(
      position: Vector2(spawnX, spawnY),
      baseSpeed: speed,
      path: path,
      random: random,
    );

    // Add to the game world so it scrolls with the camera
    game.world.add(vehicle);
    _activeVehicles.add(vehicle);
  }

  /// Creates a straight path along the lane. Oncoming paths run down the
  /// screen; same-direction paths run far up the road (those vehicles are
  /// despawned once the player passes them).
  List<Vector2> _createStraightPath(Vector2 startPosition, {required bool oncoming}) {
    final step = oncoming ? 500.0 : -3000.0;
    return [
      startPosition,
      Vector2(startPosition.x, startPosition.y + step),
      Vector2(startPosition.x, startPosition.y + step * 2),
      Vector2(startPosition.x, startPosition.y + step * 3),
    ];
  }

  /// Pauses traffic spawning
  void pause() {
    _isActive = false;
  }

  /// Resumes traffic spawning
  void resume() {
    _isActive = true;
  }

  /// Stops spawning and clears all active vehicles
  void clear() {
    _isActive = false;
    for (final vehicle in _activeVehicles) {
      vehicle.removeFromParent();
    }
    _activeVehicles.clear();
  }

  /// Gets count of active vehicles (for debugging)
  int get activeVehicleCount => _activeVehicles.length;
}
