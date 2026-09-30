import 'dart:math' as math;

import '../../data/vehicle_catalog.dart';
import '../../models/traffic_pattern.dart';
import '../components/player_vehicle.dart' show PlayerVehicle;
import 'collision_rules.dart';
import 'run_environment.dart';

/// One fare stop the simulated driver completed: the distance the shift
/// had reached when the taxi pulled over, and how long the whole stop
/// cycle took — the px driven and the seconds elapsed since the previous
/// stop (or the start line). The raw material of the earnings harness
/// (issue #34): the real course deals one fare per slot, so stop *k* is
/// the delivery of fare *k*, and the cycle time is what its meter is
/// judged against.
class FareStop {
  const FareStop({
    required this.distancePx,
    required this.cyclePx,
    required this.cycleSeconds,
  });

  /// True distance into the shift of the boarding, in px.
  final double distancePx;

  /// Distance driven since the previous boarding (or the start), in px.
  final double cyclePx;

  /// Seconds the cycle took, including the board itself and the kerb
  /// approach — every second between one delivery and the next.
  final double cycleSeconds;
}

/// The outcome of one simulated shift.
class SimulatedRun {
  const SimulatedRun({
    required this.seed,
    required this.distancePx,
    required this.drivenSeconds,
    required this.crashDistancesPx,
    required this.survived,
    this.fareStops = const [],
  });

  final int seed;

  /// How far the simulated taxi drove before the third crash ended the
  /// shift (or before the harness's safety cap, for [survived] runs), in px.
  final double distancePx;

  /// Seconds the shift was actively driven — stall time excluded, matching
  /// [RunRecord.durationSeconds]' semantics.
  final double drivenSeconds;

  /// How far into the shift each crash-grade contact landed, in loss order.
  final List<double> crashDistancesPx;

  /// True when the run hit the harness's distance cap still alive — the
  /// curve never caught this driver. Counts as an extremely long run.
  final bool survived;

  /// Every fare stop the driver completed, in delivery order. Recorded at
  /// each boarding — the moment the real game starts a fare's meter and
  /// banks a delivery.
  final List<FareStop> fareStops;

  double get distanceMetres => distancePx / 10.0; // RunSummary.pixelsPerMetre
}

/// Aggregate of a Monte-Carlo batch: the raw material of the tuning
/// decision. Median, not mean — one 40 km veteran next to a pile of
/// first-kilometre wrecks must not flatter the curve.
class RunLengthEstimate {
  RunLengthEstimate._({required this.runs});

  final List<SimulatedRun> runs;

  static RunLengthEstimate compute(List<SimulatedRun> runs) =>
      RunLengthEstimate._(runs: List.unmodifiable(runs));

  /// Median distance the shift reached, in px.
  double get medianDistancePx {
    final sorted = runs.map((r) => r.distancePx).toList()..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Share of runs still alive past [distancePx].
  double survivalFractionBeyond(double distancePx) => runs.isEmpty
      ? 0.0
      : runs.where((r) => r.distancePx >= distancePx).length / runs.length;

  /// Share of runs that ended before [distancePx] — early deaths.
  double deathFractionWithin(double distancePx) => runs.isEmpty
      ? 0.0
      : runs.where((r) => !r.survived && r.distancePx < distancePx).length /
          runs.length;

  /// Death rate inside each [windowPx] band of road, among the runs that
  /// were still alive entering it: the shape of the whole curve at a
  /// glance. A spike means an impossible wall; a gentle rise means deaths
  /// are being earned progressively.
  List<HazardWindow> hazardWindows({double windowPx = 10000.0}) {
    final windows = <HazardWindow>[];
    final maxDistance =
        runs.fold(0.0, (m, r) => math.max(m, r.distancePx));
    for (var start = 0.0; start < maxDistance; start += windowPx) {
      final end = start + windowPx;
      final alive = runs.where((r) => r.distancePx >= start).length;
      final deaths =
          runs.where((r) => !r.survived && r.distancePx >= start && r.distancePx < end).length;
      windows.add(HazardWindow(
        startPx: start,
        endPx: end,
        aliveAtStart: alive,
        deaths: deaths,
      ));
    }
    return windows;
  }
}

/// One band of road and how lethal it proved.
class HazardWindow {
  const HazardWindow({
    required this.startPx,
    required this.endPx,
    required this.aliveAtStart,
    required this.deaths,
  });

