import 'package:flame/components.dart';
import 'dart:math';

import '../taxi_game.dart';
import 'traffic_vehicle.dart';
import '../../models/traffic_pattern.dart';
import '../systems/difficulty_curve.dart';
import '../systems/run_environment.dart';

/// One spawn a wave has already accepted (issue #179): the role it will
/// drive, the spot it materialised on, and the body it rolled — the three
/// facts the no-overlap gate needs, recorded at the `add` itself because
/// the queue makes the car invisible to a `children` scan until the
/// tree's next update.
typedef _AcceptedSpawn = ({bool oncoming, Vector2 position, Vector2 size});

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
  /// any part of it crosses the barrier. Derived from the same body
  /// table [RunEnvironment.longestTrafficHalfLength] halves for the
  /// endless-road containment span (issue #87).
  static double get longestTrafficBodyLength =>
      RunEnvironment.longestTrafficHalfLength * 2;

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

  /// Bumper room the headway rule adds to the follower's own body length
  /// before its cap engages (issue #146). One frame at the fleet's
  /// fastest same-role overtake differential — an oncoming sports car
  /// (220 · 1.3 = 286 px/s) closing on a crawling bus (150 · 0.6 = 90)
  /// at 196 px/s — eats ~3.3 px at 1/60 s and ~13 px at the
  /// [TaxiGame.maxUpdateDelta] 1/15 s frame clamp (issue #36), so 16 px
  /// means the cap always lands while metal still stands between the
  /// bumpers.
  static const double headwayMargin = 16.0;

  @override
  void update(double dt) {
    super.update(dt);

    if (_isActive) {
      _timeSinceLastSpawn += dt;

      // Spawn new vehicles based on interval
      if (_timeSinceLastSpawn >= _profile.spawnInterval) {
        _timeSinceLastSpawn = 0.0;
        _spawnVehicles(_profile);
      }

      // Clean up vehicles that are off-screen
      _activeVehicles.removeWhere((vehicle) => vehicle.shouldRemove);
    }

    // Headway runs even while spawning is paused: the endings pause this
    // spawner while the world behind the overlay keeps rolling, and a
    // pass that stopped with the spawns would leave its last caps frozen
    // on cars that have long since left whoever paced them behind.
    _capTrafficHeadway();
  }

  /// Present-tense headway (issue #146): no traffic drives through
  /// traffic. Every car used to move at a constant drawn speed and read
  /// no other car, so a faster car passed straight through the slower
  /// one ahead in its lane — fused pairs sat on screen for 15-20 s of a
  /// 4-minute shift. Prevention at spawn cannot fix that: the avenue
  /// merge funnel converges two same-direction lanes onto one past a
  /// taper, so which cars end up sharing a lane is unknowable at the
  /// moment they materialise. This pass instead re-reads the road every
  /// frame — this spawner ticks before the vehicles it spawned (it was
  /// mounted first) — and caps each car's [TrafficVehicle.paceLimit] to
  /// the *effective* speed of same-role traffic ahead of it: same
  /// direction or oncoming alike (each role paces only itself; oncoming
  /// closing on the cab is the game, not a queue), laterally overlapped
  /// by full sprite width (the visible bodies, not the scaled hitboxes),
  /// and within a body length plus [headwayMargin] of bumper gap — the
  /// min over whoever qualifies, the same cap idiom the taxi's
  /// scraped-traffic rule (#60) uses. Merges, path extensions (#129)
  /// and the world fold (#30) all just change who is ahead, and the
  /// next frame reads the new truth. No RNG is spent, so per-seed
  /// reproducibility survives untouched; the O(n²) pass runs over the
  /// view band's handful of cars.
  void _capTrafficHeadway() {
    final world = _runWorld;
    if (world == null) return;
    final traffic = world.children.whereType<TrafficVehicle>().toList();

    // A fresh cap every frame: a cap that survived its frame would pace
    // a car to traffic that has since merged away or been culled.
    for (final vehicle in traffic) {
      vehicle.paceLimit = null;
    }

    for (final follower in traffic) {
      // Unmounted cars were queued this very frame, and a mounted car
      // whose async onLoad (sprite load) has not completed yet has no
      // velocity — either way it has no place in this frame's road, and
      // reading one would pace a whole lane to a standing ghost.
      if (!follower.isMounted || !follower.isLoaded) continue;
      final followerOncoming = follower.velocity.y > 0;
      for (final leader in traffic) {
        if (identical(leader, follower)) continue;
        if (!leader.isMounted || !leader.isLoaded) continue;
        // Same role only.
        if ((leader.velocity.y > 0) != followerOncoming) continue;
        final delta = leader.position.y - follower.position.y;
        // Ahead of the follower in *its* direction of travel: up-screen
        // (smaller y) for same-direction traffic, down-screen for
        // oncoming.
        if (followerOncoming ? delta <= 0 : delta >= 0) continue;
        // Laterally overlapped by the full bodies — the fusion a player
        // sees is sprite on sprite, and the taper's diagonals bring
        // merging cars into this overlap gradually, which is exactly
        // when they must start pacing each other.
        if ((leader.position.x - follower.position.x).abs() >=
            (leader.vehicleSize.x + follower.vehicleSize.x) / 2) {
          continue;
        }
        final bumperGap =
            delta.abs() - (leader.vehicleSize.y + follower.vehicleSize.y) / 2;
        if (bumperGap > follower.vehicleSize.y + headwayMargin) continue;
        // Effective speed: the leader may itself be paced by the car
        // ahead of it, and a queue must inherit the front's pace, not
        // the leader's cruise. And when a merge race has already
        // delivered the follower *onto* the leader (negative bumper
        // gap), matching pace would only freeze the overlap in place —
        // so there the cap eases 20% below the leader's pace until the
        // bumpers part, and the plain cap holds the gap from there.
        final pace = leader.velocity.length * (bumperGap < 0 ? 0.8 : 1.0);
        final limit = follower.paceLimit;
        if (limit == null || pace < limit) {
          follower.paceLimit = pace;
        }
      }
    }
  }

  void _spawnVehicles(TrafficProfile profile) {
    // Where this wave materialises: a fixed 500 px ahead of the camera,
    // one frame shared by every lane of the wave.
    final spawnY = game.camera.viewfinder.position.y - spawnDistanceAhead;

    // The lane list belongs to the road the cars will stand on (issue
    // #95): the profile's lanes are laid over the road under the *taxi*
    // (the pressure's home), but the car materialises 500 px ahead —
    // where an avenue may already have narrowed to two lanes. Fractions
    // survive a width change, not a lane-count change: re-laying the
    // taxi-road lanes onto a two-lane street put the avenue's middle
    // lane exactly on that street's centre divider, where a car drove
    // half in the oncoming lane for its whole fixed-x life. The
    // difficulty core — interval, speeds, per-side probability — stays
    // at the taxi's distance; only the lane xs, roles, and count come
    // from the spawn road. Level mode has no living road (fixed lanes on
    // a fixed street) and keeps the pattern's lanes.
    final env = game.environment;
    final spawnDistance =
        env == null ? null : max(0.0, game.worldShift - spawnY);
    final lanes = env == null
        ? profile.lanes
        : env
            .trafficAt(_distanceOf!(), geometryDistance: spawnDistance)
            .lanes;

    // The wave's ledger of accepted spawns (issue #179): every lane of a
    // wave shares this one frame and this one spawnY, and `add` only
    // queues a component — the car the first lane accepted does not reach
    // world.children (let alone `isMounted`) until the tree's own update,
    // long after the last lane's gate has run. The ledger carries the
    // accepted fact itself, so the last lane can be gated against what
    // the first lane did in the same breath. It lives and dies with the
    // wave: the children scan below already covers every earlier wave.
    final wave = <_AcceptedSpawn>[];

    // Try to spawn a vehicle in each lane based on probability
    for (final laneConfig in lanes) {
      if (random.nextDouble() <= laneConfig.spawnProbability) {
        _spawnVehicleInLane(laneConfig, spawnY, spawnDistance, wave);
      }
    }
  }

  void _spawnVehicleInLane(
    TrafficLaneConfig laneConfig,
    double spawnY,
    double? spawnDistance,
    List<_AcceptedSpawn> wave,
  ) {
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
    // toward the origin as the run deepens. The lane x is already the
    // spawn road's own (chosen in [_spawnVehicles], issue #95), so it is
    // used as-is.
    final env = game.environment;
    final spawnX = laneConfig.laneX;
    if (env != null) {
      if (env.isIntersectionAt(spawnDistance!)) return;
      if (env.isLaneBlockedAt(spawnDistance, spawnX)) return;
    }

    // Generate random speed within range. Same-direction traffic drives
    // slower than the player so it can be overtaken.
    var speed = laneConfig.speedRange.min +
        random.nextDouble() * (laneConfig.speedRange.max - laneConfig.speedRange.min);
    if (!laneConfig.oncoming) {
      speed *= 0.5;
    }

    // The body this spawn rolls, drawn here — it used to be drawn
    // inside TrafficVehicle's random factory — so the containment gate
    // below can ask whether THIS body's footprint fits; the draw order
    // is unchanged from before the gate learned about bodies:
    // probability, speed, type.
    const types = TrafficVehicleType.values;
    final type = types[random.nextInt(types.length)];

    // No materialising on top of living traffic (issue #146). The spawn
    // line sweeps the road the camera is leaving, and a wave that fires
    // while a same-role car sits on it used to place the new car inside
    // it: before the headway rule the pair simply drove through each
    // other, but with the rule in place a fed chain of such overlaps
    // eases apart 0.8× per link — compounding toward standing. The gate
    // skips the spawn when the rolled body would land overlapping any
    // same-role car's full body (plus the headway margin), and it runs
    // after the roll like every gate above, so the RNG stream per seed
    // is untouched.
    for (final other in _runWorld!.children.whereType<TrafficVehicle>()) {
      if (!other.isMounted || !other.isLoaded) continue;
      if ((other.velocity.y > 0) != laneConfig.oncoming) continue;
      if ((other.position.x - spawnX).abs() >=
          (other.vehicleSize.x + type.size.x) / 2) {
        continue;
      }
      if ((other.position.y - spawnY).abs() <
          (other.vehicleSize.y + type.size.y) / 2 + headwayMargin) {
        return;
      }
    }

    // The same question over the wave's own ledger (issue #179): the scan
    // above reads world.children, but Flame's `add` only queues — a car
    // an earlier lane of THIS wave accepted is unmounted when this gate
    // runs, so the scan has been blind to same-wave spawns. On the
    // tutorial ladder that is not hypothetical: rung 10's pattern runs
    // two oncoming lanes 40 px apart (x 160 and 200), and a wave that
    // rolled wide bodies into both — a bus is 50 px across, and even a
    // sedan pairing hits (40+45)/2 — materialised them laterally
    // overlapped on the wave's one shared spawnY: two cars fused side by
    // side, driving down on the player abreast until the headway rule's
    // 0.8× easing was all that parted them. The record carries its own
    // oncoming flag because a queued car's velocity is still zero — its
    // path starts on the spawn point, so there is no sign to read yet
    // (the same reason the sprite flip reads the path, not the velocity,
    // issue #72). Like the scan above, this gate runs after the type
    // roll, spends no RNG, and judges same-role pairs only — an oncoming
    // car abreast of same-direction traffic is two-way traffic, not a
    // fusion.
    for (final queued in wave) {
      if (queued.oncoming != laneConfig.oncoming) continue;
      if ((queued.position.x - spawnX).abs() >=
          (queued.size.x + type.size.x) / 2) {
        continue;
      }
      if ((queued.position.y - spawnY).abs() <
          (queued.size.y + type.size.y) / 2 + headwayMargin) {
        return;
      }
    }

    // The waypoints the vehicle will follow: the endless road's merge
    // schedule, or the level street's straight lanes.
    late final List<Vector2> path;

    if (env != null) {
      // The merge schedule (issue #107): #95 fixed where cars spawn —
      // the lane set comes from the road at the spawn distance — but
      // the path stayed fixed-x, so an avenue middle-lane car (x 200)
      // drove that x straight onto the two-lane street's centre
      // divider past the taper, exactly the defect the schedule's
      // merges remove. The gate below asks the shared per-leg form:
      // each constant-x stretch gets the fixed-x [laneHoldsOnRoad]
      // question over the stretch it holds (the body's own full sprite
      // width — a sedan's footprint fits a narrowing a bus's would
      // overhang), while the diagonal merge legs are structural by
      // convexity, documented on [RunEnvironment.trafficMergeWaypoints]
      // — which is what lets an avenue kerb-lane car merge through a
      // narrowing the old whole-span fixed-x gate had to turn away. A
      // skipped spawn has already spent its rolls; they produced
      // nothing, and the stream stays deterministic per seed.
      final merge = env.trafficMergeWaypoints(
        spawnDistance!,
        laneConfig.laneX,
        oncoming: laneConfig.oncoming,
      );
      if (!env.mergePathHoldsOnRoad(
        merge,
        type.size.x / 2,
        oncoming: laneConfig.oncoming,
      )) {
        return;
      }

      // Oncoming traffic drives down toward the player; same-direction
      // traffic drives up and gets caught from behind. The schedule's
      // (distance, x) anchors become world waypoints through the same
      // shift the spawn distance came from, so the road a waypoint
      // names is the road the car is on when it reaches it.
      final shift = game.worldShift;
      final mergedPath = <Vector2>[
        for (final (d, x) in merge) Vector2(x, shift - d),
      ]..[0] = Vector2(spawnX, spawnY);
      path = mergedPath;
    } else {
      // Level mode has no living road — fixed lanes on a fixed street —
      // so its paths stay straight (issue #31's end clamps included).
      path = _createStraightPath(
        Vector2(spawnX, spawnY),
        oncoming: laneConfig.oncoming,
      );
    }

    // Create or reuse vehicle. The game reference is pinned at
    // construction (issue #32): a retired spawner's last spawn may outlive
    // its tree attachment, and the vehicle's sprite load must not depend
    // on walking a tree that is being torn down underneath it.
    final vehicle = TrafficVehicle(
      position: Vector2(spawnX, spawnY),
      vehicleType: type,
      baseSpeed: speed,
      path: path,
    )..game = game;

    // Add to this run's world so it scrolls with the camera (issue #32:
    // this spawner's own world, never the live getter — a retired
    // spawner's last tick must not write into the fresh run's world).
    _runWorld!.add(vehicle);
    // And the ledger learns of it with the add, not before: a spawn any
    // gate above rejected contributed nothing, and later lanes of this
    // wave must not be gated around a car that never materialised. A
    // fresh snapshot, not a reference to the vehicle's live position —
    // the record stands for the accept decision as it was made.
    wave.add(
      (
        oncoming: laneConfig.oncoming,
        position: Vector2(spawnX, spawnY),
        size: type.size,
      ),
    );
    _activeVehicles.add(vehicle);
  }

  /// Creates a straight path along the lane. Oncoming paths run down the
  /// screen; same-direction paths run far up the road (in an endless
  /// run those vehicles outlive the path while in view — the schedule
  /// is rebuilt and the car is culled only off either edge of the view
  /// band, issue #129 — while on the level-mode paths they arrive at
  /// the street's end and despawn).
  List<Vector2> _createStraightPath(Vector2 startPosition, {required bool oncoming}) {
    final step = oncoming ? 500.0 : -3000.0;
    // Same-direction traffic in an endless run lives only 3000 px past its
    // spawn point (issue #18): on the level-mode paths it travels 9000 px
    // up-road and accumulates into a standing wall of slow cars whose
    // density is set by minutes of history, not by the difficulty curve at
    // the player's distance — the run simulator showed the curve's shape
    // drowning in stale stock. Level mode keeps the long paths; its levels
    // are short enough that no wall forms. Since issue #129 the 3000 px is
    // a schedule, not a lifetime: a car whose path runs out inside the
    // view band keeps driving on a rebuilt schedule ([TrafficVehicle]
    // extends it), so the span bounds the *planning* horizon while the
    // culls — a screen past either edge of the camera — bound the stock.
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
  ///
  /// An *unmounted* vehicle — one whose spawn fired this very frame, so
  /// `add` has only queued it (Flame applies the queue inside the tree's
  /// own update, which runs after the fold) — is not yet in
  /// `world.children`, so the fold's walk over the tree never moved its
  /// position. Moving only its path here would leave position and
  /// waypoints a whole period (`WorldOrigin.period`, 100,800 px) apart:
  /// the first waypoint sits that far away, so it can never be reached
  /// to advance past, and the car — frozen in the stale frame —
  /// reappears one period later as a parked obstacle in the middle of
  /// the road (issue #98).
  /// Shifting an unmounted car's position here keeps position and path
  /// in the same frame; a mounted car's position was already moved by
  /// the tree walk, and moving it again would double-shift it.
  void shiftWorld(double dy) {
    for (final vehicle in _activeVehicles) {
      if (!vehicle.isMounted) {
        vehicle.position.y += dy;
      }
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
