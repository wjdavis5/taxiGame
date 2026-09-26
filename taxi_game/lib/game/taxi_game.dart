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
import '../models/run_record.dart';
import 'systems/collision_rules.dart';
import 'systems/difficulty_curve.dart';
import 'systems/endless_course.dart';
import 'systems/endless_fare_controller.dart';
import 'systems/bank_prompt.dart';
import 'systems/fare_chain.dart';
import 'systems/lives.dart';
import 'systems/run_summary.dart';
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

  /// When non-null the game was constructed to run an endless procedural
  /// run (issue #11) instead of a hand-made level: recycled road chunks,
  /// continuously generated fares, and distance-curve traffic. The same
  /// seed always reproduces the identical course.
  final int? endlessSeed;

  /// The seed of the endless run in progress; null in level mode. Set by
  /// [startEndlessRun] — which is also how the tutorial handoff (issue
  /// #16) starts a shift on a game constructed for the ladder — so it,
  /// not the constructor field alone, is what [runSeed] reads back.
  int? _activeRunSeed;

  /// True while an endless run is in progress: either the game was built
  /// for one, or — after the tutorial ladder's last rung (issue #16) — a
  /// level-mode game handed off to one via [startFirstShift]. Everything
  /// that branches on the mode (crash flow, banking, the HUD) reads this,
  /// so the handoff really does change modes.
  bool get isEndless => endlessSeed != null || course != null;

  /// The seed of the endless run in progress; null in level mode.
  int get runSeed => _activeRunSeed ?? endlessSeed!;

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

  /// The shift's failure budget — three lives, one spent per crash
  /// (issue #14). Endless runs only: the tutorial ladder still fails a
  /// level on the first crash. Run-local, like the fare chain.
  final LivesTracker lives = LivesTracker();

  /// How long the world stays frozen after a non-fatal endless crash
  /// (issue #14): long enough for the lost life to register on the HUD,
  /// short enough to keep the shift's flow. Runs after the crash
  /// hit-stop has played the impact.
  static const double crashStallSeconds = 1.2;

  /// Score accrued this run or level (issue #12).
  int get score => fareChain.score;

  /// A seed for a brand-new shift, from the clock. Each shift gets a
  /// fresh seed, so each draws a fresh city (issue #11).
  static int freshSeed() => DateTime.now().microsecondsSinceEpoch & 0x3FFFFFFF;

  /// The timed bank-or-push choice offered at every endless dropoff
  /// (issue #13). Inactive in level mode — levels settle at completion.
  final BankPrompt bankPrompt = BankPrompt();

  /// What the most recent bank paid out, in coins, for the banked-shift
  /// panel. Null until a shift is banked; cleared when a new run starts.
  int? lastBankedScore;

  /// The settled record of the shift that just ended (issue #15) — the
  /// run-summary panel reads it. Set the instant the shift ends, before
  /// its overlay goes up, and cleared when the next run starts.
  RunSummary? lastRunSummary;

  /// Coins credited to the wallet during the current run (issue #15):
  /// each delivered fare's base reward, plus the banked payout if the
  /// shift ends in a bank. The summary's "earned" line.
  int _runCoinsEarned = 0;

  /// How far into the current shift each life was lost, in world px, in
  /// loss order (issue #17) — the "where" of the stats record. One entry
  /// per spent life; cleared with every fresh shift.
  final List<double> _lifeLossDistancesPx = <double>[];

  /// Seconds the current shift has been actively driven (issue #17):
  /// world-update time while the run is live. Crash hit-stops and stalls
  /// freeze the world and this clock with it, so the recorded duration
  /// measures driving, not dead time.
  double _runDrivenSeconds = 0;

  List<PassengerData> passengers = [];
  int passengersDelivered = 0;

  /// True once the current level or run has built its [player]. Guards
  /// [runDistance], which reads the player's position, so the HUD can
  /// poll it before the world exists. The old [isGameActive] guard made
  /// the distance read zero through a crash stall (issue #14) — the
  /// badge would have flashed 0 m every time a life was spent.
  bool _playerReady = false;

  bool isGameActive = false;
  int currentLevelNumber = 1;

  /// Whether a level follows the one on screen (issue #16). Set at every
  /// [loadLevel]; false past the last rung of the tutorial ladder, which
  /// is how the completion panel knows to offer the Endless handoff
  /// instead of a NEXT LEVEL button that dead-ends.
  bool hasNextLevel = false;

  /// How far into an endless run the taxi has driven, in px. Zero in
  /// level mode. Stays readable while a crash stall holds the world (the
  /// run is paused, not rewound), so the HUD's distance badge does not
  /// flash zero.
  double get runDistance =>
      (isEndless && _playerReady) ? math.max(0.0, -player.position.y) : 0.0;

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

  /// The overlay a crash deferred until the hit-stop ends (issue #7):
  /// 'levelFailed' for the tutorial ladder, 'shiftWrecked' for the third
  /// endless crash (issue #14). The impact lands first, then the panel
  /// explains it. Null when nothing is waiting.
  String? _pendingOverlayName;

  /// Seconds of crash stall left (issue #14); zero when not stalling.
  /// While it counts down the whole world holds still — no movement, no
  /// collisions, no fare clocks — then the shift resumes.
  double _crashStallRemaining = 0;

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

    // A save pointing past the last level means the tutorial ladder is
    // finished (issue #16): the ladder's whole job is to hand the player
    // to Endless, so PLAY opens onto a fresh shift — never an endless
    // replay of level 10.
    if (!await levelLoader.levelExists(gameState.currentLevel)) {
      await startEndlessRun(seed: freshSeed());
      return;
    }
    await loadLevel(gameState.currentLevel);
  }

  /// Starts an endless procedural run (issue #11): recycled road chunks,
  /// fares generated continuously from the seeded course, and traffic on
  /// the distance curve. The same [seed] always builds the same run.
  Future<void> startEndlessRun({required int seed}) async {
    isGameActive = false;
    lastImpact = null;
    _activeRunSeed = seed;

    // Clear any impact juice left over from the previous run (issue #7),
    // along with the lives budget and any crash stall it was mid-way
    // through (issue #14): a fresh shift starts with three lives and no
    // debt from the last one.
    shake.reset();
    hitStop.reset();
    _pendingOverlayName = null;
    _crashStallRemaining = 0;
    lives.reset();
    _speedLines?.intensity = 0;
    _applyShake(0); // restores the viewport position, dropping any shake

    course = EndlessCourse(seed: seed);
    passengers.clear();
    passengersDelivered = 0;
    fareChain.reset();
    _dismissBankPrompt();
    lastBankedScore = null;
    lastRunSummary = null;
    _runCoinsEarned = 0;
    _lifeLossDistancesPx.clear();
    _runDrivenSeconds = 0;

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
    _playerReady = true;

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

    // Clear any impact juice left over from the previous level (issue
    // #7). The lives budget resets with it: a level has no failure
    // budget — its first crash still fails it — but the counter must
    // never carry a spent budget across modes (issue #14).
    shake.reset();
    hitStop.reset();
    _pendingOverlayName = null;
    _crashStallRemaining = 0;
    lives.reset();
    _speedLines?.intensity = 0;
    _applyShake(0); // restores the viewport position, dropping any shake

    currentLevel = await levelLoader.loadLevel(levelNumber);

    // A level run has no endless systems. Clear any a previous run left
    // behind: [isEndless] is what routes crashes, banking, and the HUD,
    // and a stale course would keep the level wearing the shift's rules
    // (issue #16 lets one game hand off between the two modes).
    course = null;
    fareController = null;
    roadChunks = null;
    _activeRunSeed = null;

    // Whether another rung follows this one (issue #16): the completion
    // panel reads it to offer NEXT LEVEL, or — past the last rung — the
    // handoff to Endless.
    hasNextLevel = await levelLoader.levelExists(levelNumber + 1);

    fareChain.reset();
    _dismissBankPrompt();
    // A bank's payout line belongs to the run that earned it (issue #16
    // teaches banking inside the ladder, and the completion panel shows
    // the payout) — never to the level loaded after it.
    lastBankedScore = null;

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
    _playerReady = true;

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
    } else if (currentLevel.bankPromptEnabled) {
      // The banking lesson (issue #16): on the levels that teach it, every
      // dropoff still leaving fares undelivered asks the same timed
      // question an endless dropoff does — bank the score and settle for
      // a sure payout, or push on at an increased multiplier with the
      // score at risk. The prompt rides above the live level either way.
      _offerBankOrPush();
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
    _runCoinsEarned += passenger.reward;

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
  /// 1:1 in coins — and the run ends. Everything unbanked would have been
  /// forfeited by ending the run any other way (a crash, or later, the
  /// third life — issue #14), which is exactly the pressure the choice is
  /// designed to apply.
  ///
  /// In a level that teaches banking (issue #16) the run is the level, so
  /// banking settles it as a success — [_bankAndCompleteLevel].
  void bankShift() {
    if (bankPrompt.bank() == null) return;
    if (isEndless) {
      _endShiftAsBanked();
    } else {
      _bankAndCompleteLevel();
    }
  }

  /// Banking inside the tutorial ladder (issue #16): the same payout a
  /// bank makes in an endless shift — the chain score converted to coins
  /// 1:1 — and the level settles as a success, unlocking the next rung.
  /// The fares left undelivered are the trade the lesson is about: a sure
  /// payout now against a bigger, riskier one had the player pushed on.
  void _bankAndCompleteLevel() {
    lastBankedScore = fareChain.score;
    gameState.addCoins(lastBankedScore!);
    _completeLevel();
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

    isGameActive = false;
    _freezePlayer();
    trafficSpawner.pause();
    _dismissBankPrompt();

    gameState.addCoins(lastBankedScore!);
    _runCoinsEarned += lastBankedScore!;
    _finalizeRunSummary(ShiftOutcome.banked);
    overlays.add('shiftBanked');
  }

  /// Settles the shift that just ended into [lastRunSummary] (issue #15):
  /// snapshots the final numbers and records the score against the
  /// personal best. Called before the summary overlay goes up, so the
  /// panel always reads a complete snapshot.
  ///
  /// Only ever reached from the endless endings — a banked or wrecked
  /// shift — which is also when the shift enters the on-device history
  /// (issue #17): the same snapshot feeds the stats screen, the sole
  /// tuning instrument in a game with no analytics.
  void _finalizeRunSummary(ShiftOutcome outcome) {
    final previousBest = gameState.endlessBestScore;
    final isPersonalBest = gameState.recordEndlessScore(fareChain.score);
    lastRunSummary = RunSummary(
      outcome: outcome,
      score: fareChain.score,
      bestChain: fareChain.bestMultiplier,
      faresDelivered: faresDelivered,
      distancePx: runDistance,
      coinsEarned: _runCoinsEarned,
      isPersonalBest: isPersonalBest,
      previousBest: previousBest,
    );
    gameState.recordEndlessRun(RunRecord(
      endedAtMs: DateTime.now().millisecondsSinceEpoch,
      distancePx: runDistance,
      score: fareChain.score,
      faresDelivered: faresDelivered,
      longestChain: fareChain.bestMultiplier,
      livesLost: _lifeLossDistancesPx.length,
      lifeLossDistancesPx: List.of(_lifeLossDistancesPx),
      banked: outcome == ShiftOutcome.banked,
      durationSeconds: _runDrivenSeconds,
    ));
  }

  /// The run summary's DRIVE AGAIN (issue #15): tears down whichever
  /// end-of-shift panel is up and puts a fresh shift — three new lives, a
  /// new seed, a new city — on the same road immediately. The retry never
  /// routes through the menu; the friction between "I died" and "I'm
  /// driving again" is where retention is won or lost.
  void retryShift() {
    overlays.remove('shiftBanked');
    overlays.remove('shiftWrecked');
    startEndlessRun(seed: freshSeed());
  }

  void _completeLevel() {
    isGameActive = false;
    _freezePlayer();
    trafficSpawner.pause();

    // Completing the level supersedes any open bank-or-push choice
    // (issue #16): the last fare's delivery can land while a prompt from
    // the previous one is still up, and a settled level owes no payout on
    // top of its completion.
    _dismissBankPrompt();

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
    overlays.remove('shiftWrecked');
    if (isEndless) {
      startEndlessRun(seed: runSeed);
      return;
    }
    loadLevel(currentLevelNumber);
  }

  /// Advances to the next level. Returns false past the last rung of the
  /// tutorial ladder (issue #16) — there, the completion panel offers the
  /// Endless handoff via [startFirstShift] instead.
  Future<bool> startNextLevel() async {
    final next = currentLevelNumber + 1;
    if (!await levelLoader.levelExists(next)) {
      return false;
    }
    overlays.remove('levelComplete');
    await loadLevel(next);
    return true;
  }

  /// The tutorial handoff (issue #16): the ladder is finished, so the
  /// completion panel's button starts the player's first endless shift —
  /// in the same session, on the same road, with no trip back to the
  /// menu. The lesson levels taught in safe isolation now run for real:
  /// three lives, a live bank, and a score worth protecting.
  void startFirstShift() {
    overlays.remove('levelComplete');
    startEndlessRun(seed: freshSeed());
  }

  /// A judged player–traffic crash (issues #6, #14). Endless runs route
  /// through the three-strike flow — a life down, the shift resumes,
  /// until the third crash ends it. The tutorial ladder keeps the
  /// level-fail behaviour: its first crash fails the level.
  void onCrash([CrashReport? report]) {
    if (isEndless) {
      _onEndlessCrash(report);
    } else {
      onLevelFailed(report);
    }
  }

  /// Ends the level after a real collision. [report] carries the full
  /// telemetry of the contact for the failure overlay and logs. Level
  /// mode only — endless runs are crashed through [onCrash] (issue #14).
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
      _pendingOverlayName = 'levelFailed';
    } else {
      overlays.add('levelFailed');
    }
  }

  // --- Three strikes (issue #14) ------------------------------------------

  /// A crash in an endless run: one life down and the chain multiplier
  /// back to 1x, then a brief stall before the shift resumes. The third
  /// crash ends the shift and forfeits everything unbanked.
  void _onEndlessCrash([CrashReport? report]) {
    if (!isGameActive) return;
    lastImpact = report;

    // The open bank-or-push choice dies with the touch (issue #13) —
    // and unlike a bank, nothing is paid out: the score survives the
    // crash but stays unbanked and at risk, which is exactly what the
    // remaining lives are now protecting.
    _dismissBankPrompt();

    if (report != null) {
      debugPrint('[crash] ${report.explanation}');
      _spawnCrashFx(report);
    }

    lives.spend();
    fareChain.breakChain();
    // Where the life went, for the stats history (issue #17): the distance
    // the shift had covered when this crash cost a life.
    _lifeLossDistancesPx.add(runDistance);

    if (lives.isExhausted) {
      _endShiftAsWrecked();
    } else {
      _stallAfterCrash();
    }
  }

  /// Holds the whole world still for [crashStallSeconds] — long enough
  /// for the spent life to register — then hands the shift back.
  void _stallAfterCrash() {
    isGameActive = false;
    _freezePlayer();
    _crashStallRemaining = crashStallSeconds;
  }

  /// Hands the shift back after the stall: same road, same fares, same
  /// unbanked score — now riding on a broken 1x chain.
  void _resumeAfterCrashStall() {
    _crashStallRemaining = 0;
    isGameActive = true;
  }

  /// The third crash: the shift ends and everything unbanked is forfeit
  /// (issue #14) — the outcome banking at a dropoff exists to escape.
  /// Nothing is paid into the wallet here; the forfeited score is only
  /// ever read, by the wreck panel, to say what was lost.
  void _endShiftAsWrecked() {
    isGameActive = false;
    _freezePlayer();
    trafficSpawner.pause();
    _finalizeRunSummary(ShiftOutcome.wrecked);

    // The wreck panel waits out the hit-stop (issue #7): the impact
    // lands first, then the forfeit is explained.
    if (hitStop.isActive) {
      _pendingOverlayName = 'shiftWrecked';
    } else {
      overlays.add('shiftWrecked');
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
      final overlay = _pendingOverlayName;
      if (!hitStop.isActive && overlay != null) {
        _pendingOverlayName = null;
        overlays.add(overlay);
      }
      return;
    }

    // Crash stall (issue #14): after a non-fatal endless crash the whole
    // world holds still while the spent life registers on the HUD, then
    // the shift resumes where it left off.
    if (_crashStallRemaining > 0) {
      _crashStallRemaining = math.max(0.0, _crashStallRemaining - dt);
      _applyShake(dt);
      if (_crashStallRemaining <= 0) {
        _resumeAfterCrashStall();
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

      // The stats clock (issue #17) runs with the same one: only time the
      // shift is actually live counts as driven.
      if (isEndless) {
        _runDrivenSeconds += dt;
      }

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