  final double startPx;
  final double endPx;
  final int aliveAtStart;
  final int deaths;

  /// Fraction of still-alive runs that died inside this band.
  double get deathRate => aliveAtStart == 0 ? 0.0 : deaths / aliveAtStart;
}

/// A headless Monte-Carlo estimate of endless run length (issue #18).
///
/// The game ships with no analytics, and issue #17's on-device stats screen
/// has no real history yet — no device playtesting exists to tune against.
/// This simulator is the stand-in: it rebuilds a shift from the same pure
/// pieces the live game runs — [DifficultyCurve] for traffic,
/// [VehicleStats] for the car, [CollisionRules] for what kills — and drives
/// it with a simple reflex policy, many seeds at once. The tuning target is
/// the batch's *median* run length.
///
/// **What it models, faithfully:**
///  - spawning: the spawner's exact cadence (interval read from the curve
///    at the current distance, per-lane probability roll, speed drawn from
///    the lane range, same-direction traffic halved, vehicle-type
///    multiplier applied, spawns 500 px ahead of the camera);
///  - the living road (issue #24): [RunEnvironment] for the street itself
///    — lane targets and kerb stops follow the local width, traffic rides
///    the environment-aware profile with the weather/night modifier folded
///    into the pressure, rain scales the steering speed full lock gets,
///    fog shortens the driver's planning horizon, and no traffic spawns on
///    cross streets or in closed works lanes;
///  - physics: the player's throttle ramp and braking from [vehicle]'s
///    stats, lateral movement at full steering lock, both hitboxes scaled
///    exactly as the live game scales them;
///  - rulings: every contact judged by [CollisionRules.severityFor] on the
///    closing speed along the impact axis *and* the player's share of it
///    (issue #58: traffic ramming a boxed-in taxi is a scrape, not a
///    life), once per overlap episode —
///    scrapes shed speed and push apart, crashes spend one of three lives
///    and freeze the world for the crash stall;
///  - the driver: a competent human stand-in. It scans the road at
///    [reactionInterval] (not every frame — people are not 60 Hz), dodges
///    to the clear lane when threatened, brakes when both lanes are, keeps
///    following distance off a slow blocker, and must physically travel
///    between lanes at its car's steering speed.
///
/// **What it deliberately does not model:** fares. Collecting them weaves
/// the taxi out to the kerbs and adds exposure the policy never takes, so
/// the simulator is *optimistic* — it measures the difficulty system in
/// isolation, and real runs die somewhat sooner. The tuning band carries
/// margin for that. When TestFlight players eventually fill the issue #17
/// history, the on-device median is the ground truth this estimate is
/// checked against; until then this harness is the instrument.
class RunLengthSimulator {
  RunLengthSimulator({
    required this.seed,
    this.vehicle,
    this.environment,
    this.reactionInterval = 0.25,
    this.lookaheadSeconds = 1.25,
    this.misjudgeRate = 0.03,
    this.dt = 1 / 60,
  });

  /// RNG seed for the run's traffic. Same seed, same run.
  final int seed;

  /// The car being driven. Defaults to the starter cab — the car the
  /// median player is in.
  final VehicleStats? vehicle;

  /// The living world to drive through (issue #24). Defaults to the one
  /// this run's own seed draws, so the harness measures exactly what a
  /// player of [seed] meets: the same widths, rain, fog, night, works,
  /// and junctions, with their difficulty fold applied.
  final RunEnvironment? environment;

  /// How often the driver re-reads the road, in seconds. The human lag the
  /// whole estimate rides on.
  final double reactionInterval;

  /// How far ahead the driver plans, in seconds of closing time.
  final double lookaheadSeconds;

  /// The human-error term: how often a threatened driver takes the wrong
  /// escape — dodges into the unsafer lane instead of braking, or vice
  /// versa. This is what couples deaths to the difficulty curve: error is
  /// roughly constant per threatened decision, so hazard rises with
  /// exposure, exactly as it does for people. Zero makes the driver a
  /// perfect machine (and the curve cannot kill it); one makes every
  /// threat fatal.
  final double misjudgeRate;

