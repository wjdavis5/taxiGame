import 'dart:math' as math;

import 'package:flame/camera.dart';
import 'package:flame/components.dart' show PositionComponent;
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'components/player_vehicle.dart';
import 'components/road_segment.dart';
import 'components/background.dart';
import 'components/environment_overlay.dart';
import 'components/ghost_car.dart';
import 'components/traffic_spawner.dart';
import 'components/traffic_vehicle.dart';
import 'components/pickup_zone.dart';
import 'components/dropoff_zone.dart';
import 'components/scrape_marker.dart';
import 'components/burst_particles.dart';
import 'components/close_call_pop.dart';
import 'components/coin_pop.dart';
import 'components/life_lost_pop.dart';
import 'components/speed_lines.dart';
import 'components/virtual_stick.dart';
import 'levels/level.dart';
import '../models/passenger_data.dart';
import '../models/run_record.dart';
import '../models/daily_result.dart';
import 'systems/collision_rules.dart';
import 'systems/daily_shift.dart';
import 'systems/difficulty_curve.dart';
import 'systems/endless_course.dart';
import 'systems/endless_fare_controller.dart';
import 'systems/bank_prompt.dart';
import 'systems/fare_chain.dart';
import 'systems/ghost_replay.dart';
import 'systems/lives.dart';
import 'systems/near_miss.dart';
import 'systems/run_environment.dart';
import 'systems/run_summary.dart';
import 'systems/road_chunk_manager.dart';
import 'systems/impact_fx.dart';
import 'systems/world_origin.dart';
import '../services/audio_service.dart';
import '../services/game_state_service.dart';
import '../services/haptics_service.dart';
import '../services/level_loader_service.dart';

/// Why a tutorial level failed (issue #112): a judged crash, or a fare
/// the level still needs stranded behind the one-way cab. The failure
/// panel words itself from this. Endless runs never fail this way —
/// their stranded dropoffs are relocated instead (issue #28) — so only
/// [TaxiGame.onLevelFailed] and the missed-fare check ever set it.
enum LevelFailReason { crash, fareMissed }

