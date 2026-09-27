import 'package:flame/components.dart';
import 'dart:math';

import '../taxi_game.dart';
import 'traffic_vehicle.dart';
import '../../models/traffic_pattern.dart';
import '../systems/difficulty_curve.dart';

/// Manages spawning of traffic vehicles based on patterns
class TrafficSpawner extends Component with HasGameReference<TaxiGame> {
  /// Level mode: a fixed per-level pattern for the whole level. The RNG
  /// is injectable so tests (and any future seed) can pin the weather of
  /// spawn rolls.
  TrafficSpawner({required TrafficPattern pattern, Random? random})
      : _fixedPattern = pattern,
        _profileOf = null,
        _distanceOf = null,
        random = random ?? Random();

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

  /// The world this run's traffic belongs to, captured on mount (issue
  /// #32). A retired spawner can still get one update after [TaxiGame]
  /// has swapped in the fresh run's world; spawning through the live
  /// [TaxiGame.world] getter then would drop a previous-run car onto the
  /// new run's street. Vehicles always go to this spawner's own world.
  World? _runWorld;

  @override
  void onMount() {
    super.onMount();
    _runWorld = game.world;
  }

  // Spawn area (ahead of camera view)
  static const double spawnDistanceAhead = 500.0;

  /// Length in px of the longest traffic body any lane can spawn (issue
  /// #31): the clearance traffic keeps from the level course's end — a
  /// spawn holds half of this inside the street so the vehicle
  /// materialises entirely on it, and a same-direction path terminates
  /// this far below the end so the vehicle despawns on arrival before
  /// any part of it crosses the barrier.
  static double get longestTrafficBodyLength => TrafficVehicleType.values
      .map((type) => type.size.y)
      .reduce(max);

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

    // The level course ends (issue #31): nothing materialises past its
    // end, and whatever spawns near it stays fully on the street — half
    // the longest body is the least depth that guarantees that. The roll
    // above already happened, so skipping keeps the RNG stream — and any
    // seed's reproducibility — untouched. Endless roads are infinite and
    // need no gate.
    final roadTopY = game.levelRoadTopY;
    if (roadTopY != null &&
        spawnY - longestTrafficBodyLength / 2 < roadTopY) {
      return;
    }

    // The living road (issue #24) keeps some ground clear: traffic never
    // materialises inside a work zone's closed lanes or on a cross
    // street. The roll above already happened, so skipping keeps the RNG
    // stream — and with it the seed's reproducibility — untouched. The
    // clearance reads true distance (issue #30): world y folds back
    // toward the origin as the run deepens.
    final env = game.environment;
    if (env != null) {
      final spawnDistance = max(0.0, game.worldShift - spawnY);
      if (env.isIntersectionAt(spawnDistance)) return;
      if (env.isLaneBlockedAt(spawnDistance, spawnX)) return;
    }

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

    // Create or reuse vehicle. The game reference is pinned at
    // construction (issue #32): a retired spawner's last spawn may outlive
    // its tree attachment, and the vehicle's sprite load must not depend
    // on walking a tree that is being torn down underneath it.
    final vehicle = TrafficVehicle.random(
      position: Vector2(spawnX, spawnY),
      baseSpeed: speed,
      path: path,
      random: random,
    )..game = game;

    // Add to this run's world so it scrolls with the camera (issue #32:
    // this spawner's own world, never the live getter — a retired
    // spawner's last tick must not write into the fresh run's world).
    _runWorld!.add(vehicle);
    _activeVehicles.add(vehicle);
  }

  /// Creates a straight path along the lane. Oncoming paths run down the
  /// screen; same-direction paths run far up the road (those vehicles are
  /// despawned once the player passes them).
  List<Vector2> _createStraightPath(Vector2 startPosition, {required bool oncoming}) {
    final step = oncoming ? 500.0 : -3000.0;
    // Same-direction traffic in an endless run lives only 3000 px past its
    // spawn point (issue #18): on the level-mode paths it travels 9000 px
    // up-road and accumulates into a standing wall of slow cars whose
    // density is set by minutes of history, not by the difficulty curve at
    // the player's distance — the run simulator showed the curve's shape
    // drowning in stale stock. Level mode keeps the long paths; its levels
    // are short enough that no wall forms.
    final sameDirectionWaypoints = _profileOf != null ? 1 : 3;
    final path = <Vector2>[startPosition];
    for (var i = 1; i <= (oncoming ? 3 : sameDirectionWaypoints); i++) {
      path.add(Vector2(startPosition.x, startPosition.y + step * i));
    }

    // The level street ends (issue #31): a same-direction path stops a
    // body-length inside the end, so the vehicle despawns on arrival
    // instead of driving off the road past the barrier. Oncoming paths
    // run down-screen, away from the end, and are left alone.
    final roadTopY = game.levelRoadTopY;
    if (roadTopY != null && !oncoming) {
      final minWaypointY = roadTopY + longestTrafficBodyLength;
      for (var i = 0; i < path.length; i++) {
        if (path[i].y < minWaypointY) {
          path[i] = Vector2(path[i].x, minWaypointY);
        }
      }
    }
    return path;
  }

  /// Moves every active vehicle's stored path into the world frame
  /// shifted by [dy] (issue #30's fold). The vehicles themselves are world
  /// components the game's fold moves directly; their waypoints live here,
  /// so a vehicle steering across a fold would otherwise aim at a spot a
  /// whole period behind the road it is on.
  void shiftWorld(double dy) {
    for (final vehicle in _activeVehicles) {
      for (var i = 0; i < vehicle.path.length; i++) {
        vehicle.path[i] = Vector2(vehicle.path[i].x, vehicle.path[i].y + dy);
      }
    }
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
