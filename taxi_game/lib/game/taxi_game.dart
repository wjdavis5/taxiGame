import 'dart:math' as math;

import 'package:flame/camera.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'components/player_vehicle.dart';
import 'components/road_segment.dart';
import 'components/background.dart';
import 'components/traffic_spawner.dart';
import 'components/pickup_zone.dart';
import 'components/dropoff_zone.dart';
import 'components/scrape_marker.dart';
import 'components/burst_particles.dart';
import 'components/coin_pop.dart';
import 'components/speed_lines.dart';
import 'levels/level.dart';
import '../models/passenger_data.dart';
import 'systems/collision_rules.dart';
import 'systems/impact_fx.dart';
import '../services/game_state_service.dart';
import '../services/level_loader_service.dart';

/// Main game class that manages the entire game loop and components
class TaxiGame extends FlameGame
    with HasCollisionDetection, TapCallbacks, KeyboardEvents {
  TaxiGame({
    required this.levelLoader,
    required this.gameState,
  }) : super(
          camera: CameraComponent.withFixedResolution(width: 400, height: 800),
        );

  final LevelLoaderService levelLoader;
  final GameStateService gameState;

  late PlayerVehicle player;
  late GameLevel currentLevel;
  late TrafficSpawner trafficSpawner;

  List<PassengerData> passengers = [];
  int passengersDelivered = 0;

  bool isGameActive = false;
  int currentLevelNumber = 1;

  /// Telemetry for the most recent player–traffic contact — a scrape or a
  /// crash — so overlays and logs can explain exactly what happened
  /// (issue #6 contact legibility). Cleared whenever a level loads.
  CrashReport? lastImpact;

  /// Rate-limits scrape feedback so a jittering grind cannot spam markers.
  double _scrapeMarkerCooldown = 0;

  // --- Impact juice (issue #7) -------------------------------------------
  /// Decaying screen-shake envelope, driven onto the camera viewport in
  /// [update]. Crashes shake hard (scaled to impact speed), scrapes jolt.
  final ShakeEnvelope shake = ShakeEnvelope();

  /// The brief world freeze at a crash.
  final HitStop hitStop = HitStop();

  /// Screen-space speed lines over the windshield; null until [onLoad].
  SpeedLines? _speedLines;

  /// Shake offset currently baked into [camera.viewport.position], so the
  /// next frame can add a fresh delta on top of the untouched position.
  final Vector2 _appliedShakeOffset = Vector2.zero();

  /// Set when a crash defers its failure overlay until the hit-stop ends
  /// (issue #7): the impact lands first, then the panel explains it.
  bool _pendingFailureOverlay = false;

  // The road spans x 100..300 in world coordinates (center 200, width 200).
  static const double roadCenterX = 200;
  static const double roadWidth = 200;

  // Touch position tracking for steering
  Vector2? _touchPosition;

  @override
  Color backgroundColor() => const Color(0xFF1A1A1A); // Letterbox outside the viewport

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Static sky/scenery behind the scrolling world
    camera.backdrop.add(Background());

    // Speed lines live on the viewport: screen-space, drawn over the
    // world but under the Flutter HUD (issue #7).
    _speedLines = SpeedLines();
    camera.viewport.add(_speedLines!);

    // If the save points past the last level (all levels beaten),
    // replay the final level instead of silently falling back.
    var levelNumber = gameState.currentLevel;
    if (!await levelLoader.levelExists(levelNumber)) {
      final total = await levelLoader.getTotalLevels();
      levelNumber = total > 0 ? total : 1;
    }
    await loadLevel(levelNumber);
  }

  /// Loads the given level, replacing whatever was on screen before.
  Future<void> loadLevel(int levelNumber) async {
    isGameActive = false;
    currentLevelNumber = levelNumber;
    lastImpact = null;

    // Clear any impact juice left over from the previous run (issue #7).
    shake.reset();
    hitStop.reset();
    _pendingFailureOverlay = false;
    _speedLines?.intensity = 0;
    _applyShake(0); // restores the viewport position, dropping any shake

    currentLevel = await levelLoader.loadLevel(levelNumber);

    // Tear down the previous level, if any.
    world.removeAll(world.children.toList());

    // The player can only drive forward (up), so it must start below every
    // pickup point. Dropoffs extend upward into negative y.
    final allPoints = [
      ...currentLevel.pickupPoints,
      ...currentLevel.dropoffPoints,
    ];
    final lowestPointY =
        allPoints.map((p) => p.y).fold(0.0, math.max); // largest y
    final highestPointY =
        allPoints.map((p) => p.y).fold(0.0, math.min); // smallest y
    final playerStartY = lowestPointY + 250;

    // Road long enough to cover the whole route with margin on both ends.
    final roadTop = highestPointY - 900;
    final roadBottom = playerStartY + 500;
    world.add(RoadSegment(
      position: Vector2(roadCenterX, roadTop),
      length: roadBottom - roadTop,
    ));

    // Render the vehicle selected in the garage/save data.
    player = PlayerVehicle(
      startPosition: Vector2(roadCenterX, playerStartY),
      vehicleId: gameState.selectedVehicle,
    );
    world.add(player);

    // Camera: locked horizontally on the road, follows the taxi vertically.
    camera.viewfinder.position = Vector2(roadCenterX, playerStartY);
    camera.follow(player, verticalOnly: true);

    trafficSpawner = TrafficSpawner(pattern: currentLevel.trafficPattern);
    world.add(trafficSpawner);

    _createPassengers();

    isGameActive = true;
  }

  void _createPassengers() {
    passengers.clear();
    passengersDelivered = 0;

    // Create a passenger for each pickup/dropoff pair in the level
    for (int i = 0; i < currentLevel.pickupPoints.length; i++) {
      final pickupPoint = currentLevel.pickupPoints[i];
      final dropoffPoint = i < currentLevel.dropoffPoints.length
          ? currentLevel.dropoffPoints[i]
          : currentLevel.dropoffPoints.last;

      final passenger = PassengerData(
        id: 'passenger_$i',
        pickupLocation: pickupPoint,
        dropoffLocation: dropoffPoint,
        reward: currentLevel.coinReward ~/ currentLevel.pickupPoints.length,
      );

      passengers.add(passenger);

      world.add(PickupZone(
        position: pickupPoint,
        passenger: passenger,
        onPickup: () => _onPassengerPickup(passenger),
      ));

      world.add(DropoffZone(
        position: dropoffPoint,
        passenger: passenger,
        onDropoff: () => _onPassengerDropoff(passenger),
      ));
    }
  }

  void _onPassengerPickup(PassengerData passenger) {
    player.hasPassenger = true;

    // Green burst: a passenger boarded (issue #7).
    world.add(BurstParticles(
      position: passenger.pickupLocation,
      colors: ImpactFxPalettes.pickup,
    ));
  }

  void _onPassengerDropoff(PassengerData passenger) {
    passengersDelivered++;
    player.hasPassenger =
        passengers.any((p) => p.isPickedUp && !p.isDelivered);

    // Blue-and-gold burst: the fare is paid (issue #7).
    world.add(BurstParticles(
      position: passenger.dropoffLocation,
      colors: ImpactFxPalettes.dropoff,
    ));
    // Coins fly from the dropoff to the HUD counter. The total itself
    // still updates at level completion — the economy is unchanged; this
    // only makes the award visible.
    for (var i = 0; i < 3; i++) {
      world.add(CoinPop(
        startPosition: passenger.dropoffLocation,
        delay: 0.06 * i,
      ));
    }

    if (passengersDelivered >= passengers.length) {
      _completeLevel();
    }
  }

  void _completeLevel() {
    isGameActive = false;
    _freezePlayer();
    trafficSpawner.pause();

    // A volley of coins streams from the taxi to the HUD counter as the
    // reward lands (issue #7).
    for (var i = 0; i < 6; i++) {
      world.add(CoinPop(
        startPosition: player.position,
        delay: 0.05 * i,
      ));
    }

    // Award coins and unlock the next level.
    gameState.completeLevel(currentLevelNumber, currentLevel.coinReward);

    overlays.add('levelComplete');
  }

  /// Restarts the current level from scratch (after a crash).
  void restartLevel() {
    overlays.remove('levelFailed');
    overlays.remove('levelComplete');
    loadLevel(currentLevelNumber);
  }

  /// Advances to the next level. Returns false if there is none.
  Future<bool> startNextLevel() async {
    final next = currentLevelNumber + 1;
    if (!await levelLoader.levelExists(next)) {
      return false;
    }
    overlays.remove('levelComplete');
    await loadLevel(next);
    return true;
  }

  /// Ends the level after a real collision. [report] carries the full
  /// telemetry of the contact for the failure overlay and logs.
  void onLevelFailed([CrashReport? report]) {
    if (!isGameActive) return;
    lastImpact = report;
    if (report != null) {
      debugPrint('[crash] ${report.explanation}');
      _spawnCrashFx(report);
    }
    isGameActive = false;
    _freezePlayer();
    trafficSpawner.pause();

    // The failure overlay waits out the hit-stop (issue #7): the sparks,
    // shake, and freeze land first, then the panel explains what happened.
    if (hitStop.isActive) {
      _pendingFailureOverlay = true;
    } else {
      overlays.add('levelFailed');
    }
  }

  /// Crash juice (issue #7): a hot spark burst at the contact point,
  /// a hit-stop, and a shake scaled to how fast the impact closed.
  void _spawnCrashFx(CrashReport report) {
    world.add(BurstParticles(
      position: report.contactPoint.clone(),
      colors: ImpactFxPalettes.crash,
      count: 18,
      maxSpeed: 240,
      lifetime: 0.6,
    ));
    shake.trigger(
      ImpactFx.crashShakeMagnitudeFor(report.closingSpeedAlongImpact),
      duration: ImpactFx.crashShakeDuration,
    );
    hitStop.trigger();
  }

  /// Records a low-speed glancing scrape: no life is lost, the player was
  /// already slowed by [PlayerVehicle]; this only surfaces feedback naming
  /// what was hit.
  void onScrape(CrashReport report) {
    lastImpact = report;

    // Sparks and a short jolt — enough to feel the sheet metal, without
    // crowding out the crash feedback (issue #7).
    world.add(BurstParticles(
      position: report.contactPoint.clone(),
      colors: ImpactFxPalettes.scrape,
      count: 6,
      maxSpeed: 130,
      lifetime: 0.35,
    ));
    shake.trigger(
      ImpactFx.scrapeShakeMagnitude,
      duration: ImpactFx.scrapeShakeDuration,
    );

    if (_scrapeMarkerCooldown <= 0) {
      _scrapeMarkerCooldown = 0.4;
      world.add(ScrapeMarker(
        position: report.contactPoint.clone(),
        vehicleKind: report.vehicleKind,
      ));
    }
  }

  @override
  void update(double dt) {
    if (hitStop.isActive) {
      // Hit-stop (issue #7): the world holds still for a beat — no
      // component updates, no collisions — while the shake keeps jittering
      // the frozen frame.
      hitStop.update(dt);
      _applyShake(dt);
      if (!hitStop.isActive && _pendingFailureOverlay) {
        _pendingFailureOverlay = false;
        overlays.add('levelFailed');
      }
      return;
    }

    super.update(dt);
    _applyShake(dt);

    // Speed lines track the taxi's forward speed so velocity reads
    // without looking at a number (issue #7).
    if (_speedLines != null) {
      _speedLines!.intensity = isGameActive
          ? ImpactFx.speedLineIntensityFor(-player.velocity.y)
          : 0;
    }

    if (_scrapeMarkerCooldown > 0) {
      _scrapeMarkerCooldown = math.max(0.0, _scrapeMarkerCooldown - dt);
    }
  }

  /// Applies one frame of screen shake as a delta on the viewport
  /// position, so it never fights the camera's follow logic (which owns
  /// the viewfinder) and leaves no residue when it decays.
  void _applyShake(double dt) {
    final base = camera.viewport.position - _appliedShakeOffset;
    _appliedShakeOffset.setFrom(shake.update(dt));
    camera.viewport.position = base + _appliedShakeOffset;
  }

  void _freezePlayer() {
    _touchPosition = null;
    player.stopAccelerating();
    player.setSteering(0);
    // The run is over; the windshield effect ends with it (issue #7).
    _speedLines?.intensity = 0;
  }

  void pauseGame() {
    paused = true;
    overlays.add('pauseMenu');
  }

  void resumeGame() {
    paused = false;
    overlays.remove('pauseMenu');
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (isGameActive) {
      _touchPosition = event.canvasPosition;
      player.startAccelerating();
      _updateSteeringFromTouch();
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    _touchPosition = null;
    player.stopAccelerating();
    player.setSteering(0);
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    super.onTapCancel(event);
    _touchPosition = null;
    player.stopAccelerating();
    player.setSteering(0);
  }

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    if (!isGameActive) return KeyEventResult.ignored;

    final accelerate = keysPressed.contains(LogicalKeyboardKey.arrowUp) ||
        keysPressed.contains(LogicalKeyboardKey.keyW) ||
        keysPressed.contains(LogicalKeyboardKey.space);
    final left = keysPressed.contains(LogicalKeyboardKey.arrowLeft) ||
        keysPressed.contains(LogicalKeyboardKey.keyA);
    final right = keysPressed.contains(LogicalKeyboardKey.arrowRight) ||
        keysPressed.contains(LogicalKeyboardKey.keyD);

    // Keyboard input only overrides "stop" when no touch is active, so
    // touch and keyboard can be used together.
    if (accelerate) {
      player.startAccelerating();
    } else if (_touchPosition == null) {
      player.stopAccelerating();
    }
    if (left != right) {
      player.setSteering(left ? -1 : 1);
    } else if (_touchPosition == null) {
      player.setSteering(0);
    }
    return KeyEventResult.handled;
  }

  void _updateSteeringFromTouch() {
    if (_touchPosition == null || !isGameActive) return;

    // Steer based on touch position relative to the screen center:
    // left half steers left, right half steers right.
    final screenCenter = canvasSize.x / 2;
    final deltaX = _touchPosition!.x - screenCenter;
    final steeringInput = (deltaX / (canvasSize.x / 2)).clamp(-1.0, 1.0);
    player.setSteering(steeringInput);
  }
}
