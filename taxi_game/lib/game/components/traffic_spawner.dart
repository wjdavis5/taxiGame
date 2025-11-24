import 'package:flame/components.dart';
import 'dart:math';

import '../taxi_game.dart';
import 'traffic_vehicle.dart';
import '../../models/traffic_pattern.dart';

/// Manages spawning of traffic vehicles based on patterns
class TrafficSpawner extends Component with HasGameReference<TaxiGame> {
  final TrafficPattern pattern;
  final Random random = Random();

  double _timeSinceLastSpawn = 0.0;
  bool _isActive = true;

  // Pool for reusing vehicles (optimization)
  final List<TrafficVehicle> _vehiclePool = [];
  final List<TrafficVehicle> _activeVehicles = [];

  // Spawn area (ahead of camera view)
  static const double spawnDistanceAhead = 500.0;

  TrafficSpawner({required this.pattern});

  /// Factory constructors for common patterns
  factory TrafficSpawner.light() => TrafficSpawner(pattern: TrafficPattern.light);
  factory TrafficSpawner.medium() => TrafficSpawner(pattern: TrafficPattern.medium);
  factory TrafficSpawner.heavy() => TrafficSpawner(pattern: TrafficPattern.heavy);

  @override
  void update(double dt) {
    super.update(dt);

    if (!_isActive) return;

    _timeSinceLastSpawn += dt;

    // Spawn new vehicles based on interval
    if (_timeSinceLastSpawn >= pattern.spawnInterval) {
      _timeSinceLastSpawn = 0.0;
      _spawnVehicles();
    }

    // Clean up vehicles that are off-screen
    _activeVehicles.removeWhere((vehicle) => vehicle.shouldRemove);
  }

  void _spawnVehicles() {
    // Try to spawn a vehicle in each lane based on probability
    for (final laneConfig in pattern.lanes) {
      if (random.nextDouble() <= laneConfig.spawnProbability) {
        _spawnVehicleInLane(laneConfig);
      }
    }
  }

  void _spawnVehicleInLane(TrafficLaneConfig laneConfig) {
    // Calculate spawn position (ahead of player/camera)
    final spawnY = game.camera.viewfinder.position.y - spawnDistanceAhead;
    final spawnX = laneConfig.laneX;

    // Generate random speed within range
    final speed = laneConfig.speedRange.min +
        random.nextDouble() * (laneConfig.speedRange.max - laneConfig.speedRange.min);

    // Create path (for now, just move straight down)
    final path = _createStraightPath(Vector2(spawnX, spawnY));

    // Create or reuse vehicle
    final vehicle = TrafficVehicle.random(
      position: Vector2(spawnX, spawnY),
      baseSpeed: speed,
      path: path,
      random: random,
    );

    // Add to game
    game.add(vehicle);
    _activeVehicles.add(vehicle);
  }

  /// Creates a straight path moving downward (in player's direction)
  List<Vector2> _createStraightPath(Vector2 startPosition) {
    // Create waypoints going down the road
    return [
      startPosition,
      Vector2(startPosition.x, startPosition.y + 500),
      Vector2(startPosition.x, startPosition.y + 1000),
      Vector2(startPosition.x, startPosition.y + 1500),
    ];
  }

  /// Creates a path with a lane change
  List<Vector2> _createLaneChangePath(Vector2 startPosition, double targetLaneX) {
    final midY = startPosition.y + 250;
    return [
      startPosition,
      Vector2(startPosition.x, midY),
      Vector2(targetLaneX, midY + 100),
      Vector2(targetLaneX, midY + 500),
      Vector2(targetLaneX, midY + 1000),
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
