import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/pickup_zone.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/passenger_data.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// App-lifecycle handling (issue #36): backgrounding mid-shift must be a
/// non-event for run state. The run freezes through the pause machinery
/// without popping the menu over the street, the return shows the pause
/// menu so re-entry is deliberate, and — whatever dt the resumed ticker
/// carries — no frame may consume more than [TaxiGame.maxUpdateDelta], so
/// fare countdowns, the bank-or-push window, and the taxi's position all
/// survive the absence intact.

/// The staged state's snapshot: the clocks and positions a backgrounded
/// shift must come back with.
class _StagedShift {
  _StagedShift({
    required this.passenger,
    required this.timerSeconds,
    required this.bankSeconds,
    required this.playerY,
  });

  /// The boarded passenger whose countdown is running.
  final PassengerData passenger;
  final double timerSeconds;
  final double bankSeconds;
  final double playerY;

  double timerNow(TaxiGame game) =>
      game.fareChain.timerFor(passenger)!.remainingSeconds;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
    // These tests stage a bank window over a LIVE run — mark the primer
    // spent up front, or the first-ever offer would hold its teaching
    // freeze through the backgrounding and change what "was running"
    // means below.
    gameState.markBankPromptSeen();
  });

  /// Mounts [game] headlessly so component `onLoad` hooks run (the
  /// endless-run test pattern; [Game.mount] is what GameWidget calls in
  /// production).
  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  /// Headless games have no overlay builder map; the flows under test
  /// add 'pauseMenu' (the lifecycle return), 'bankOrPush' (each endless
  /// dropoff), and 'shiftBanked' (a bank), so register stand-ins as
  /// [GameScreen] does in production.
  TaxiGame endlessGame(int seed) => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: seed,
      )
        ..overlays.addEntry('pauseMenu', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink());

  /// Lets pending component mounts finish before the next simulated tick.
  Future<void> drain() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.value();
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> tickAndSettle(TaxiGame game) async {
    game.update(1 / 60);
    await drain();
    game.update(1 / 60);
    await drain();
  }

  /// Delivers [fare] by teleporting the taxi kerb to kerb, the way the
  /// endless-run tests do. Assumes the fare's zones are mounted.
  void deliverFare(TaxiGame game, EndlessFare fare) {
    game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
    game.update(1 / 60);
    game.player.position = Vector2(fare.dropoff.x, fare.dropoff.y + 30);
    game.update(1 / 60);
  }

  /// Brings a live shift to the exact state the issue describes: fare 0
  /// delivered (the bank-or-push window open) and fare 1 boarded (its
  /// countdown running), so both clocks are burning when the app goes to
  /// the background.
  Future<_StagedShift> stageTimerAndBankWindow(TaxiGame game) async {
    await tickAndSettle(game);

    deliverFare(game, game.course!.fare(0));
    expect(game.bankPrompt.isActive, isTrue,
        reason: 'precondition: the bank window is open');
    expect(game.fareChain.isCarryingFare, isFalse,
        reason: 'precondition: fare 0 is settled');

    // Drive on so the course streams fare 1 in, then board it.
    game.player.position += Vector2(0, -900);
    await tickAndSettle(game);
    final fare1 = game.course!.fare(1);
    game.player.position = Vector2(fare1.pickup.x, fare1.pickup.y + 30);
    game.update(1 / 60);

    final passenger = game.world.children.whereType<PickupZone>().firstWhere(
          (z) => z.passenger.id == 'endless_1',
        ).passenger;
    expect(game.fareChain.timerFor(passenger), isNotNull,
        reason: 'precondition: fare 1 rides on a live countdown');

    return _StagedShift(
      passenger: passenger,
      timerSeconds: game.fareChain.timerFor(passenger)!.remainingSeconds,
      bankSeconds: game.bankPrompt.remainingSeconds,
      playerY: game.player.position.y,
    );
  }

  group('backgrounding mid-shift (issue #36)', () {
    test('freezes the run silently and demands deliberate re-entry on '
        'return, with every clock intact behind a 30 s resume frame',
        () async {
      final game = await mountGame(endlessGame(42));
      final staged = await stageTimerAndBankWindow(game);

      // The taxi is moving when the interruption hits — the dangerous
      // case, the one that could tunnel through traffic on a giant dt.
      const speed = 280.0;
      game.player.velocity = Vector2(0, -speed);

      // A parked car 150 px up the road: if the resume frame tunnelled,
      // the taxi would blow straight past it.
      final parkedCar = TrafficVehicle(
        position: Vector2(200, staged.playerY - 150),
        vehicleType: TrafficVehicleType.sedan,
        baseSpeed: 0,
        path: [Vector2(200, staged.playerY - 150)],
      );
      game.world.add(parkedCar);

      // --- The app goes to the background (call, notification shade) ---
      game.lifecycleStateChange(AppLifecycleState.hidden);

      expect(game.paused, isTrue, reason: 'the run is frozen');
      expect(game.isGameActive, isTrue,
          reason: 'the shift itself is intact, not torn down');
      expect(game.overlays.isActive('pauseMenu'), isFalse,
          reason: 'no pause menu popped over a street nobody can see');

      // --- The app comes back; the ticker carries the absent 30 s ---
      game.lifecycleStateChange(AppLifecycleState.resumed);

      expect(game.paused, isTrue,
          reason: 'still frozen — the player must re-enter deliberately');
      expect(game.overlays.isActive('pauseMenu'), isTrue,
          reason: 'the existing pause menu is the way back in');
      expect(game.bankPrompt.isActive, isTrue,
          reason: 'the bank window never silently resolved to push');

      // The resumed frame delivers the whole absent gap as one dt. The
      // auto-pause already gates it in production (a paused engine gets
      // no updates); the clamp is the guarantee that even a frame that
      // slips through cannot spend the absence.
      game.update(30.0);

      expect(staged.timerNow(game),
          closeTo(staged.timerSeconds - TaxiGame.maxUpdateDelta, 1e-9),
          reason: 'the fare countdown lost one clamped frame, not 30 s');
      expect(game.bankPrompt.remainingSeconds,
          closeTo(staged.bankSeconds - TaxiGame.maxUpdateDelta, 1e-9),
          reason: 'the bank window lost one clamped frame, not 30 s');

      final travelled = staged.playerY - game.player.position.y;
      expect(travelled, greaterThan(10.0),
          reason: 'the taxi did keep rolling under the clamp');
      expect(travelled, lessThan(TaxiGame.maxUpdateDelta * speed),
          reason: 'one frame moves at most maxUpdateDelta of real speed, '
              'not 30 s of it (unclamped: ${speed * 30.0}px)');
      expect(game.player.position.y, greaterThan(parkedCar.position.y),
          reason: 'no tunnelling: the parked car is still ahead');

      // --- Dismissing the pause menu resumes cleanly ---
      final timerAfterResume = staged.timerNow(game);
      game.resumeGame();
      expect(game.paused, isFalse);
      expect(game.overlays.isActive('pauseMenu'), isFalse);
      expect(game.isGameActive, isTrue);

      game.update(1 / 60);
      expect(staged.timerNow(game),
          closeTo(timerAfterResume - 1 / 60, 1e-9),
          reason: 'the countdown is burning again at live rate');

      // And the shift still plays: the boarded fare delivers normally.
      deliverFare(game, game.course!.fare(1));
      expect(game.faresDelivered, 2,
          reason: 'the interrupted fare still settles');
      expect(game.isGameActive, isTrue);
    });

    test('a transient inactive (shade pull) freezes a live run the same '
        'way', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      game.lifecycleStateChange(AppLifecycleState.inactive);
      expect(game.paused, isTrue);
      expect(game.overlays.isActive('pauseMenu'), isFalse,
          reason: 'nothing is on screen yet — the freeze is silent');

      game.lifecycleStateChange(AppLifecycleState.resumed);
      expect(game.paused, isTrue);
      expect(game.overlays.isActive('pauseMenu'), isTrue);
      expect(game.isGameActive, isTrue);

      game.resumeGame();
      expect(game.isGameActive, isTrue);
    });

    test('backgrounding while already paused changes nothing, and a '
        'settled shift is never hijacked by the menu', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // The player paused by hand, then backgrounded from the menu.
      game.pauseGame();
      expect(game.overlays.isActive('pauseMenu'), isTrue);

      game.lifecycleStateChange(AppLifecycleState.hidden);
      game.lifecycleStateChange(AppLifecycleState.resumed);

      expect(game.paused, isTrue, reason: 'the manual pause stands');
      expect(game.overlays.isActive('pauseMenu'), isTrue,
          reason: 'the same menu — no auto-pause stacked on top of it');
      expect(game.isGameActive, isTrue);

      game.resumeGame();
      expect(game.isGameActive, isTrue, reason: 'the shift plays on');

      // A settled shift (banked at the dropoff) has nothing live left to
      // protect: backgrounding it must not flag an auto-pause, so the
      // return puts no pause menu over the summary panel.
      deliverFare(game, game.course!.fare(0));
      game.bankShift();
      expect(game.isGameActive, isFalse, reason: 'precondition: banked');

      game.lifecycleStateChange(AppLifecycleState.hidden);
      game.lifecycleStateChange(AppLifecycleState.resumed);

      expect(game.overlays.isActive('pauseMenu'), isFalse,
          reason: 'the banked panel is the screen; no pause menu on top');
      expect(game.isGameActive, isFalse);
    });
  });

  group('backgrounding during the post-crash freeze (issue #141)', () {
    test('the auto-pause arms on the stall, and the shift never resumes '
        'on its own under the menu', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // Spend a life the way the clamp test does: a survivable crash
      // with its impact freeze armed, exactly what a judged collision
      // produces. The stall holds the world, the shift is not over, and
      // [TaxiGame.isGameActive] is false for the whole freeze — the
      // state the old _isRunLive gate read as "nothing live to
      // protect".
      game.onCrash();
      game.hitStop.trigger();
      expect(game.isCrashStall, isTrue, reason: 'the post-crash freeze');
      expect(game.isGameActive, isFalse,
          reason: 'the stall holds the world still');
      expect(game.isShiftOver, isFalse,
          reason: 'a survivable crash: the shift continues after it');

      // --- The app goes to the background mid-freeze (call, shade) ---
      game.lifecycleStateChange(AppLifecycleState.hidden);

      expect(game.paused, isTrue,
          reason: 'the freeze counts as live: the auto-pause arms');
      expect(game.overlays.isActive('pauseMenu'), isFalse,
          reason: 'still silent — no menu over a street nobody can see');

      // --- The app returns; the ticker carries the absence as one dt ---
      game.lifecycleStateChange(AppLifecycleState.resumed);

      expect(game.paused, isTrue,
          reason: 'the deliberate re-entry gate, same as a live run');
      expect(game.overlays.isActive('pauseMenu'), isTrue,
          reason: 'the pause menu is the way back in');
      expect(game.isGameActive, isFalse,
          reason: 'the shift has not silently restarted under the menu');

      // The resumed frame delivers the absent gap as one dt. Clamped, it
      // must not finish the freeze and hand the shift to live traffic
      // while the player is still reading the menu — the self-restart
      // the issue reported.
      game.update(30.0);
      expect(game.isCrashStall, isTrue,
          reason: 'the stall did not silently complete');
      expect(game.isGameActive, isFalse,
          reason: 'no live play the player did not choose');

      // --- Deliberate re-entry: the freeze finishes and hands the
      // shift back where the crash left it ---
      game.resumeGame();
      expect(game.paused, isFalse);
      expect(game.overlays.isActive('pauseMenu'), isFalse);

      // 1.5 s of live ticks: the hit-stop remainder (0.10 s minus the
      // clamped frame) plus the 1.2 s stall, with margin.
      for (var i = 0; i < 90; i++) {
        game.update(1 / 60);
      }
      expect(game.isCrashStall, isFalse, reason: 'the stall has run out');
      expect(game.isGameActive, isTrue,
          reason: 'the shift resumes where the crash left it — chosen, '
              'not automatic');
      expect(game.lives.remaining, 2, reason: 'the one life the crash cost');
    });
  });

  group('the dt clamp (issue #36)', () {
    test('one frame may never consume more than maxUpdateDelta, even '
        'carrying raw engine time', () async {
      expect(TaxiGame.maxUpdateDelta, closeTo(1 / 15, 1e-9));

      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // The bank window is open and the taxi is at speed when a frame
      // carrying the whole backgrounded gap arrives — say the lifecycle
      // event was lost and the ticker kept counting.
      deliverFare(game, game.course!.fare(0));
      const speed = 280.0;
      game.player.velocity = Vector2(0, -speed);
      final playerY = game.player.position.y;
      final bankSeconds = game.bankPrompt.remainingSeconds;

      game.update(30.0);

      expect(game.bankPrompt.isActive, isTrue,
          reason: 'the 5 s window cannot expire inside one clamped frame');
      expect(game.bankPrompt.remainingSeconds,
          closeTo(bankSeconds - TaxiGame.maxUpdateDelta, 1e-9));
      expect(playerY - game.player.position.y,
          lessThan(TaxiGame.maxUpdateDelta * speed),
          reason: 'no frame moves the taxi further than one clamped step');
    });

    test('a giant dt cannot drain a crash stall or its hit-stop in one '
        'frame', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // Spend a life: the shift stalls while the impact freeze plays.
      game.onCrash();
      expect(game.isGameActive, isFalse, reason: 'the stall holds');
      // The impact freeze — in production armed by _spawnCrashFx when the
      // report carries telemetry; armed here the same way.
      game.hitStop.trigger();
      expect(game.hitStop.isActive, isTrue,
          reason: 'the impact freeze plays first');
      final hitStopLeft = game.hitStop.remaining;

      game.update(30.0);
      expect(game.hitStop.remaining,
          closeTo(hitStopLeft - TaxiGame.maxUpdateDelta, 1e-9),
          reason: 'the hit-stop drains one clamped frame, not 30 s');
      expect(game.hitStop.isActive, isTrue,
          reason: 'the freeze survives the absent seconds');
      expect(game.isGameActive, isFalse,
          reason: 'the 1.2 s crash stall did not silently complete — '
              'an unclamped 30 s frame would have ended it and resumed '
              'the shift');
    });
  });
}