  /// Simulation tick.
  final double dt;

  // Road geometry, matching TaxiGame and DifficultyCurve. Lane positions
  // are not constants any more (issue #24): the driver reads them from the
  // environment's road geometry every tick.
  static const double roadCenterX = 200;
  static const double spawnDistanceAhead = 500.0;

  // Harness safety caps so a too-easy curve can never hang the batch: a
  // run that reaches these is recorded as survived-at-cap, not simulated
  // forever.
  static const double maxDistancePx = 800000; // 80 km
  static const double maxDrivenSeconds = 2 * 3600;

  /// Road length of one fare slot — the cadence at which the driver leaves
  /// the lanes for a kerb. Mirrors [EndlessCourse.slotLength].
  static const double fareSlotLength = 1400.0;

  /// Runs the shift once. Deterministic in [seed].
  SimulatedRun run() {
    final stats = vehicle ??
        VehicleCatalog.statsFor(VehicleSpritesFallback.defaultVehicleId);
    final random = math.Random(seed ^ 0x1D5EED5);
    final env = environment ?? RunEnvironment(seed: seed);

    // Player state. Forward speed is a magnitude (the taxi drives toward
    // -y); position is the vehicle centre, as in the live game.
    var x = roadCenterX;
    var y = 0.0;
    var speed = 0.0;
    var vx = 0.0;
    var braking = false;

    // The road under the taxi, refreshed every tick (issue #24): lane
    // targets and kerbs follow whatever width the street has here, and
    // rain scales the lateral speed the driver can actually steer at.
    var laneOncomingX = env.roadAt(0).oncomingLaneX;
    var laneSameDirX = env.roadAt(0).sameDirectionLaneX;
    var steerSpeed = stats.steeringSpeed;
    // How long a lane change takes, including the driver's lag — the
    // window other-lane threats are checked against.
    var switchSeconds =
        (laneSameDirX - laneOncomingX).abs() / steerSpeed +
            reactionInterval;

    var targetLaneX = laneSameDirX; // the policy's current intent

    // Kerb positions: the road edge each car can actually reach (the live
    // game clamps the taxi to the road, so the kerb stop is at the clamp,
    // where the pickup zone reaches it).
    var curbLeftX = env.roadAt(0).leftX + stats.width / 2;
    var curbRightX = env.roadAt(0).rightX - stats.width / 2;

    // --- Fare stops: the reason a real driver cannot simply crawl. ---
    // Every fare slot the taxi leaves the traffic lanes for the kerb,
    // boards at walking pace, and merges back — and the merge back into
    // live traffic is where deep runs take their hits. Slot cadence
    // mirrors EndlessCourse.slotLength with per-fare variation.
    var mode = _DriveMode.cruising;
    var curbX = curbLeftX;
    var stopTimer = 0.0;
    var pxSinceStop = 0.0;
    var nextStopGap = fareSlotLength * (0.7 + random.nextDouble() * 0.6);

    // The fare ledger (issue #34): every completed boarding is recorded
    // with the distance it landed at and the time the cycle took, so the
    // earnings harness can price each delivery against its meter.
    final fareStops = <FareStop>[];
    var lastStopPx = 0.0;
    var lastStopSeconds = 0.0;

    final playerHalfW = stats.width * CollisionRules.playerHitboxScale / 2;
    final playerHalfH = stats.height * CollisionRules.playerHitboxScale / 2;

    var lives = 3;
    var stallRemaining = 0.0;
    var spawnTimer = 0.0;
    var policyTimer = 0.0;
    var drivenSeconds = 0.0;
    final crashDistances = <double>[];
    var survived = false;

    final vehicles = <_SimVehicle>[];

    bool laneClear(double laneX, double horizon) =>
        _nearestThreatTime(vehicles, laneX, x, y, speed,
            playerHalfW: playerHalfW, playerHalfH: playerHalfH,
            horizon: horizon) == null;

    // Blind-spot check: would any vehicle in this band of road be at my
    // position while a lane change traverses it? Pulling across a car
    // that overlaps you — or will overlap you before the change completes
    // — side-swipes it, and the lateral closure is crash-grade under the
    // impact-axis rule. Covers cars alongside now and cars that will
    // arrive mid-change from either direction. Drivers look before they
    // move; only the misjudge skips this check.
    bool blindSpotBlocked(double bandX) {
      // Signed moving-gap test: with g the signed gap to the car (behind
      // is positive) and r the rate the gap changes (v.vy + speed), does
      // the gap ever dip inside the pass-through bubble while this change
      // runs? Covers cars approaching from either direction, cars pacing
      // me, and correctly clears cars that are already escaping.
      final horizon = switchSeconds + 0.2;
      for (final v in vehicles) {
        if ((v.x - bandX).abs() >= playerHalfW + v.halfW + 6) {
          continue;
        }
        final bubble = playerHalfH + v.halfH + 10;
        final g = v.y - y;
        final r = v.vy + speed;
        double minGap;
        if (r.abs() < 1) {
          minGap = g.abs(); // pacing me: the gap never opens
        } else {
          final tClose = -g / r;
          if (tClose >= 0 && tClose <= horizon) {
            minGap = 0; // it reaches my position mid-change
          } else {
            minGap = math.min(g.abs(), (g + r * horizon).abs());
          }
        }
        if (minGap < bubble) return true;
      }
      return false;
    }

    // The lateral navigation target the control loop steers toward is
    // derived from the mode each frame: the kerb while stopping or
    // boarding, otherwise the driver's intended lane.

    // --- The reflex driver (runs every [reactionInterval]) ----------------
    void decide() {
      // How far ahead this driver can see right now (issue #24): fog
      // shortens the planning horizon the same way it shortens a real
      // driver's sight line.
      final lookahead =
          lookaheadSeconds * env.visibilityAt(math.max(0.0, -y));

      // Threat against where I actually am, and against where I'm heading.
      var threat = _nearestThreatTime(vehicles, x, x, y, speed,
          playerHalfW: playerHalfW, playerHalfH: playerHalfH,
          horizon: lookahead);
      final threatTarget = _nearestThreatTime(vehicles, targetLaneX, x, y,
          speed,
          playerHalfW: playerHalfW, playerHalfH: playerHalfH,
          horizon: lookahead);
      if (threatTarget != null &&
          (threat == null || threatTarget < threat)) {
        threat = threatTarget;
      }

      // Boarding at the kerb is a commitment: the driver holds position
      // through light pressure, but bails to the nearest lane when the
      // kerb stop itself becomes a threat.
      if (mode == _DriveMode.boarding) {
        if (threat != null && threat < lookahead * 0.8) {
          mode = _DriveMode.reentering;
          targetLaneX = x < roadCenterX ? laneOncomingX : laneSameDirX;
        }
        return;
      }

      if (mode == _DriveMode.toCurb) {
        // Approaching a pickup: hold the kerb line unless the street is
        // hot right now, in which case brake and wait in traffic.
        braking = threat != null && threat < lookahead * 0.8;
        return;
      }

      if (threat != null) {
        // Threatened: the escape is almost always *lateral*. Braking into
        // a head-on only slows the inevitable — the car is coming down MY
        // lane — so the driver changes lanes unless the other lane's own
        // threat arrives before the lane change can complete.
        final other =
            targetLaneX == laneSameDirX ? laneOncomingX : laneSameDirX;
        final otherThreat = _nearestThreatTime(vehicles, other, x, y, speed,
            playerHalfW: playerHalfW, playerHalfH: playerHalfH,
            horizon: lookahead * 1.25);
        if (random.nextDouble() < misjudgeRate) {
          // The wrong read under pressure: commit to the other lane
          // without checking it. Sometimes it happens to be the right
          // escape; sometimes it is exactly the crash.
          targetLaneX = other;
          braking = false;
          mode = _DriveMode.cruising;
          return;
        }
        if ((otherThreat == null || otherThreat > switchSeconds + 0.15) &&
            !blindSpotBlocked(other)) {
          targetLaneX = other;
          braking = false;
        } else {
          // A true squeeze: neither lane can be entered in time. Brake,
          // pace whatever is ahead, and let the stream sort itself out.
          braking = true;
        }
        return;
      }

      braking = false;

      // Not threatened, but stuck behind a slow same-direction blocker in
      // my lane: overtake into a clear lane. Drivers overtake with real
      // margins — a car 2.5 s away in the other lane is accepted, which is
      // exactly how merge-in-front near-misses happen.
      final blocker = _nearestSameDirBlockerGap(vehicles, targetLaneX, y,
          speed, playerHalfW: playerHalfW, playerHalfH: playerHalfH);
      if (blocker != null) {
        final other =
            targetLaneX == laneSameDirX ? laneOncomingX : laneSameDirX;
        if (laneClear(other, lookahead * 2.0) &&
            !blindSpotBlocked(other)) {
          targetLaneX = other;
        }
      }
    }

    while (lives > 0 &&
        -y < maxDistancePx &&
        drivenSeconds < maxDrivenSeconds) {
      if (stallRemaining > 0) {
        // Crash stall: the whole world holds still, exactly as the live
        // game freezes it while the spent life registers.
        stallRemaining -= dt;
        continue;
      }

      // The street under the wheels this tick (issue #24): lane targets
      // and kerbs follow the local width; rain scales the lateral speed
      // full lock can actually steer at.
      final distance = math.max(0.0, -y);
      final road = env.roadAt(distance);
      laneOncomingX = road.oncomingLaneX;
      laneSameDirX = road.sameDirectionLaneX;
      curbLeftX = road.leftX + stats.width / 2;
      curbRightX = road.rightX - stats.width / 2;
      steerSpeed = stats.steeringSpeed * env.gripAt(distance);
      switchSeconds =
          (laneSameDirX - laneOncomingX).abs() / steerSpeed +
              reactionInterval;

      // --- Drive ---
      policyTimer += dt;
      if (policyTimer >= reactionInterval) {
        policyTimer = 0.0;
        decide();
      }

      // --- Fare stops: leave the lanes for the kerb, board, merge back ---
      if (mode == _DriveMode.cruising) {
        pxSinceStop += speed * dt;
        if (pxSinceStop >= nextStopGap) {
          curbX = random.nextBool() ? curbLeftX : curbRightX;
          final approachClear = _nearestThreatTime(vehicles, curbX, x, y,
              speed,
              playerHalfW: playerHalfW, playerHalfH: playerHalfH,
              horizon: lookaheadSeconds * 0.8) ==
                  null &&
              !blindSpotBlocked(curbX);
          if (approachClear) {
            mode = _DriveMode.toCurb;
          } else {
            // Too hot to pull over now: look again in a moment.
            pxSinceStop = nextStopGap - 150;
          }
        }
      } else if (mode == _DriveMode.toCurb) {
        if ((x - curbX).abs() < 3) {
          mode = _DriveMode.boarding;
          stopTimer = 1.0;
          // Boarded: the delivery lands here. The cycle is everything
          // since the previous boarding — the drive to the kerb, the
          // approach, the merge — and that whole span is what a meter is
          // judged against in the earnings harness.
          final distanceNow = math.max(0.0, -y);
          fareStops.add(FareStop(
            distancePx: distanceNow,
            cyclePx: distanceNow - lastStopPx,
            cycleSeconds: drivenSeconds - lastStopSeconds,
          ));
          lastStopPx = distanceNow;
          lastStopSeconds = drivenSeconds;
        }
      } else if (mode == _DriveMode.boarding) {
        stopTimer -= dt;
        if (stopTimer <= 0) {
          // Merge back into whichever lane reads safer right now, and is
          // not blocked alongside (the same look before re-entering a
          // lane a driver does at every real kerb pull-out).
          final leftThreat = _nearestThreatTime(vehicles, laneOncomingX, x,
              y, speed,
              playerHalfW: playerHalfW, playerHalfH: playerHalfH,
              horizon: lookaheadSeconds);
          final rightThreat = _nearestThreatTime(vehicles, laneSameDirX, x,
              y, speed,
              playerHalfW: playerHalfW, playerHalfH: playerHalfH,
              horizon: lookaheadSeconds);
          final leftBlocked = blindSpotBlocked(laneOncomingX);
          final rightBlocked = blindSpotBlocked(laneSameDirX);
          if (leftBlocked && rightBlocked) {
            // Both lanes have someone alongside: wait at the kerb until
            // one clears. Staying put beats pulling into a fender.
            stopTimer = 0.4;
          } else {
            mode = _DriveMode.reentering;
            var goRight = (leftThreat == null && rightThreat != null) ||
                (leftThreat != null &&
                    rightThreat != null &&
                    rightThreat > leftThreat);
            if (leftBlocked && !rightBlocked) goRight = true;
            if (rightBlocked && !leftBlocked) goRight = false;
            targetLaneX = goRight ? laneSameDirX : laneOncomingX;
          }
        }
      } else if (mode == _DriveMode.reentering) {
        if ((x - targetLaneX).abs() < 3) {
          mode = _DriveMode.cruising;
          pxSinceStop = 0.0;
          nextStopGap = fareSlotLength * (0.7 + random.nextDouble() * 0.6);
        }
      }

      // Following reflex first: never rear-end a slow blocker — match its
      // pace while closing inside a second of gap. Re-checked every frame;
      // it is a reflex, not a decision.
      final followCap = _followingSpeedCap(vehicles, x, y, speed,
          playerHalfW: playerHalfW, playerHalfH: playerHalfH);

      if (mode == _DriveMode.boarding) {
        // The taxi stops for its passenger.
        speed = math.max(0.0, speed - PlayerVehicle.deceleration * dt);
      } else if (braking) {
        // A held brake means "shed speed", but never to a standstill behind
        // a blocker — a driver caught between lanes paces the car ahead and
        // waits for the stream to open, it does not sit dead in the road
        // for oncoming traffic to find.
        final pace = followCap ?? 0.0;
        if (speed > pace) {
          speed = math.max(pace, speed - PlayerVehicle.deceleration * dt);
        } else if (speed < pace) {
          speed = math.min(pace, speed + stats.acceleration * dt);
        }
      } else {
        speed = math.min(stats.topSpeed, speed + stats.acceleration * dt);
        if (followCap != null && speed > followCap) speed = followCap;
      }

      // Lateral: travel toward the navigation target at full steering
      // lock — the kerb while stopping or boarding, otherwise the
      // driver's intended lane.
      final navTarget =
          mode == _DriveMode.toCurb || mode == _DriveMode.boarding
              ? curbX
              : targetLaneX;
      final dx = navTarget - x;
      final maxStep = steerSpeed * dt;
      vx = dx.abs() <= maxStep ? 0.0 : (dx > 0 ? steerSpeed : -steerSpeed);
      x += dx.abs() <= maxStep ? dx : maxStep * (dx > 0 ? 1 : -1);

      y -= speed * dt;

      // --- Spawn, exactly as TrafficSpawner.distanceBased does ---
      // The environment-aware profile (issue #24): the curve's anchors
      // over the local lane layout, with the weather/night modifier
      // already folded into the pressure.
      final profile = env.trafficAt(distance);
      spawnTimer += dt;
      if (spawnTimer >= profile.spawnInterval) {
        spawnTimer = 0.0;
        final spawnDistance = distance + spawnDistanceAhead;
        // Same clearances the live spawner keeps (issue #24): no traffic
        // materialises on a cross street or inside a work zone's closed
        // lanes. Skipping after the roll leaves the RNG stream untouched.
        final junction = env.isIntersectionAt(spawnDistance);
        for (final lane in profile.lanes) {
          if (junction) continue;
          if (env.isLaneBlockedAt(spawnDistance, lane.laneX)) continue;
          if (random.nextDouble() <= lane.spawnProbability) {
            var laneSpeed = lane.speedRange.min +
                random.nextDouble() *
                    (lane.speedRange.max - lane.speedRange.min);
            if (!lane.oncoming) laneSpeed *= 0.5;
            const types = TrafficVehicleType.values;
            final type = types[random.nextInt(types.length)];
            vehicles.add(_SimVehicle(
              x: lane.laneX,
              y: y - spawnDistanceAhead,
              speed: laneSpeed * type.speedMultiplier,
              oncoming: lane.oncoming,
              type: type,
            ));
          }
        }
      }

      // --- Move traffic ---
      for (final v in vehicles) {
        v.y += v.vy * dt;
      }
      // Cull: off the bottom of the view (oncoming, past the player), or
      // beyond the same-direction path length (3000 px) ahead of its spawn
      // point — the live game's two despawn reasons.
      vehicles.removeWhere((v) => v.y > y + 1000 || v.y < v.spawnY - 3000);

      // --- Contacts: one ruling per vehicle ---
      // Episode-scoped arming alone (rulingActive) re-arms the moment the
      // scrape pushback separates the bodies and the closing vehicle
      // re-overlaps a frame or two later — an oncoming vehicle could
      // bulldoze the body backwards off the start one scrape at a time
      // (issue #42). A contacted vehicle never rules again, mirroring
      // the live game's TrafficVehicle.contactedPlayer guard.
      for (final v in vehicles) {
        final overlaps = (v.x - x).abs() < playerHalfW + v.halfW &&
            (v.y - y).abs() < playerHalfH + v.halfH;
        if (!overlaps) {
          v.rulingActive = false;
          continue;
        }
        if (v.rulingActive || v.contacted) continue;
        v.rulingActive = true;
        v.contacted = true;

        var axisX = x - v.x;
        var axisY = y - v.y;
        final len = math.sqrt(axisX * axisX + axisY * axisY);
        if (len < 0.001) {
          axisX = 0;
          axisY = -1;
        } else {
          axisX /= len;
          axisY /= len;
        }
        final relX = vx - 0.0;
        final relY = -speed - v.vy;
        final into =
            math.max(0.0, -(relX * axisX + relY * axisY));
        // Fault half of the ruling (issue #58): how much of that closing
        // is the taxi's own doing. The taxi's velocity is (vx, -speed); a
        // contact the traffic initiated — the reflex driver boxed in and
        // rammed from behind — must cost speed, never a life.
        final mine = -(vx * axisX - speed * axisY);
        final severity = CollisionRules.severityFor(into, mine);

        if (severity == ContactSeverity.crash) {
          lives--;
          crashDistances.add(math.max(0.0, -y));
          // The live game freezes the world for the crash stall, and the
          // touch lifts: the taxi coasts (throttle released) when it
          // resumes. The struck vehicle keeps rolling with no further
          // ruling while the overlap lasts. The freeze also means at most
          // ONE crash can rule per frame — a second simultaneous contact
          // finds the world inactive and goes unruled — so the ruling
          // pass stops here.
          if (lives > 0) {
            stallRemaining = 1.2;
            braking = true;
            break;
          }
          break;
        } else {
          // Scrape: keep a third of the speed, push out of overlap along
          // the impact axis — the live game's scrape response, verbatim.
          speed *= CollisionRules.scrapeSpeedKeep;
          x += axisX * CollisionRules.scrapePushback;
          y += axisY * CollisionRules.scrapePushback;
        }
      }

      drivenSeconds += dt;
    }

    if (lives > 0) survived = true;
    return SimulatedRun(
      seed: seed,
      distancePx: math.max(0.0, -y),
      drivenSeconds: drivenSeconds,
      crashDistancesPx: List.unmodifiable(crashDistances),
      survived: survived,
      fareStops: List.unmodifiable(fareStops),
    );
  }