/// Main game class that manages the entire game loop and components
class TaxiGame extends FlameGame
    with HasCollisionDetection, KeyboardEvents {
  TaxiGame({
    required this.levelLoader,
    required this.gameState,
    this.audio,
    this.haptics,
    this.endlessSeed,
    this.isDailyShift = false,
    this.isGhostRace = false,
  }) : super(
          camera: CameraComponent.withFixedResolution(width: 400, height: 800),
        );

  final LevelLoaderService levelLoader;
  final GameStateService gameState;

  /// The audio service (issue #4); null in the headless tests, which run the
  /// game without any audio graph. Every call site is a null-aware poke —
  /// the game never depends on sound existing.
  final AudioService? audio;

  /// The haptics service (issue #5); null in the headless tests, which run
  /// the game without any platform channel. Every call site is a null-aware
  /// poke — the game never depends on the phone being able to buzz. The
  /// enabled-gate itself lives in the service, synced from the save's
  /// vibration setting by the composition root.
  final HapticsService? haptics;

  /// When non-null the game was constructed to run an endless procedural
  /// run (issue #11) instead of a hand-made level: recycled road chunks,
  /// continuously generated fares, and distance-curve traffic. The same
  /// seed always reproduces the identical course.
  final int? endlessSeed;

  /// True when this game is running today's Daily Shift (issue #19): an
  /// endless run whose seed comes from the calendar date, so every player
  /// in the world drives the identical course. Its one attempt is spent
  /// when the shift ends — [retryShift] clears this flag, because the
  /// drive that follows a finished daily is free play on a fresh seed,
  /// never a replay of the day's course.
  bool isDailyShift;

  /// True when this game is a ghost race (issue #20): a replay of the
  /// day's shared course — the daily's seed — run *after* the day's one
  /// scoring attempt is spent, against the stored best run rendered as
  /// [ghostCar]. The race never touches the settled daily result (the
  /// data layer's first-wins rule holds); it only offers its trace to
  /// the ghost, which keeps the better score. Like [isDailyShift],
  /// cleared by [retryShift] — a drive on from here is free play.
  bool isGhostRace;

  /// The seed of the endless run in progress; null in level mode. Set by
  /// [startEndlessRun] — which is also how the tutorial handoff (issue
  /// #16) starts a shift on a game constructed for the ladder — so it,
  /// not the constructor field alone, is what [runSeed] reads back.
  int? _activeRunSeed;

  /// The calendar day this Daily Shift is playing (issue #19), as a
  /// 'yyyy-MM-dd' date key. Pinned when the run starts, so a shift still
  /// on the road at midnight records to the day it was played. Null for
  /// any non-daily run.
  String? _dailyDateKey;

  /// The calendar day the run on the road belongs to ('yyyy-MM-dd'),
  /// pinned at run start: the Daily Shift's day (issue #19), and by the
  /// same rule the day of any run on that course — a ghost race included
  /// (issue #20). Null in free play. The score card (issue #22) dates
  /// itself from this, so a shift finished after midnight still shares
  /// the day its course was seeded from.
  String? get runDateKey => _dailyDateKey ?? _ghostDateKey;

  /// The calendar day the ghost rules apply to on this run (issue #20):
  /// pinned — with the same day-at-start rule as [_dailyDateKey] — for
  /// any run on the daily course, whether the scoring daily itself or a
  /// [isGhostRace] replay. Both the recording and the replay key on it.
  /// Null for any run that is not on the daily course, which is how the
  /// ghost stays attached to the Daily Shift only.
  String? _ghostDateKey;

  /// Samples the player's path while [_ghostDateKey] is set (issue #20),
  /// on the driven-time clock. Cleared with every run start.
  GhostRecorder? _ghostRecorder;

  /// The translucent replay of the stored best run for [_ghostDateKey]
  /// (issue #20); null when this run has no ghost to race — free play,
  /// or the day's first run before any trace exists for it.
  GhostCar? ghostCar;

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

  /// The living world of the endless run in progress (issue #24): road
  /// geometry, weather, time of day, works, and cross streets, all seeded
  /// from the run's seed so the Daily Shift reproduces its sky exactly
  /// like its fares. Null in level mode, which keeps the classic fixed
  /// daylight street.
  RunEnvironment? environment;

  /// Lateral grip in effect right now, 1.0 on a dry street — the player
  /// car scales its full-lock steering by this (issue #24). Sampled from
  /// the environment every frame; 1.0 in level mode.
  double gripMultiplier = 1.0;

  /// How far the world has folded back toward the origin so far this run
  /// (issue #30): the y delta applied to every world component at each
  /// [WorldOrigin.period] of true road. World y stays small so the
  /// canvas's single-precision transforms never degrade the road into
  /// bare sky; true distance is always `worldShift − world y`. Zero in
  /// level mode — levels are finite roads.
  double _worldShift = 0;

  /// How many folds have been applied: the [WorldOrigin.period] multiple
  /// the world's coordinates are canonical for.
  int _rebaseCount = 0;

  /// The current world fold, in px. Read by everything that converts
  /// between world y and true distance (see [WorldOrigin]).
  double get worldShift => _worldShift;

  /// How dark it is right now, 0..1 (issue #24). Traffic reads it to
  /// light its headlights; level mode keeps it at 0.
  double darkness = 0;

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

  /// The largest dt any single frame may consume, in seconds (issue #36).
  ///
  /// Flame's ticker measures real time, and when the engine's game loop
  /// is stopped and started around a backgrounding — or its lifecycle
  /// event is late and the ticker keeps counting through the absence —
  /// the first frame back can carry the whole absent gap in one dt. That
  /// one frame would burn fare countdowns by the absent seconds, let the
  /// bank-or-push window silently resolve to push, and move the taxi far
  /// enough to tunnel straight through a traffic hitbox. Clamped here at
  /// the top of [update], no frame advances any dt-driven system by more
  /// than this; a backgrounded gap is discarded, never simulated. 1/15 s
  /// sits well above the 60 Hz frame budget, so ordinary judder on a slow
  /// device is never clipped.
  static const double maxUpdateDelta = 1 / 15;

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
  /// world-update time while the run is live. Crash hit-stop and stalls
  /// freeze the world and this clock with it, so the recorded duration
  /// measures driving, not dead time.
  double _runDrivenSeconds = 0;

  /// Wall-clock time the current run has been live (both modes), for the
  /// diagnostics heartbeat's timestamp.
  double _liveRunSeconds = 0;

  /// Interval accumulator for the diagnostics heartbeat: one line of
  /// where the run stands every [heartbeatInterval] of live play, so a
  /// hard kill on a device leaves a trail of "how far it got" behind it.
  double _heartbeatSeconds = 0;

  /// How often the heartbeat logs, in seconds of live play.
  static const double heartbeatInterval = 5.0;

  List<PassengerData> passengers = [];
  int passengersDelivered = 0;

  /// True once the current level or run has built its [player]. Guards
  /// [runDistance], which reads the player's position, so the HUD can
  /// poll it before the world exists. The old [isGameActive] guard made
  /// the distance read zero through a crash stall (issue #14) — the
  /// badge would have flashed 0 m every time a life was spent.
  bool _playerReady = false;

  /// Whether the player vehicle exists yet. Public because the viewport
  /// overlays (issue #24) read the taxi's position to place their light
  /// and fog cutouts, and must fall back to the viewfinder before the
  /// world exists.
  bool get isPlayerReady => _playerReady;

  bool isGameActive = false;

  /// True once this run has settled and stays so until the next one
  /// starts ([startEndlessRun] or [loadLevel], which both reset it). The
  /// shared *terminal* flag: the end-of-shift summaries (banked or
  /// wrecked, issue #14) and — since issue #71 — the level endings
  /// (completed or failed) all set it, because an ended run is ended
  /// whatever panel explains it. The summary owns the screen from that
  /// moment: pausing stacks a second decision under it, the pause menu's
  /// BANK & QUIT used to pay the already-banked score out again on every
  /// tap — unlimited coins, including from a wreck's forfeited score
  /// (issue #52) — and the world that keeps ticking underneath could
  /// still "deliver" a fare the ending had already forfeited, whose
  /// prompt then paid out a second time through BANK (issue #71).
  /// [pauseGame], [bankFromPause], [bankShift], and the zone callbacks
  /// all no-op while it is set, and the HUD's pause button stands down
  /// (its polling widget reads this).
  bool _shiftOver = false;

  /// Whether the shift on screen has ended and its summary owns the
  /// screen (issue #52). See [_shiftOver].
  bool get isShiftOver => _shiftOver;

  int currentLevelNumber = 1;

  /// The loaded ladder level's authored name ('First Ride', 'Bank It'),
  /// or null in endless mode and before a level loads — the ten names
  /// are the ladder's flavor, and the HUD and completion panel surface
  /// them. A plain nullable field, not `currentLevel.name`: `currentLevel`
  /// is late and the HUD reads before the world exists.
  String? currentLevelName;

  /// Whether a level follows the one on screen (issue #16). Set at every
  /// [loadLevel]; false past the last rung of the tutorial ladder, which
  /// is how the completion panel knows to offer the Endless handoff
  /// instead of a NEXT LEVEL button that dead-ends.
  bool hasNextLevel = false;

  /// How far into an endless run the taxi has driven, in px. Zero in
  /// level mode. Stays readable while a crash stall holds the world (the
  /// run is paused, not rewound), so the HUD's distance badge does not
  /// flash zero. True distance, not world y: the fold (issue #30) keeps
  /// the world's coordinates small, this keeps count of the road.
  double get runDistance =>
      (isEndless && _playerReady)
          ? math.max(0.0, worldShift - player.position.y)
          : 0.0;

  /// Fares delivered so far in this endless run.
  int get faresDelivered => fareController?.faresDelivered ?? 0;

  /// The fare currently on offer ahead of the taxi (issue #25) — a
  /// waiting passenger whose kind the player can read and decline before
  /// committing to the kerb. Null when nothing waitable is on screen, and
  /// always null outside an endless run: a level's pickups are mandatory
  /// objectives, so there is nothing there to decline.
  PassengerData? get currentFareOffer => fareController?.offerOnScreen;

  /// Declines the current fare offer (issue #25): its zones come off the
  /// street, no meter starts, nothing is paid and nothing is penalised —
  /// the cost is only the fare itself. Returns false when there is
  /// nothing to decline.
  bool declineCurrentOffer() {
    final offer = currentFareOffer;
    if (offer == null) return false;
    return fareController!.declineOffer(offer);
  }

  /// How far ahead (+) or behind (−) the ghost is, in metres on the
  /// same scale the HUD's distance badge uses (issue #20). Null when
  /// there is no ghost on the road — the HUD hides its badge rather
  /// than showing a gap to nothing.
  double? get ghostGapMetres {
    final ghost = ghostCar;
    if (ghost == null || !isEndless) return null;
    return (ghost.position.y - player.position.y) /
        RunSummary.pixelsPerMetre;
  }

  /// Telemetry for the most recent player–traffic contact — a scrape or a
  /// crash — so overlays and logs can explain exactly what happened
  /// (issue #6 contact legibility). Cleared whenever a level loads.
  CrashReport? lastImpact;

  /// Why the level failed, when it has (issue #112): set by every level
  /// failure path, cleared by every run start, read by the failure panel
  /// to word a stranded fare differently from a collision.
  LevelFailReason? lastFailReason;

  /// Rate-limits scrape feedback so a grinding push-match cannot spam
  /// particles, shake, sound, and markers at frame rate (issue #42).
  double _scrapeFeedbackCooldown = 0;

  // --- Impact juice (issue #7) -------------------------------------------
  /// Decaying screen-shake envelope, driven onto the camera viewport in
  /// [update]. Crashes shake hard (scaled to impact speed), scrapes jolt.
  final ShakeEnvelope shake = ShakeEnvelope();

  /// The brief world freeze at a crash.
  final HitStop hitStop = HitStop();

  /// Screen-space speed lines over the windshield; null until [onLoad].
  SpeedLines? _speedLines;

  /// The weather-and-darkness windshield layer (issue #24); null until
  /// [onLoad]. Draws nothing until the run environment says otherwise.
  EnvironmentOverlay? _environmentOverlay;

  /// The sky/scenery behind the world; kept so the day-night arc (issue
  /// #24) can re-tint it as the run drives on.
  final Background _background = Background();

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

  /// The current crash's spark burst (issue #106): the frozen branches
  /// of [update] drain its mount and tick it, so the impact reads at
  /// the moment it happens instead of 1.3 s late. Replaced by the next
  /// crash's burst — a crash cannot be re-judged while the world is
  /// frozen ([isGameActive] is down for the whole hit-stop and stall),
  /// so nothing can clobber a live reference mid-freeze.
  BurstParticles? _crashSparks;

  /// True through the whole hit-stop-plus-stall window of a survivable
  /// crash (issue #105): [_crashStallRemaining] is set the instant the
  /// crash is judged and zeroed on every other path — run start, level
  /// load, the banked ending, the resume itself, the wreck — so it is
  /// faithful for exactly the freeze the shift comes back from. The
  /// stick's claim gate reads it: a thumb that *lands* mid-freeze is
  /// the thumb the resume must hand the stick to, while every other
  /// not-live state (a terminal ending, an overlay before the run)
  /// still refuses the claim.
  bool get isCrashStall => _crashStallRemaining > 0;

  // The road spans x 100..300 in world coordinates (center 200, width 200).
  static const double roadCenterX = 200;
  static const double roadWidth = 200;

  /// How far past a level's topmost zone the street keeps going (issue
  /// #31). A level's road is finite — that is what makes it a course —
  /// but its end must read as the end of a street, not a cliff into the
  /// void: this much surface beyond the last zone, a barrier, stop line,
  /// and crossing painted on it (see `RoadSegment`), and the taxi clamped
  /// one car length inside it (see [levelRoadTopY]).
  static const double levelRoadEndMargin = 800.0;

  /// How far up the road the level camera's centre runs ahead of the taxi
  /// (issue #45). The ladder's start is pinned to each level's lowest
  /// marker — 250 px below it, a constant of [loadLevel] — so a camera
  /// centred on the taxi itself always framed the first pickup exactly
  /// 150 px below the view top: inside the ~110 px HUD chip band, where
  /// the marker hid under a chip (the ×1 on level 1, SCORE 0 on 2 and 3).
  /// Editing the level JSON cannot move it — the start derives from the
  /// lowest point, so the 150 px is structural — but leading the camera
  /// does: the marker opens 250 px below the view top, clear of the
  /// chips, with the authored geometry, the first-drive distance, and
  /// the endless framing all untouched.
  static const double levelCameraLead = 100.0;

  /// World y of the level road's top end (issue #31): the line the taxi
  /// noses against at the course's finish. Null outside level mode — an
  /// endless run's road is infinite, and its coordinate space belongs to
  /// the world fold (issue #30), so nothing may clamp it.
  double? levelRoadTopY;

  /// The point the level camera follows (issue #45): the taxi's position
  /// nudged up the road by [levelCameraLead]. Pure data — never mounted,
  /// never rendered; [update] mirrors the taxi into it right before the
  /// component tree ticks. Null outside level mode; recreated by every
  /// [loadLevel].
  _LevelCameraLead? _levelCameraLead;

  /// The one-thumb relative-drag virtual stick (issue #29), the sole
  /// touch input: mounted on the viewport in [onLoad]. Null only before
  /// that — handlers guard rather than assume.
  VirtualStick? _virtualStick;

  /// Exposed for tests and the keyboard guard.
  VirtualStick? get virtualStick => _virtualStick;

  /// The stick just received its first real touch this save (issue #37):
  /// the thumb landed in the lower half exactly where the hint said it
  /// would, so the hint has done its job — take it down and record the
  /// dismissal for good. Called on every accepted stick engagement, but
  /// the save write happens only once: [GameStateService
  /// .dismissControlHint] is idempotent and removing a non-active
  /// overlay is a no-op.
  ///
  /// The hint itself is offered by the game screen (issue #37 puts it on
  /// the first game start of an undismissed save); the game only ever
  /// stands it down.
  void onStickEngaged() {
    overlays.remove('controlHint');
    gameState.dismissControlHint();
  }

  @override
  Color backgroundColor() => const Color(0xFF1A1A1A); // Letterbox outside the viewport

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Static sky/scenery behind the scrolling world
    camera.backdrop.add(_background);

    // Speed lines live on the viewport: screen-space, drawn over the
    // world but under the Flutter HUD (issue #7).
    _speedLines = SpeedLines();
    camera.viewport.add(_speedLines!);

    // The windshield layer (issue #24): darkness with the taxi's
    // headlights cut out, fog, and rain streaks. Added after the speed
    // lines so weather reads over them; the HUD still rides above both.
    _environmentOverlay = EnvironmentOverlay();
    camera.viewport.add(_environmentOverlay!);

    // The virtual stick (issue #29): screen-space control surface, drawn
    // over the world and the weather, under the Flutter HUD. It mounts
    // its own drag-event dispatcher on the game.
    _virtualStick = VirtualStick();
    camera.viewport.add(_virtualStick!);

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

  /// Retires the previous run's or level's world wholesale (issue #32).
  ///
  /// A teardown sweep of [world.children] can never be complete. Flame
  /// defers tree changes: a component added to a mounted parent during a
  /// tick — a road chunk the chunk manager synced in the shift's final
  /// frames, a fare zone, a traffic car — is *queued* to mount at the next
  /// tick's start, and until then it is not in [world.children] at all. A
  /// retry tapped between ticks would sweep only the children it can see,
  /// and the queued straggler would mount straight into the fresh run's
  /// world afterwards: previous-run geometry nobody tracks and nothing
  /// culls, composited into the new run's first frames. When the ended
  /// shift had crossed a fold, that straggler's canonical position
  /// (computed under the old shift) lands exactly on the fresh run's
  /// opening street — the sheared two-worlds frame TestFlight caught.
  ///
  /// Retiring the world itself closes the race by construction. The
  /// camera re-points at the fresh world synchronously, so the old one
  /// can never render again, and anything still queued to mount mounts
  /// into a world that is already detached — it can only ever come back
  /// on the tree as a child of the retired one, and is carried out with
  /// it when that removal processes.
  void _clearWorld() {
    world = World();
  }

  /// Starts an endless procedural run (issue #11): recycled road chunks,
  /// fares generated continuously from the seeded course, and traffic on
  /// the distance curve. The same [seed] always builds the same run.
  Future<void> startEndlessRun({required int seed}) async {
    isGameActive = false;
    lastImpact = null;
    lastFailReason = null;
    _activeRunSeed = seed;
    // A daily shift pins the day it started on (issue #19): a run still
    // being driven at midnight belongs to the course — and the result —
    // of the day it set out on.
    _dailyDateKey = isDailyShift ? DailyShift.todayKey : null;
    // A ghost race replays the day's course too (issue #20), so it pins
    // the recording-and-replay day by the same rule.
    _ghostDateKey = (isDailyShift || isGhostRace) ? DailyShift.todayKey : null;
    _ghostRecorder =
        _ghostDateKey != null ? GhostRecorder() : null;

    // Clear any impact juice left over from the previous run (issue #7),
    // along with the lives budget and any crash stall it was mid-way
    // through (issue #14): a fresh shift starts with three lives and no
    // debt from the last one. The fresh shift also re-arms the pause
    // menu (issue #52): the previous summary no longer owns the screen.
    shake.reset();
    hitStop.reset();
    _pendingOverlayName = null;
    _crashStallRemaining = 0;
    _shiftOver = false;
    lives.reset();
    _speedLines?.intensity = 0;
    _applyShake(0); // restores the viewport position, dropping any shake

    // The living world (issue #24): the same seed draws the same streets,
    // weather, and sky as it draws fares — the Daily Shift's course and
    // its mood are one reproducible thing. The course reads the
    // environment to put passengers on the kerbs the road really has.
    // A fresh shift also starts a fresh world frame (issue #30): no folds
    // applied, world y and true distance the same thing again.
    environment = RunEnvironment(seed: seed);
    course = EndlessCourse(seed: seed, environment: environment);
    debugPrint('[run] endless start seed=$seed daily=$isDailyShift '
        'ghost=$isGhostRace');
    _liveRunSeconds = 0;
    _heartbeatSeconds = 0;
    _worldShift = 0;
    _rebaseCount = 0;
    // The endless road has no end (issue #11): whatever level street was
    // here before — the tutorial handoff (#16) drives this path — owed
    // its clamp to the level road's finish, and that finish is gone.
    levelRoadTopY = null;
    // Its camera framing goes with it (issue #45): the endless shift
    // centres straight on the taxi, no level lead.
    _levelCameraLead = null;
    // And no ladder name either: the shift is not a level.
    currentLevelName = null;
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
    _clearWorld();

    // The endless road: chunks are added ahead of the camera and culled
    // behind it forever (issue #11). Chunks render the run's own geometry
    // and carry its work zones (issue #24).
    final chunks = RoadChunkManager(environment: environment);
    roadChunks = chunks;
    world.add(chunks);

    // The ghost (issue #20): the stored best run for this day rides
    // along as a translucent car on every run of the same day's course.
    // Added underneath the player so an overlap always reads as the
    // player's car. Free play has no day to match, and the day's first
    // run has no trace yet — no ghost on the road in either case.
    ghostCar = null;
    final ghostTrace =
        _ghostDateKey != null ? gameState.ghostFor(_ghostDateKey!) : null;
    if (ghostTrace != null && ghostTrace.sampleCount > 0) {
      final ghost = GhostCar(trace: ghostTrace);
      ghostCar = ghost;
      world.add(ghost);
    }

    // The player starts at y 0 and only drives upward (negative y); chunk
    // indices below 0 already cover the road behind the start line.
    // The game reference is pinned at construction (issue #32): the world
    // swap below can leave this player's own add queued past the next
    // teardown, and an in-flight sprite load must not depend on walking a
    // tree that is being retired underneath it.
    player = PlayerVehicle(
      startPosition: Vector2(roadCenterX, 0),
      vehicleId: gameState.selectedVehicle,
    )..game = this;
    world.add(player);
    _playerReady = true;

    // Camera: locked horizontally on the road, follows the taxi vertically.
    camera.viewfinder.position = Vector2(roadCenterX, 0);
    camera.follow(player, verticalOnly: true);

    trafficSpawner = TrafficSpawner.distanceBased(
      // Traffic rides the difficulty curve laid out over the road that
      // actually exists at each distance, with weather and night folded
      // into the pressure (issue #24).
      profileOf: (d) => environment!.trafficAt(d),
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
    lastFailReason = null;
    // Clear any impact juice left over from the previous level (issue
    // #7). The lives budget resets with it: a level has no failure
    // budget — its first crash still fails it — but the counter must
    // never carry a spent budget across modes (issue #14). A fresh level
    // also re-arms the pause menu's shift-over guard (issue #52).
    shake.reset();
    hitStop.reset();
    _pendingOverlayName = null;
    _crashStallRemaining = 0;
    _shiftOver = false;
    lives.reset();
    _speedLines?.intensity = 0;
    _applyShake(0); // restores the viewport position, dropping any shake

    currentLevel = await levelLoader.loadLevel(levelNumber);
    currentLevelName = currentLevel.name;
    debugPrint('[run] level start $levelNumber \'${currentLevel.name}\'');
    _liveRunSeconds = 0;
    _heartbeatSeconds = 0;

    // A level run has no endless systems. Clear any a previous run left
    // behind: [isEndless] is what routes crashes, banking, and the HUD,
    // and a stale course would keep the level wearing the shift's rules
    // (issue #16 lets one game hand off between the two modes).
    course = null;
    fareController = null;
    roadChunks = null;
    _activeRunSeed = null;
    // The living world goes with it (issue #24): a level is the classic
    // fixed daylight street, with dry grip and a bright sky. The world
    // frame resets with it (issue #30) — an Endless handoff starts clean.
    environment = null;
    _worldShift = 0;
    _rebaseCount = 0;
    gripMultiplier = 1.0;
    darkness = 0;
    _background.darkness = 0;
    _dailyDateKey = null;
    // A level run is no daily course: no ghost recording, no ghost on
    // the road (issue #20).
    _ghostDateKey = null;
    _ghostRecorder = null;
    ghostCar = null;

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
    _clearWorld();

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

    // The street runs a fixed, generous margin past the topmost zone
    // (issue #31): the course ends in road — a painted dead end — and
    // the taxi noses against that end ([PlayerVehicle] reads
    // [levelRoadTopY]) instead of driving off the world.
    final roadTop = highestPointY - levelRoadEndMargin;
    final roadBottom = playerStartY + 500;
    levelRoadTopY = roadTop;
    world.add(RoadSegment(
      position: Vector2(roadCenterX, roadTop),
      length: roadBottom - roadTop,
    ));

    // Render the vehicle selected in the garage/save data. Game reference
    // pinned at construction, as in [startEndlessRun] (issue #32).
    player = PlayerVehicle(
      startPosition: Vector2(roadCenterX, playerStartY),
      vehicleId: gameState.selectedVehicle,
    )..game = this;
    world.add(player);
    _playerReady = true;

    // Camera: locked horizontally on the road, follows the taxi vertically
    // — through the lead (issue #45), a point [levelCameraLead] up the
    // road, so the level's first pickup opens below the HUD chip band
    // instead of underneath a chip. The lead is born at the start's
    // lead position and the viewfinder with it, so frame zero is already
    // the followed frame; [update] keeps the two glued thereafter.
    _levelCameraLead =
        _LevelCameraLead(Vector2(roadCenterX, playerStartY - levelCameraLead));
    camera.viewfinder.position =
        Vector2(roadCenterX, playerStartY - levelCameraLead);
    camera.follow(_levelCameraLead!, verticalOnly: true);

    trafficSpawner = TrafficSpawner(pattern: currentLevel.trafficPattern);
    world.add(trafficSpawner);

    _createPassengers();

    isGameActive = true;
  }

  void _createPassengers() {
    passengers.clear();
    passengersDelivered = 0;

    // Create a passenger for each pickup/dropoff pair in the level. Level
    // fares are all standard (issue #25): the ladder is the tutorial,
    // every pickup is a mandatory objective with an authored dropoff, and
    // a VIP clock or a far-side swap has no take-it-or-leave-it decision
    // to live in there. The special fares belong to the endless course —
    // see [EndlessCourse.fare] — where a fare is an offer.
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
    // A settled run boards nobody (issue #71): the world keeps ticking
    // under the end-of-run panel, and a cab still rolling must not pick
    // up work the ending already closed.
    if (_shiftOver) return;
    player.hasPassenger = true;

    // The meter starts running: this passenger's countdown begins now
    // (issue #12). In an endless run the budget tightens with the
    // difficulty curve's fare pressure at this distance (issue #18) —
    // deep-run fares ride shorter clocks, easing off in the relief lulls
    // like everything else — and the world's mood rides the same meter:
    // rain, fog, and night shorten the countdown by the same modifier
    // they thicken the traffic (issue #24). Level mode keeps the original
    // budgets.
    fareChain.startFare(
      passenger,
      pressure: isEndless
          ? DifficultyCurve.farePressureFor(
              runDistance,
              environmentModifier:
                  environment?.difficultyModifierAt(runDistance) ?? 0.0,
            )
          : 0.0,
    );

    // Green burst: a passenger boarded (issue #7).
    world.add(BurstParticles(
      position: passenger.pickupLocation,
      colors: ImpactFxPalettes.pickup,
    ));
    // ...and the boarding chirp (issue #4) under the boarding thud
    // (issue #5).
    audio?.playPickupSound();
    haptics?.pickup();
  }

  void _onPassengerDropoff(PassengerData passenger) {
    // A settled run delivers nothing (issue #71): the world keeps
    // ticking under the failure panel, and the cab that used to coast
    // in just short of this kerb paid a fare the wreck had already
    // forfeited.
    if (_shiftOver) return;
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

    // The two-tone delivery chime (issue #4) over the delivery thud
    // (issue #5).
    audio?.playDropoffSound();
    haptics?.dropoff();

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
    // A settled shift delivers nothing (issue #71): the wreck panel's
    // world keeps ticking, and a cab coasting on its last velocity used
    // to roll into the dropoff it died 8 px short of — "delivering" the
    // fare, arming the bank prompt over the wreck, and paying a forfeit
    // out a second time through BANK.
    if (_shiftOver) return;
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

    // The two-tone delivery chime (issue #4) over the delivery thud
    // (issue #5).
    audio?.playDropoffSound();
    haptics?.dropoff();

    // Every completed dropoff asks the question (issue #13): bank the
    // score and end the shift, or push on at an increased multiplier. The
    // prompt rides above the live game — the street keeps moving under it.
    _offerBankOrPush();
  }

  // --- Bank or push (issue #13) -------------------------------------------

  /// True while the first-ever bank-or-push offer on this hold traffic
  /// stopped for the decision (the primer). The choice is the game's
  /// core gamble, and it gets one calm introduction per save — after
  /// that every offer rides live traffic on the five-second clock, as
  /// designed. Released by every path that resolves or supersedes the
  /// prompt ([_dismissBankPrompt]).
  bool _bankPrimerActive = false;

  /// Whether the primer is holding its freeze on the save's first-ever
  /// choice (issue #132). See [_bankPrimerActive] — exposed the way
  /// [isShiftOver] is, because [pauseGame] ignores taps for as long as
  /// this is set: the HUD's pause button reads it to stand down instead
  /// of sitting in the corner looking live while doing nothing.
  bool get isBankPrimerActive => _bankPrimerActive;

  /// Puts the bank-or-push choice on screen after an endless dropoff.
  void _offerBankOrPush() {
    bankPrompt.offer();
    // The primer: the first offer a save ever sees stops the world, so
    // the choice can be read instead of reacted to. The ladder's banking
    // lessons (issue #16) run frozen the same way — this is the same
    // mercy for a player who never climbed it.
    if (!gameState.bankPromptSeen) {
      gameState.markBankPromptSeen();
      _bankPrimerActive = true;
      paused = true;
      debugPrint('[bank] primer: first-ever offer froze traffic');
      // No update frame runs while paused, so the engine needs the
      // explicit off — the same line [pauseGame] uses.
      audio?.setEngineRunning(false);
    }
    overlays.add('bankOrPush');
  }

  /// The choice is gone: resolved, superseded by a crash, or left behind
  /// by a restart. Only ever tears down — consequences are applied by the
  /// caller that resolved the prompt. Also the one place the primer
  /// releases its freeze: every resolution path (bank, push, crash,
  /// completion, restart) comes through here.
  void _dismissBankPrompt() {
    bankPrompt.dismiss();
    overlays.remove('bankOrPush');
    if (_bankPrimerActive) {
      _bankPrimerActive = false;
      paused = false;
      // The primer froze the world mid-drive, and a thumb that moved (and
      // was tracked) through the freeze must not hand the cab its
      // pre-freeze axes back: re-feed the offset the thumb actually holds
      // — the same hand-back [resumeGame] gives the pause menu and the
      // crash stall's resume gives its 1.2 s (issues #103, #91). The
      // ending paths that also land here have already stood the shift
      // down, so the stick's own live-game gate makes their call a no-op.
      _virtualStick?.resume();
    }
  }

  /// The pause menu's BANK & QUIT (issue #5): pays the at-risk score out
  /// through the ordinary bank path and hands the shift its earned
  /// summary — quitting is no longer the one way out that silently
  /// deletes the run. A no-op without a live score to protect, and —
  /// since issue #52 — a no-op once the shift has already settled: the
  /// summary owns the screen, and every extra tap here used to pay the
  /// same score into the wallet again.
  void bankFromPause() {
    if (!isEndless || _shiftOver || fareChain.score <= 0) return;
    overlays.remove('pauseMenu');
    paused = false;
    _endShiftAsBanked();
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
    // A settled shift has nothing left to bank (issue #71) — the same
    // guard [bankFromPause] has carried since issue #52. The prompt's
    // BANK used to bypass it, and a delivery the wreck panel should
    // never have allowed armed exactly that prompt.
    if (_shiftOver) return;
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
  ///
  /// The bank is the *whole* payout (issue #34): the flat level reward is
  /// forfeited with the undelivered fares, exactly as an endless bank
  /// forfeits everything after it. The lesson is the bank mechanic, and
  /// paying the score *and* the flat reward would double-pay the rung —
  /// so a banked level pays the chain score OR the flat reward, never
  /// both. Pushing on instead keeps the classic settlement: complete the
  /// level, collect the flat reward, no bank line.
  void _bankAndCompleteLevel() {
    lastBankedScore = fareChain.score;
    gameState.addCoins(lastBankedScore!);
    _completeLevel(banked: true);
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
    // Belt and braces with [bankShift]'s guard (issue #71): every path
    // into a payout stands down once the shift has settled.
    if (_shiftOver) return;
    lastBankedScore = fareChain.score;

    // The summary owns the screen from here (issue #52): the shift is
    // over for pausing and banking alike, and a crash stall still
    // counting down must not resume the world underneath the panel.
    _shiftOver = true;
    _crashStallRemaining = 0;
    isGameActive = false;
    _haltPlayerForShiftEnd();
    trafficSpawner.pause();
    _dismissBankPrompt();

    // The ending tears down any pause that was up when the bank was
    // made (issue #86): the prompt's buttons stay tappable under the
    // pause menu's card, so banking from a paused prompt used to leave
    // the shift ended but the game still frozen — and DRIVE AGAIN then
    // opened a new run under a stale PAUSED menu, because every run
    // starter assumes it is entered unpaused. The same two lines
    // [bankFromPause] and [resumeGame] use. Idempotent for the clean
    // paths: the primer's freeze is released by [_dismissBankPrompt]
    // above, and an unpaused ending removes and sets nothing that
    // matters.
    overlays.remove('pauseMenu');
    paused = false;

    // The ticker keeps running under the summary, and update() stops
    // asserting the engine once the shift settles (issue #73) — so the
    // ending itself turns it off, the same explicit off [pauseGame]
    // gives the pause menu.
    audio?.setEngineRunning(false);

    gameState.addCoins(lastBankedScore!);
    _runCoinsEarned += lastBankedScore!;
    // A payout deserves its sting (issue #4).
    audio?.playBankedJingle();
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
  /// tuning instrument in a game with no analytics. Recording the shift
  /// is also what folds it into the lifetime records and evaluates the
  /// achievements (issue #21), so the summary is built *after* the
  /// record and carries whatever unlocked.
  void _finalizeRunSummary(ShiftOutcome outcome) {
    final previousBest = gameState.endlessBestScore;
    final isPersonalBest = gameState.recordEndlessScore(fareChain.score);
    gameState.recordEndlessRun(RunRecord(
      endedAtMs: DateTime.now().millisecondsSinceEpoch,
      distancePx: runDistance,
      score: fareChain.score,
      faresDelivered: faresDelivered,
      nearMisses: fareChain.nearMisses,
      longestChain: fareChain.bestMultiplier,
      livesLost: _lifeLossDistancesPx.length,
      lifeLossDistancesPx: List.of(_lifeLossDistancesPx),
      banked: outcome == ShiftOutcome.banked,
      durationSeconds: _runDrivenSeconds,
    ));

    // A finished daily shift settles the day's one attempt (issue #19):
    // the score stands — banked payout or forfeited wreck alike — and
    // the day is done. Only this ending records it; a shift abandoned to
    // the menu never ends, and so never spends the attempt.
    final dailyDateKey = _dailyDateKey;
    if (isDailyShift && dailyDateKey != null) {
      gameState.recordDailyResult(DailyResult(
        dateKey: dailyDateKey,
        score: fareChain.score,
        banked: outcome == ShiftOutcome.banked,
        completedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
    }

    // Achievements the shift just earned (issue #21): drained here, one
    // call after the evaluations above, so the summary panel — the
    // screen the shift's ending already owns — is where the player
    // learns about them.
    final unlockedAchievements = gameState.takePendingAchievementUnlocks();

    lastRunSummary = RunSummary(
      outcome: outcome,
      score: fareChain.score,
      bestChain: fareChain.bestMultiplier,
      faresDelivered: faresDelivered,
      nearMisses: fareChain.nearMisses,
      distancePx: runDistance,
      coinsEarned: _runCoinsEarned,
      isPersonalBest: isPersonalBest,
      previousBest: previousBest,
      achievementsUnlocked: unlockedAchievements,
    );

    // A finished daily-course run offers its path as the ghost (issue
    // #20) — the scoring daily itself or a ghost race, never free play
    // (_ghostDateKey is null there). recordDailyGhostRun keeps the
    // best-scoring trace for the day, so the ghost is always the run a
    // replay tries to beat. Fire and forget, like the history writes
    // above.
    final ghostDateKey = _ghostDateKey;
    final recorder = _ghostRecorder;
    if (ghostDateKey != null && recorder != null) {
      gameState.recordDailyGhostRun(
        dateKey: ghostDateKey,
        score: fareChain.score,
        banked: outcome == ShiftOutcome.banked,
        vehicleId: player.vehicleId,
        samples: recorder.takeSamples(),
      );
    }
  }

  /// The run summary's DRIVE AGAIN (issue #15): tears down whichever
  /// end-of-shift panel is up and puts a fresh shift — three new lives, a
  /// new seed, a new city — on the same road immediately. The retry never
  /// routes through the menu; the friction between "I died" and "I'm
  /// driving again" is where retention is won or lost.
  ///
  /// After a Daily Shift (issue #19) the day's attempt is already spent,
  /// so the retry demotes the game to free play: a fresh-seed endless
  /// shift, never a replay of the day's shared course. A ghost race
  /// demotes the same way (issue #20) — racing your ghost is a choice,
  /// not the default that waits behind a tap.
  void retryShift() {
    overlays.remove('shiftBanked');
    overlays.remove('shiftWrecked');
    isDailyShift = false;
    isGhostRace = false;
    startEndlessRun(seed: freshSeed());
  }

  /// The run summary's RACE YOUR GHOST (issue #20), rebuilt in place
  /// (issue #73): the day's course again with the stored best run
  /// riding along as the translucent ghost, on the same route the
  /// summary already owns. The button used to push a *second*
  /// [GameScreen] over the finished one, and the hidden game kept
  /// ticking behind it — its per-frame engine-off fought the live race
  /// through the shared [AudioService], and every MAIN MENU pop landed
  /// on an older summary instead of the menu. One route, one game: the
  /// restart mirrors [retryShift], and [startEndlessRun] does the rest
  /// — it re-derives the ghost day from [isGhostRace], spawns the
  /// [GhostCar], and clears the settled shift's flags.
  ///
  /// The race may only start for the day the settled run pinned
  /// ([runDateKey]) — the day the summary's button was built for. A tap
  /// after midnight (issue #96) used to re-read `todayKey`, which was
  /// already the next day: the "race" drove D+1's never-shared course
  /// alone — the ghost it promised belonged to D — and the practice
  /// run's trace then became D+1's stored ghost, overwriting D's, so
  /// the player entered D+1's one scoring attempt having rehearsed the
  /// course. Refused, nothing changes: the summary keeps the screen,
  /// exactly as if the button had never been offered.
  void raceGhost() {
    final day = runDateKey;
    if (day == null || day != DailyShift.todayKey) return;
    overlays.remove('shiftBanked');
    overlays.remove('shiftWrecked');
    isDailyShift = false;
    isGhostRace = true;
    startEndlessRun(seed: DailyShift.seedForDateKey(day));
  }

  /// Settles a completed level: freezes the run, pays the flat reward —
  /// unless the level was [banked], whose payout is the chain score
  /// already in the wallet (issue #34) — and unlocks the next rung.
  void _completeLevel({bool banked = false}) {
    // The completion panel owns the screen from here: the run is as
    // terminal as a settled shift (issue #71) — no pausing, banking, or
    // delivering under it, and no cab coasting on into a kerb.
    _shiftOver = true;
    isGameActive = false;
    _haltPlayerForShiftEnd();
    trafficSpawner.pause();
    // The engine's explicit off for the same reason as the endless
    // endings (issue #73): update() stops asserting once the run
    // settles, so the ending itself is the last call.
    audio?.setEngineRunning(false);

    // Completing the level supersedes any open bank-or-push choice
    // (issue #16): the last fare's delivery can land while a prompt from
    // the previous one is still up, and a settled level owes no payout on
    // top of its completion.
    _dismissBankPrompt();

    // The ending tears down any pause that was up when the bank was made
    // (issue #86) — same two lines as [_endShiftAsBanked]: a banking
    // lesson's prompt banked while paused used to hand NEXT LEVEL a
    // frozen game under a stale PAUSED menu, because [loadLevel] assumes
    // it is entered unpaused. Idempotent for the ordinary, unpaused
    // completion.
    overlays.remove('pauseMenu');
    paused = false;

    // A volley of coins streams from the taxi to the HUD counter as the
    // reward lands (issue #7). A banked level paid its coins at the
    // dropoff, so the volley celebrates the bank already on the counter.
    for (var i = 0; i < 6; i++) {
      world.add(CoinPop(
        startPosition: player.position,
        delay: 0.05 * i,
      ));
    }
    // Coins ring (issue #4) and tick in the hand (issue #5), and the
    // completion jingle plays (issue #4).
    audio?.playCoinSound();
    haptics?.coinAward();
    audio?.playLevelCompleteSound();

    // Award coins and unlock the next level. A bank pays the chain score
    // OR the flat reward, never both (issue #34): the score is in, so the
    // reward pays nothing.
    gameState.completeLevel(currentLevelNumber, banked ? 0 : currentLevel.coinReward);

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
    lastFailReason = LevelFailReason.crash;

    // A crash forfeits everything unbanked (issue #13): the open choice
    // dies with the run, and whatever the chain held stays unbanked.
    _dismissBankPrompt();

    if (report != null) {
      debugPrint('[crash] ${report.explanation}');
      _spawnCrashFx(report);
    }
    // The failure panel owns the screen from here: the run is as
    // terminal as a settled shift (issue #71) — the world that keeps
    // ticking underneath must deliver, bank, and roll nowhere.
    _shiftOver = true;
    isGameActive = false;
    _haltPlayerForShiftEnd();
    trafficSpawner.pause();
    // The engine's explicit off, as every terminal ending gives it
    // (issue #73).
    audio?.setEngineRunning(false);

    // The failure overlay waits out the hit-stop (issue #7): the sparks,
    // shake, and freeze land first, then the panel explains what happened.
    if (hitStop.isActive) {
      _pendingOverlayName = 'levelFailed';
    } else {
      overlays.add('levelFailed');
    }
    // The wreck sting lands with the impact, panel or no panel (issue #4).
    audio?.playLevelFailedSound();
  }

  // --- Stranded fares (issue #112) -----------------------------------------

  /// Fails the level when a fare it still needs is behind the cab for
  /// good (issue #112): level streets are one-way — no reverse, and
  /// issue #31's end clamp exists because of it — so a pickup the cab
  /// sailed past, or a carried dropoff it never stopped for, can never
  /// be completed; every further delivery only postpones the discovery,
  /// and the run used to end with the cab parked at the road's end, no
  /// fail, no retry, no message. The endless course instead relocates
  /// passed dropoffs (issue #28) — forgiveness for a mode whose fares
  /// are offers; a level's fares are mandatory objectives, so the honest
  /// verdict is the failure flow, with a reason of its own so the panel
  /// can name it. The 80 px grace mirrors
  /// [EndlessFareController.passHysteresis]: a cab grazing a zone's
  /// edge is judged still at it, not past it. Level zones never move
  /// (the world fold is endless-only, issue #30), so the stored route
  /// points are the live zone positions.
  void _checkForMissedFares() {
    final playerY = player.position.y;
    for (final passenger in passengers) {
      if (passenger.isDelivered) continue;
      // The zone this fare still needs: its kerb if not yet boarded,
      // its destination if aboard.
      final neededY = passenger.isPickedUp
          ? passenger.dropoffLocation.y
          : passenger.pickupLocation.y;
      if (playerY < neededY - EndlessFareController.passHysteresis) {
        _failLevelForMissedFare();
        return;
      }
    }
  }

  /// The failure ending for a stranded fare (issue #112): the same
  /// settle a crash performs — run over, cab halted, spawner paused,
  /// engine off, any open bank choice dismissed — minus the impact
  /// telemetry and FX, and with the reason the panel words itself from.
  /// RETRY is the recovery: [restartLevel] re-runs the rung from its
  /// start, below every zone again.
  void _failLevelForMissedFare() {
    if (!isGameActive) return;
    lastFailReason = LevelFailReason.fareMissed;
    debugPrint('[level] fare missed: a zone this level still needs is '
        'behind the cab (cab y ${player.position.y.toStringAsFixed(0)})');
    _dismissBankPrompt();
    _shiftOver = true;
    isGameActive = false;
    _haltPlayerForShiftEnd();
    trafficSpawner.pause();
    audio?.setEngineRunning(false);
    overlays.add('levelFailed');
    audio?.playLevelFailedSound();
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
      // Name the cost where it was paid (issue #14's feedback gap): the
      // world is about to hold still for [crashStallSeconds], and the
      // pop rides that freeze — the impact lands, "-1 LIFE · N LEFT"
      // hangs over the frozen taxi, and it rises away as the shift
      // resumes.
      world.add(LifeLostPop(
        position: player.position + Vector2(0, -70),
        livesLeft: lives.remaining,
      ));
      _stallAfterCrash();
    }
  }

  /// Holds the whole world still for [crashStallSeconds] — long enough
  /// for the spent life to register — then hands the shift back.
  void _stallAfterCrash() {
    isGameActive = false;
    // Suspend, not release (issue #91): the thumb that caused the crash
    // is usually still down, and the shift resumes under it — it must
    // keep owning the stick through the stall to drive the moment the
    // world moves again.
    _freezePlayer(releaseStick: false);
    _crashStallRemaining = crashStallSeconds;
  }

  /// Hands the shift back after the stall: same road, same fares, same
  /// unbanked score — now riding on a broken 1x chain.
  void _resumeAfterCrashStall() {
    _crashStallRemaining = 0;
    isGameActive = true;
    // The held thumb drives immediately (issue #91): a still thumb emits
    // no drag updates, so the resume re-feeds the offset it holds rather
    // than waiting for the next move — the cab would otherwise sit dead
    // through exactly the moment the player needs it moving.
    _virtualStick?.resume();
  }

  /// The third crash: the shift ends and everything unbanked is forfeit
  /// (issue #14) — the outcome banking at a dropoff exists to escape.
  /// Nothing is paid into the wallet here; the forfeited score is only
  /// ever read, by the wreck panel, to say what was lost.
  void _endShiftAsWrecked() {
    // The wreck summary owns the screen (issue #52): no pausing under
    // it, and — the hole this flag closes — no BANK & QUIT paying the
    // forfeited score out through the pause menu afterwards.
    _shiftOver = true;
    _crashStallRemaining = 0;
    isGameActive = false;
    _haltPlayerForShiftEnd();
    trafficSpawner.pause();
    // The engine's explicit off for the same reason as the bank's (issue
    // #73): update() has nothing more to assert once the shift settles.
    audio?.setEngineRunning(false);
    _finalizeRunSummary(ShiftOutcome.wrecked);

    // The wreck panel waits out the hit-stop (issue #7): the impact
    // lands first, then the forfeit is explained.
    if (hitStop.isActive) {
      _pendingOverlayName = 'shiftWrecked';
    } else {
      overlays.add('shiftWrecked');
    }
    // The wreck sting lands with the impact, panel or no panel (issue #4).
    audio?.playLevelFailedSound();
  }

  /// Crash juice (issue #7): a hot spark burst at the contact point,
  /// a hit-stop, and a shake scaled to how fast the impact closed.
  void _spawnCrashFx(CrashReport report) {
    final sparks = BurstParticles(
      position: report.contactPoint.clone(),
      colors: ImpactFxPalettes.crash,
      count: 18,
      maxSpeed: 240,
      lifetime: 0.6,
    );
    // Kept for the freeze (issue #106): the frozen branches of [update]
    // tick this burst through the hit-stop and stall it belongs to —
    // before, both it and the "-1 LIFE" pop sat unmounted in the add
    // queue for the whole freeze (the branches return before
    // `super.update`, the only place that ever drained the queue) and
    // played late, the instant the shift resumed.
    _crashSparks = sparks;
    world.add(sparks);
    shake.trigger(
      ImpactFx.crashShakeMagnitudeFor(report.closingSpeedAlongImpact),
      duration: ImpactFx.crashShakeDuration,
    );
    hitStop.trigger();
    // The impact sound rides the same beat as the shake and the freeze
    // (issue #4), and the heavy buzz lands in the same instant (issue #5).
    audio?.playCrashSound();
    haptics?.crash();
  }

  /// The crash freeze's one concession to time (issue #106): the frozen
  /// branches of [update] return before `super.update`, and
  /// `super.update`→`updateTree` is the only place Flame's
  /// component-lifecycle queue ever drains — so everything a crash
  /// queued sat invisible through the 0.10 s hit-stop plus the 1.2 s
  /// stall and appeared only as the world resumed. The frozen frame
  /// drains the queue itself here — the same public
  /// [ComponentTreeRoot.processLifecycleEvents] Flame's own `ready()`
  /// runs — so the pop and the spark burst mount on the first frozen
  /// frame. Then only the sparks tick: the burst is the impact, and the
  /// impact is *now*; the pop is the freeze's caption, mounted but
  /// held, and rises away when the shift resumes. Nothing else enqueues
  /// during a freeze, so the drain admits exactly the crash's own FX.
  /// The burst's self-removal, once its last particle dies, is drained
  /// by the next frozen frame's pass here — which is also what ends
  /// the ticking.
  void _playCrashFxThroughFreeze(double dt) {
    processLifecycleEvents();
    final sparks = _crashSparks;
    if (sparks != null && sparks.isMounted) {
      sparks.update(dt);
    }
  }

  /// Records a low-speed glancing scrape: no life is lost, the player was
  /// already slowed by [PlayerVehicle]; this only surfaces feedback naming
  /// what was hit.
  void onScrape(CrashReport report) {
    lastImpact = report;

    // One volley of feedback per window (issue #42): a push-match grinds
    // out scrapes at frame rate, and each one used to add particles,
    // shake, sound, and a marker — 60 Hz of all four. The record above
    // always updates; everything the player sees and hears shares the
    // same 0.4 s window the marker has always kept.
    if (_scrapeFeedbackCooldown > 0) return;
    _scrapeFeedbackCooldown = 0.4;

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
    // Sheet-metal scrape sound under the jolt (issue #4).
    audio?.playScrapeSound();
    world.add(ScrapeMarker(
      position: report.contactPoint.clone(),
      vehicleKind: report.vehicleKind,
    ));
  }

  /// A pass the taxi just cleared, reported by [vehicle] at the moment
  /// its y sank past the vehicle's (issue #23). The ruling is made here:
  /// a close call needs [NearMissRules]' clearance and speed, so most
  /// passes report in and rule out. A pass that rules in pays through
  /// the fare chain ([FareChain.awardNearMiss]) — there is no second
  /// score — and the feedback is loud on every channel the game has,
  /// because a near-miss the player does not notice scores nothing
  /// psychologically.
  void onNearMiss(TrafficVehicle vehicle) {
    if (!isGameActive) return;

    final gap = NearMissRules.lateralGap(
      playerPosition: player.position,
      playerSize: player.vehicleSize,
      vehiclePosition: vehicle.position,
      vehicleSize: vehicle.vehicleSize,
    );
    final isCloseCall = NearMissRules.isCloseCall(
      gap: gap,
      playerForwardSpeed: -player.velocity.y,
    );
    if (!isCloseCall) return;

    final points = fareChain.awardNearMiss();
    debugPrint('[near-miss] Cleared a ${vehicle.vehicleType.name} for '
        '$points pts — ${fareChain.nearMisses} this run.');

    // A cool slipstream burst in the gap the pass threaded, and the
    // award floating up out of it — the same beat the other feedback
    // pops play, in the close-call palette's cyan.
    final midPoint = (player.position + vehicle.position) / 2;
    world.add(BurstParticles(
      position: midPoint,
      colors: ImpactFxPalettes.closeCall,
      count: 10,
      maxSpeed: 150,
      lifetime: 0.35,
      gravity: 40,
    ));
    world.add(CloseCallPop(position: midPoint, points: points));

    // Haptic thump plus the OS click (the game ships no audio assets —
    // see [CloseCallFeedback]) under the save's existing settings: the
    // thump rides the haptics service's vibration gate like every other
    // buzz, the click the sound flag (issue #75).
    haptics?.closeCall();
    CloseCallFeedback.play(soundEnabled: gameState.soundEnabled);
  }

  @override
  void update(double dt) {
    // Issue #36: no single frame may consume more than [maxUpdateDelta],
    // whatever the ticker says — a resume frame carrying the whole
    // backgrounded gap is truncated, protecting every dt-driven system
    // below at once (fare countdowns, the bank window, stalls, hit-stops,
    // and every component's movement) instead of each one patching its
    // own dt.
    dt = math.min(dt, maxUpdateDelta);

    // Engine audio (issue #4): humming while the shift is live, idling
    // under a stopped taxi and rising with forward speed. Re-asserted every
    // frame — including frozen ones — so a hit-stop or a crash stall quiets
    // the engine for exactly as long as the world is held. A stopped ticker
    // (pause menu, backgrounding) calls no update at all; those paths turn
    // the engine off explicitly in [pauseGame] and [lifecycleStateChange].
    //
    // A settled shift stops asserting altogether (issue #73): the summary
    // owns the screen but the ticker keeps running, and the finished game's
    // per-frame engine-off used to fight a live race driven over it through
    // the shared AudioService. The endings turn the engine off once,
    // explicitly; from there this loop has nothing more to say.
    if (_playerReady && !_shiftOver) {
      final speed01 =
          (-player.velocity.y / player.maxSpeed).clamp(0.0, 1.0);
      audio?.setEngineRunning(isGameActive);
      audio?.setEngineIntensity(speed01);
    }

    // Sample the living world (issue #24) before anything moves: the
    // overlay tints from it, traffic lights its headlights by it, and the
    // player car steers by its grip. Runs even while frozen — [runDistance]
    // stays readable through a crash stall, so the sky holds still with
    // the world instead of flickering.
    _sampleEnvironment();

    if (hitStop.isActive) {
      // Hit-stop (issue #7): the world holds still for a beat — no
      // component updates, no collisions — while the shake keeps jittering
      // the frozen frame. The crash's own FX are the one exception
      // (issue #106): the queued sparks and pop mount and the sparks
      // play, so the freeze shows the impact instead of a bare frame.
      hitStop.update(dt);
      _playCrashFxThroughFreeze(dt);
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
    // the shift resumes where it left off. The crash's sparks keep
    // burning through it (issue #106) — everything else waits.
    if (_crashStallRemaining > 0) {
      _crashStallRemaining = math.max(0.0, _crashStallRemaining - dt);
      _playCrashFxThroughFreeze(dt);
      _applyShake(dt);
      if (_crashStallRemaining <= 0) {
        _resumeAfterCrashStall();
      }
      return;
    }

    // Keep the world's coordinates small (issue #30): fold the whole
    // world back one period whenever the taxi crosses the next boundary,
    // before anything reads a position this frame.
    _maybeRebaseWorld();

    // Refresh the level camera's lead (issue #45) here, immediately
    // before the tree ticks: the camera updates ahead of the world, so a
    // lead updated inside the world would hand the follow a frame-old
    // position and the view would rubber-band a tick behind every move.
    // Mirroring here reads the taxi where it stands this tick — exactly
    // the position the follow saw when it tracked the taxi itself.
    final lead = _levelCameraLead;
    if (lead != null) {
      lead.position.setFrom(player.position);
      lead.position.y -= levelCameraLead;
    }

    super.update(dt);
    _applyShake(dt);

    // Fare countdowns tick only while the run is live (issue #12): a
    // crash, the completion panel, or a pause freezes the meter with
    // everything else. (Pause stops this whole method; overlays set
    // isGameActive false first.)
    if (isGameActive) {
      fareChain.update(dt);

      // The stranded-fare verdict (issue #112) rides the live clock with
      // the meter: it must not tick (nor fire) through a crash stall, a
      // hit-stop, or any panel — only while the level is actually being
      // driven. Endless is exempt by route: its fares are offers, and a
      // passed dropoff relocates (issue #28) instead of failing.
      if (!isEndless) _checkForMissedFares();

      // The diagnostics heartbeat: one line of where the run stands per
      // heartbeatInterval of live play — the trail a hard kill cuts off.
      _liveRunSeconds += dt;
      _heartbeatSeconds += dt;
      if (_heartbeatSeconds >= heartbeatInterval) {
        _heartbeatSeconds = 0;
        debugPrint('[shift] t=${_liveRunSeconds.round()}s '
            'dist=${(runDistance / RunSummary.pixelsPerMetre).round()}m '
            'speed=${(-player.velocity.y).round()}px/s '
            'score=${fareChain.score} '
            '${isEndless ? 'lives=${lives.remaining}' : 'level=$currentLevelNumber'}');
      }

      // The stats clock (issue #17) runs with the same one: only time the
      // shift is actually live counts as driven.
      if (isEndless) {
        _runDrivenSeconds += dt;

        // The ghost trace samples the same clock (issue #20), so the
        // replay measures driving — never hit-stops, stalls, or dead
        // time — exactly the beats it races against. Samples are stored
        // in true-distance coordinates (issue #30): the replay adds the
        // fold it replays under, so traces stay comparable across runs.
        _ghostRecorder?.tick(
            dt, player.position.x, player.position.y - worldShift);
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

    if (_scrapeFeedbackCooldown > 0) {
      _scrapeFeedbackCooldown = math.max(0.0, _scrapeFeedbackCooldown - dt);
    }
  }

  /// Reads the run environment at the taxi's distance (issue #24) and
  /// pushes what the frame needs where it is consumed: grip to the car,
  /// darkness to traffic, and the overlay's three intensities to the
  /// windshield layer. Level mode has no environment; every value rests
  /// at its neutral.
  void _sampleEnvironment() {
    final env = environment;
    if (env == null || !isEndless) {
      gripMultiplier = 1.0;
      darkness = 0;
      _background.darkness = 0;
      _environmentOverlay?.darkness = 0;
      _environmentOverlay?.rainIntensity = 0;
      _environmentOverlay?.fogIntensity = 0;
      return;
    }

    final distance = runDistance;
    gripMultiplier = env.gripAt(distance);
    darkness = env.darknessAt(distance);
    _background.darkness = darkness;
    final overlay = _environmentOverlay;
    if (overlay != null) {
      overlay.darkness = darkness;
      overlay.rainIntensity = env.rainIntensityAt(distance);
      overlay.fogIntensity = env.fogIntensityAt(distance);
    }
  }

  /// Folds the world back toward the origin (issue #30) whenever the taxi
  /// has crossed the next [WorldOrigin.period] boundary: every world
  /// component and the camera move by the same delta in the same tick, so
  /// nothing on screen moves and world y never grows past one period —
  /// which is what keeps the canvas's single-precision transforms from
  /// degrading the road into bare sky on long runs.
  ///
  /// The fold's frame is the live shift [worldShift] itself, and live
  /// placement — chunks, fare zones — goes through it (`worldShift −
  /// distance`), *not* the canonical per-distance mapping: a distance
  /// just ahead of a boundary the taxi hasn't crossed belongs to the next
  /// frame canonically, and placing it there drew it a whole period away
  /// (issue #53). Anything holding coordinates outside the component tree
  /// (traffic waypoints, ghost traces, frozen passenger vectors) converts
  /// through [worldShift] too, and is shifted at its owner.
  void _maybeRebaseWorld() {
    if (!isEndless || !_playerReady) return;

    final trueDistance = worldShift - player.position.y;
    final frame = (trueDistance / WorldOrigin.period).floor();
    if (frame <= _rebaseCount) return;

    final delta = (frame - _rebaseCount) * WorldOrigin.period;
    _rebaseCount = frame;
    _worldShift += delta;

    // World children only: a chunk's cones and a vehicle's sprite are in
    // their parent's local space and must not move twice. Traffic paths
    // and the fares' frozen passenger vectors are the world-sized state
    // held outside the tree — shifted at their owners.
    for (final child in world.children) {
      if (child is PositionComponent) child.position.y += delta;
    }
    trafficSpawner.shiftWorld(delta);
    fareController?.shiftStoredFares(delta);
    // The viewfinder's getter hands back a copy (it reads a transform
    // offset), so the fold assigns a fresh vector — `+=` on `.position.y`
    // would fold everything but the camera. The follow behavior locks the
    // viewfinder on the taxi at infinite speed anyway, so snapping it to
    // the folded taxi keeps the same frame the follow would produce — and
    // world components that update before the camera this very tick read
    // a viewfinder that agrees with the folded world.
    camera.viewfinder.position = Vector2(
      camera.viewfinder.position.x,
      player.position.y,
    );
  }

  /// Applies one frame of screen shake as a delta on the viewport
  /// position, so it never fights the camera's follow logic (which owns
  /// the viewfinder) and leaves no residue when it decays.
  void _applyShake(double dt) {
    final base = camera.viewport.position - _appliedShakeOffset;
    _appliedShakeOffset.setFrom(shake.update(dt));
    camera.viewport.position = base + _appliedShakeOffset;
  }

  /// Stops the player's inputs. Terminal endings take the default and
  /// [VirtualStick.release] the stick (`releaseStick: true`): the run is
  /// over, so a thumb still on the screen must own nothing afterwards.
  /// The crash stall passes `releaseStick: false` and suspends instead
  /// (issue #91): the shift resumes 1.2 s later under a thumb that never
  /// lifted, and a release there cleared the stick's pointer id — every
  /// drag update from the held thumb was then dropped by its guard, and
  /// the cab sat dead until the thumb lifted and landed again.
  void _freezePlayer({bool releaseStick = true}) {
    // The stick zeroes its own inputs on release or suspension (issues
    // #29, #91); the explicit zeroes below cover a freeze without a
    // touch at all.
    if (releaseStick) {
      _virtualStick?.release();
    } else {
      _virtualStick?.suspend();
    }
    player.stopAccelerating();
    player.setThrottle(0);
    player.setSteering(0);
    // The inputs are over either way; the windshield effect ends with
    // them (issue #7), and update() re-intensifies it the moment the
    // stall hands the world back.
    _speedLines?.intensity = 0;
  }

  /// A terminal ending's freeze: on top of the dead stick
  /// ([_freezePlayer], which releases — the run is over) the body stops
  /// dead. [update] keeps ticking the world under an end-of-run panel,
  /// and a cab that had only lost its inputs kept coasting on its last
  /// velocity — rolling into the drop-off the wreck had come up just
  /// short of and "delivering" a fare the ending had already forfeited
  /// (issue #71). The crash stall keeps to a plain [_freezePlayer] —
  /// suspending the stick instead of releasing it (issue #91) and
  /// leaving the body's momentum alone: the shift resumes there, and
  /// both the thumb that held on and the cab's motion are part of what
  /// it resumes with.
  void _haltPlayerForShiftEnd() {
    _freezePlayer();
    player.velocity = Vector2.zero();
  }

  void pauseGame() {
    // The primer already holds the world still (issue #4): a pause menu
    // stacked on it could only fight the prompt for the release, so the
    // HUD's pause button stands down until the choice resolves. And a
    // settled shift's summary owns the screen (issue #52): a menu under
    // it offered a bank that paid the same score out on every tap.
    if (_bankPrimerActive || _shiftOver) return;
    paused = true;
    // The ticker stops with the pause, so no update frame will quiet the
    // engine — turn it off here (issue #4).
    audio?.setEngineRunning(false);
    overlays.add('pauseMenu');
  }

  void resumeGame() {
    if (_bankPrimerActive) return;
    paused = false;
    // The thumb that held the stick through the pause kept tracking its
    // glides but fed nothing (the stick's pause gate), so the cab left the
    // menu driving the pre-pause axes until the thumb next moved (issue
    // #103) — re-feed the offset the resume actually finds. The stall's
    // own resume (issue #91) does the same hand-back one freeze over.
    _virtualStick?.resume();
    overlays.remove('pauseMenu');
  }

  // --- App lifecycle (issue #36) -------------------------------------------

  /// Set when the app was sent to the background (or covered by a system
  /// surface) with a live shift on the road: the run was frozen through
  /// the engine's own pause, without dropping the pause menu over a
  /// street the player can no longer see. When the app comes back, this
  /// flag turns the freeze into the ordinary pause menu, so re-entering
  /// the shift is a deliberate act — the player is never dumped back into
  /// live traffic by the OS.
  bool _lifecycleAutoPaused = false;

  /// True while a shift is live enough that backgrounding it must freeze
  /// the run and demand deliberate re-entry on return: the street is
  /// moving and the clocks are burning. Deliberately narrow — a crash
  /// stall or hit-stop has already frozen the world (and only ever
  /// consumes clamped time, see [maxUpdateDelta]), and an end-of-shift
  /// panel has nothing live left to protect.
  bool get _isRunLive => isGameActive;

  /// Flame's hook for app lifecycle changes (`Game.lifecycleStateChange`
  /// — wired through the game widget's render box observer). Flame's own
  /// handling stops and restarts the ticker around the absence; keep it,
  /// then add the run-level freeze and the deliberate re-entry on top.
  ///
  /// The order matters: [FlameGame.lifecycleStateChange] pauses the
  /// engine and, on return, silently restarts it — resuming the shift
  /// without asking, which is exactly the behaviour this override exists
  /// to gate. [_lifecycleAutoPaused] is therefore decided from the pause
  /// state *before* the super call, and re-asserted after it on resume.
  @override
  void lifecycleStateChange(AppLifecycleState state) {
    debugPrint('[lifecycle] ${state.name} paused=$paused');
    final wasRunning = !paused;
    super.lifecycleStateChange(state);

    switch (state) {
      case AppLifecycleState.inactive: // notification shade, call banner
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Audio follows the run out: engine off, music suspended (issue
        // #4). No update frame runs while the ticker is stopped, so the
        // engine needs the explicit off.
        audio?.pauseAll();
        if (_isRunLive && wasRunning) {
          // Freeze through the existing pause machinery, but keep the
          // menu off the street: the freeze is recorded here, and the
          // pause menu waits for the app to come back.
          _lifecycleAutoPaused = true;
          paused = true;
        }
      case AppLifecycleState.resumed:
        audio?.resumeAll();
        if (_lifecycleAutoPaused) {
          _lifecycleAutoPaused = false;
          // Flame's super call above may have restarted the ticker; hold
          // the freeze and put the existing pause menu up, so the player
          // walks back in through [resumeGame].
          paused = true;
          overlays.add('pauseMenu');
        }
    }
  }

  /// Leaving a game screen is not backgrounding the app — but Flame's
  /// dispose path fakes exactly that: `GameWidget.disposeCurrentGame`
  /// fires `lifecycleStateChange(AppLifecycleState.paused)` immediately
  /// before this hook, which suspends the whole audio service. Nothing
  /// on the menu ever resumed it, so the music died after every game,
  /// and the Settings toggle could not revive it either — `playMusic`
  /// returns early while suspended (issue #54). Hand the audio back to
  /// the menu here, guarded on the app actually being in the foreground:
  /// the framework updates `WidgetsBinding.lifecycleState` *before*
  /// notifying observers, so a genuine backgrounding is already visible
  /// as hidden/paused/detached by the time this runs, and only the
  /// synthetic pause of a widget disposal slips through (a null state —
  /// headless tests — also means foreground). The engine stays off after
  /// a game: `pauseAll` already cleared its want, and the menu does not
  /// drive.
  @override
  void onDispose() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final appInBackground = lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.detached;
    if (!appInBackground) {
      audio?.resumeAll();
    }
    super.onDispose();
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

    // Keyboard input only overrides "stop" when no thumb owns the stick
    // (issue #29), so the two inputs can be used together.
    final stickActive = _virtualStick?.isActive ?? false;
    if (accelerate) {
      player.startAccelerating();
    } else if (!stickActive) {
      player.stopAccelerating();
    }
    if (left != right) {
      player.setSteering(left ? -1 : 1);
    } else if (!stickActive) {
      player.setSteering(0);
    }
    return KeyEventResult.handled;
  }
}

/// The invisible point the level camera follows (issue #45): the taxi's
/// position nudged up the road by [TaxiGame.levelCameraLead], so the
/// ladder's first pickup spawns clear of the HUD chip band. Never added
/// to the component tree — [TaxiGame.update] copies the taxi's position
/// into it each tick, and the follow behavior reads that; keeping it out
/// of the world also keeps it out of the world fold (issue #30) and
/// every `_clearWorld`, which is correct, because [TaxiGame.loadLevel]
/// rebuilds it with each level anyway.
class _LevelCameraLead extends PositionComponent {
  _LevelCameraLead(Vector2 position) : super(position: position.clone());
}
