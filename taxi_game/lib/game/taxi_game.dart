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
import 'systems/difficulty_curve.dart';
import 'systems/endless_course.dart';
import 'systems/endless_fare_controller.dart';
import 'systems/bank_prompt.dart';
import 'systems/fare_chain.dart';
import 'systems/road_chunk_manager.dart';
import 'systems/impact_fx.dart';
import '../services/game_state_service.dart';
import '../services/level_loader_service.dart';

/// Main game class that manages the entire game loop and components
class TaxiGame extends FlameGame
    with HasCollisionDetection, TapCallbacks, KeyboardEvents {
  TaxiGame({
    required this.levelLoader,
    required this.gameState,
    this.endlessSeed,
  }) : super(
          camera: CameraComponent.withFixedResolution(width: 400, height: 800),
        );

  final LevelLoaderService levelLoader;
  final GameStateService gameState;

  /// When non-null the game runs an endless procedural run (issue #11)
  /// instead of a hand-made level: recycled road chunks, continuously
  /// generated fares, and distance-curve traffic. The same seed always
  /// reproduces the identical course.
  final int? endlessSeed;

  bool get isEndless => endlessSeed != null;

  /// The seed of the endless run in progress; null in level mode.
  int get runSeed => endlessSeed!;

  late PlayerVehicle player;
  late GameLevel currentLevel;
  late TrafficSpawner trafficSpawner;

  /// Endless-run systems (issue #11); null in level mode.
  EndlessCourse? course;
  EndlessFareController? fareController;
  RoadChunkManager? roadChunks;

  /// The fare chain — score, multiplier, and the live fare countdowns
  /// (issue #12). Run-local: reset with every level or endless run.
  final FareChain fareChain = FareChain();

  /// Score accrued this run or level (issue #12).
  int get score => fareChain.score;

  /// The timed bank-or-push choice offered at every endless dropoff
  /// (issue #13). Inactive in level mode — levels settle at completion.
  final BankPrompt bankPrompt = BankPrompt();

  /// What the most recent bank paid out, in coins, for the banked-shift
  /// panel. Null until a shift is banked; cleared when a new run starts.
  int? lastBankedScore;

  /// How far into the shift the taxi had driven when it was banked, in px.
  double lastBankedDistance = 0;

  List<PassengerData> passengers = [];
  int passengersDelivered = 0;

  bool isGameActive = false;
  int currentLevelNumber = 1;

  /// How far into an endless run the taxi has driven, in px. Zero in
  /// level mode.
  double get runDistance =>
      (isEndless && isGameActive) ? math.max(0.0, -player.position.y) : 0.0;

  /// Fares delivered so far in this endless run.
  int get faresDelivered => fareController?.faresDelivered ?? 0;

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

    // Endless runs skip the level system entirely (issue #11).
    if (endlessSeed != null) {
      await startEndlessRun(seed: endlessSeed!);
      return;
    }

    // If the save points past the last level (all levels beaten),
    // replay the final level instead of silently falling back.
    var levelNumber = gameState.currentLevel;
    if (!await levelLoader.levelExists(levelNumber)) {
      final total = await levelLoader.getTotalLevels();
      levelNumber = total > 0 ? total : 1;
    }
    await loadLevel(levelNumber);
  }

  /// Starts an endless procedural run (issue #11): recycled road chunks,
  /// fares generated continuously from the seeded course, and traffic on
  /// the distance curve. The same [seed] always builds the same run.
  Future<void> startEndlessRun({required int seed}) async {
    isGameActive = false;
    lastImpact = null;

    // Clear any impact juice left over from the previous run (issue #7).
    shake.reset();
    hitStop.reset();
    _pendingFailureOverlay = false;
    _speedLines?.intensity = 0;
    _applyShake(0); // restores the viewport position, dropping any shake

    course = EndlessCourse(seed: seed);
    passengers.clear();
    passengersDelivered = 0;
    fareChain.reset();
    _dismissBankPrompt();
    lastBankedScore = null;
    lastBankedDistance = 0;

    // Tear down the previous run, if any.
    world.removeAll(world.children.toList());

    // The endless road: chunks are added ahead of the camera and culled
    // behind it forever (issue #11).
    final chunks = RoadChunkManager();
    roadChunks = chunks;
    world.add(chunks);

    // The player starts at y 0 and only drives upward (negative y); chunk
    // indices below 0 already cover the road behind the start line.
    player = PlayerVehicle(
      startPosition: Vector2(roadCenterX, 0),
      vehicleId: gameState.selectedVehicle,
    );
    world.add(player);

    // Camera: locked horizontally on the road, follows the taxi vertically.
    camera.viewfinder.position = Vector2(roadCenterX, 0);
    camera.follow(player, verticalOnly: true);

    trafficSpawner = TrafficSpawner.distanceBased(
      profileOf: DifficultyCurve.trafficForDistance,
      distanceOf: () => runDistance,
      // A spawner RNG derived from the run seed — never Dart's default
      // clock-seeded Random, or replays of one seed would diverge.
      random: math.Random(seed ^ 0x5EEDCAB5),
    );
    world.add(trafficSpawner);

    fareController = EndlessFareController(
      course: course!,
      onPickup: _onPassengerPickup,
      onDropoff: _onEndlessFareDelivered,
    );
    world.add(fareController!);

    isGameActive = true;
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
    fareChain.reset();
    _dismissBankPrompt();

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

    // The meter starts running: this passenger's countdown begins now
    // (issue #12).
    fareChain.startFare(passenger);

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

    // Score the delivery against the fare chain (issue #12); coins are
    // unchanged — the chain is mastery on top of the existing economy.
    fareChain.completeFare(passenger, fareValue: passenger.reward);

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

  /// Delivery in an endless run (issue #11): the fare pays out on the
  /// spot — there is no level completion to settle up at.
  void _onEndlessFareDelivered(PassengerData passenger) {
    player.hasPassenger = fareController?.hasActivePickup ?? false;

    // Score the delivery against the fare chain (issue #12); the coin
    // payout below is unchanged.
    fareChain.completeFare(passenger, fareValue: passenger.reward);

    // Blue-and-gold burst: the fare is paid (issue #7).
    world.add(BurstParticles(
      position: passenger.dropoffLocation,
      colors: ImpactFxPalettes.dropoff,
    ));
    // Coins fly from the dropoff to the HUD counter, and the wallet is
    // credited immediately — per-fare, the endless economy's unit.
    for (var i = 0; i < 3; i++) {
      world.add(CoinPop(
        startPosition: passenger.dropoffLocation,
        delay: 0.06 * i,
      ));
    }
    gameState.addCoins(passenger.reward);

    // Every completed dropoff asks the question (issue #13): bank the
    // score and end the shift, or push on at an increased multiplier. The
    // prompt rides above the live game — the street keeps moving under it.
    _offerBankOrPush();
  }

  // --- Bank or push (issue #13) -------------------------------------------

  /// Puts the bank-or-push choice on screen after an endless dropoff.
  void _offerBankOrPush() {
    bankPrompt.offer();
    overlays.add('bankOrPush');
  }

  /// The choice is gone: resolved, superseded by a crash, or left behind
  /// by a restart. Only ever tears down — consequences are applied by the
  /// caller that resolved the prompt.
  void _dismissBankPrompt() {
    bankPrompt.dismiss();
    overlays.remove('bankOrPush');
  }

  /// Bank: the accumulated score becomes permanent — paid into the wallet
  /// 1:1 in coins — and the shift ends. Everything unbanked would have
  /// been forfeited by ending the shift any other way (a crash, or
  /// later, the third life — issue #14), which is exactly the pressure
  /// the choice is designed to apply.
  void bankShift() {
    if (bankPrompt.bank() == null) return;
    _endShiftAsBanked();
  }

  /// Push on: keep driving at the increased multiplier. The window
  /// closing without a choice lands here too — pushing is the default,
  /// and it must pay the same whether it was chosen or merely allowed.
  void pushOn() {
    if (bankPrompt.push() == null) return;
    _applyPushBonus();
  }

  void _applyPushBonus() {
    fareChain.applyPushBonus();
    _dismissBankPrompt();
  }

  /// Freezes the shift and pays the banked score out. The score itself
  /// stays readable for the panel until the next run resets it.
  void _endShiftAsBanked() {
    lastBankedScore = fareChain.score;
    lastBankedDistance = runDistance;

    isGameActive = false;
    _freezePlayer();
    trafficSpawner.pause();
    _dismissBankPrompt();

    gameState.addCoins(lastBankedScore!);
    overlays.add('shiftBanked');
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

  /// Restarts the current level from scratch (after a crash). In an
  /// endless run the same seed restarts the same course (issue #11).
  void restartLevel() {
    overlays.remove('levelFailed');
    overlays.remove('levelComplete');
    overlays.remove('shiftBanked');
    if (isEndless) {
      startEndlessRun(seed: runSeed);
      return;
    }
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

    // A crash forfeits everything unbanked (issue #13): the open choice
    // dies with the run, and whatever the chain held stays unbanked.
    _dismissBankPrompt();

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

    // Fare countdowns tick only while the run is live (issue #12): a
    // crash, the completion panel, or a pause freezes the meter with
    // everything else. (Pause stops this whole method; overlays set
    // isGameActive false first.)
    if (isGameActive) {
      fareChain.update(dt);

      // The bank-or-push window ticks with the same clock (issue #13).
      // When it closes without a choice the player rides on — push is
      // the default, so the game never stops dead waiting for an answer.
      if (bankPrompt.update(dt) == BankDecision.pushed) {
        _applyPushBonus();
      }
    }

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