  /// Seconds until the nearest vehicle that threatens a body at [bodyX]
  /// would reach it — null when nothing is closing within [horizon]. A
  /// vehicle threatens if it is ahead, laterally inside the combined half
  /// widths (plus a small margin — careful drivers respect near-misses),
  /// and closing.
  static double? _nearestThreatTime(
    List<_SimVehicle> vehicles,
    double bodyX,
    double playerX,
    double playerY,
    double playerSpeed, {
    required double playerHalfW,
    required double playerHalfH,
    required double horizon,
  }) {
    const lateralMargin = 2.0;
    double? best;
    for (final v in vehicles) {
      if (v.y >= playerY) continue; // behind; only ahead is a threat
      if ((v.x - bodyX).abs() >=
          playerHalfW + v.halfW + lateralMargin) {
        continue;
      }
      final gap =
          (playerY - v.y) - (playerHalfH + v.halfH);
      // Closing rate along the road: player velocity minus traffic
      // velocity, i.e. forward speed plus the car's vy (positive for
      // oncoming, negative for same-direction — so same-direction traffic
      // only closes while the player is actually faster).
      final closing = playerSpeed + v.vy;
      if (closing <= 0) continue;
      final t = gap / closing;
      if (t <= horizon && (best == null || t < best)) best = t;
    }
    return best;
  }

  /// Gap to the nearest slow same-direction blocker straight ahead in a
  /// lane, when it is actually blocking (close enough to matter) — null
  /// otherwise.
  static double? _nearestSameDirBlockerGap(
    List<_SimVehicle> vehicles,
    double laneX,
    double playerY,
    double playerSpeed, {
    required double playerHalfW,
    required double playerHalfH,
  }) {
    double? best;
    for (final v in vehicles) {
      if (v.oncoming || v.vy >= 0) continue;
      if (v.y >= playerY) continue;
      if ((v.x - laneX).abs() >= playerHalfW + v.halfW) continue;
      final gap = (playerY - v.y) - (playerHalfH + v.halfH);
      if (gap > 160) continue; // far enough to not matter yet
      if (best == null || gap < best) best = gap;
    }
    return best;
  }

  /// The speed cap the following reflex imposes: the pace of the closest
  /// same-direction vehicle ahead in my band of road when I am closing on
  /// it inside a second of gap. Null when nobody is there to rear-end.
  static double? _followingSpeedCap(
    List<_SimVehicle> vehicles,
    double playerX,
    double playerY,
    double playerSpeed, {
    required double playerHalfW,
    required double playerHalfH,
  }) {
    double? cap;
    for (final v in vehicles) {
      if (v.oncoming || v.vy >= 0) continue;
      if (v.y >= playerY) continue;
      if ((v.x - playerX).abs() >= playerHalfW + v.halfW) continue;
      final gap = (playerY - v.y) - (playerHalfH + v.halfH);
      final closing = playerSpeed + v.vy; // v.vy is negative (moving up)
      if (closing <= 0) continue;
      if (gap > closing * 1.0) continue;
      final theirPace = -v.vy;
      if (cap == null || theirPace < cap) cap = theirPace;
    }
    return cap;
  }
}

/// The starter-vehicle id without importing the sprite registry (which
/// drags rendering concerns into this harness). Matches
/// `VehicleSprites.defaultVehicleId`; the catalog itself falls back to the
/// same car for unknown ids.
class VehicleSpritesFallback {
  static const String defaultVehicleId = 'taxi_yellow';
}

/// One simulated traffic vehicle: an axis-aligned box with a vertical
/// velocity, plus the overlap-episode flag that mirrors the live game's
/// one-ruling-per-touch rule.
class _SimVehicle {
  _SimVehicle({
    required this.x,
    required this.y,
    required double speed,
    required this.oncoming,
    required this.type,
  })  : vy = oncoming ? speed : -speed,
        spawnY = y,
        halfW = type.size.x * CollisionRules.trafficHitboxScale / 2,
        halfH = type.size.y * CollisionRules.trafficHitboxScale / 2;

  double x;
  double y;
  final double vy;
  final double halfW;
  final double halfH;
  final bool oncoming;
  final double spawnY;
  final TrafficVehicleType type;
  bool rulingActive = false;

  /// True once this vehicle has ever ruled on a contact (issue #42):
  /// [rulingActive] resets when the overlap ends, and a closing vehicle
  /// re-establishes overlap within a frame or two of the scrape
  /// pushback — so episode-scoped arming alone let an oncoming vehicle
  /// bulldoze the body backwards, one scrape per re-contact. This flag
  /// never resets, mirroring the live game's
  /// `TrafficVehicle.contactedPlayer`: one ruling per vehicle, then
  /// traffic drives on through.
  bool contacted = false;
}

/// What the simulated driver is doing: cruising the lanes, pulling over to
/// a kerb, boarding a passenger, or merging back into traffic. The stops
/// are the game's own rhythm — every fare slot — and the merge back is the
/// exposure a pure survival policy would never take.
enum _DriveMode { cruising, toCurb, boarding, reentering }
