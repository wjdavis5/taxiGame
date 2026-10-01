import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/burst_particles.dart';
import 'package:taxi_game/game/components/life_lost_pop.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/systems/collision_rules.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/impact_fx.dart';
import 'package:taxi_game/game/systems/lives.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/widgets/hud_overlay.dart';

/// Three-strike lives and the end-of-shift flow (issue #14): an endless
/// crash spends a life and breaks the chain, the world stalls and the
/// shift resumes, and the third crash ends the shift with everything
/// unbanked forfeit. The tutorial ladder keeps its level-fail behaviour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  /// Mounts [game] headlessly so component `onLoad` hooks run (the
  /// endless-run test pattern; [Game.mount] is what GameWidget calls in
  /// production).
  /// Advances game time by [seconds], in clamped frames (issue #36): no
  /// single frame may consume more than [TaxiGame.maxUpdateDelta], so
  /// fast-forwarding a shift means many small frames, never one giant
  /// one — exactly the invariant the live game now runs under.
  void advanceGameTime(TaxiGame game, double seconds) {
    var remaining = seconds;
    while (remaining > 0) {
      final step = math.min(remaining, TaxiGame.maxUpdateDelta);
      game.update(step);
      remaining -= step;
    }
  }

  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  /// Headless games have no overlay builder map; the crash flow adds
  /// 'levelFailed' in level mode or 'shiftWrecked' at the third endless
  /// crash, and a delivered fare arms 'bankOrPush' (issue #13), so
  /// register stand-ins as [GameScreen] does.
  TaxiGame endlessGame(int seed) => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: seed,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());

  TaxiGame levelGame() => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink());

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

  /// Delivers [fare] by teleporting the taxi to its kerbs, the way the
  /// endless-run tests do. Assumes the fare's zones are mounted.
  void deliverFare(TaxiGame game, EndlessFare fare) {
    game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
    game.update(1 / 60);
    expect(game.player.hasPassenger, isTrue, reason: 'passenger boarded');
    game.player.position = Vector2(fare.dropoff.x, fare.dropoff.y + 30);
    game.update(1 / 60);
  }

  /// Plays out the aftermath of a survivable crash: the crash hit-stop
  /// burns off first (issue #7), then the stall (issue #14) elapses and
  /// the shift resumes.
  void playOutStall(TaxiGame game) {
    advanceGameTime(game, ImpactFx.crashHitStopDuration + 0.01);
    advanceGameTime(game, TaxiGame.crashStallSeconds + 0.01);
  }

  /// An oncoming bus driving down-screen at exactly [speed] px/s, so the
  /// closing geometry is under test control.
  TrafficVehicle oncomingBus(Vector2 position, double speed) => TrafficVehicle(
        position: position.clone(),
        vehicleType: TrafficVehicleType.bus,
        baseSpeed: speed / 0.6, // undo the bus type's speed multiplier
        path: [
          Vector2(position.x, position.y + 3000),
          Vector2(position.x, position.y + 3001),
        ],
      );

  /// A full crash telemetry record, as a real collision would carry (the
  /// report is what arms the crash hit-stop that defers the panel).
  CrashReport busCrash() => CollisionRules.buildReport(
        severity: ContactSeverity.crash,
        vehicleKind: 'bus',
        playerVelocity: Vector2(0, -150),
        playerPosition: Vector2(200, 100),
        trafficVelocity: Vector2(0, 60),
        trafficPosition: Vector2(200, 40),
        contactPoint: Vector2(199.5, 70),
      );

  group('the crash feedback names the spent life', () {
    test('a survivable crash pops -1 LIFE over the frozen taxi', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      game.onCrash(busCrash());
      // The pop and the sparks ride the freeze itself (issue #106): the
      // frozen frames drain Flame's add queue on their own and tick only
      // the burst, so both are on screen at the moment of impact — not
      // 1.3 s late, the instant the shift resumes. Mid-freeze — past the
      // hit-stop, deep in the stall — the pop hangs over the taxi and
      // the burst is burning down. (The drain between the two advances
      // is the microtask break a real frame boundary gives the async
      // mount.)
      advanceGameTime(game, 0.42);
      await drain();
      advanceGameTime(game, 0.05);
      expect(game.isGameActive, isFalse,
          reason: 'precondition: the world is still frozen');
      final sparks = game.descendants().whereType<BurstParticles>().single;
      expect(sparks.liveParticles, greaterThan(0),
          reason: 'the burst is still burning mid-freeze');
      expect(sparks.liveParticles, lessThan(18),
          reason: 'the burst is aging through the freeze — mounted and '
              'ticked, not queued for the resume');
      final pops = game.descendants().whereType<LifeLostPop>().toList();
      expect(pops, hasLength(1),
          reason: 'the stall alone is not an explanation — the cost is');
      expect(pops.single.text, contains('-1 LIFE'));
      expect(pops.single.text, contains('2 LEFT'),
          reason: 'the pop says how much of the budget survives');

      // The freeze plays out and the pop is the same one the crash
      // mounted — held static through the stall, rising only once the
      // shift resumes.
      playOutStall(game);
      await tickAndSettle(game);
      final after = game.descendants().whereType<LifeLostPop>().toList();
      expect(after, hasLength(1));
      expect(after.single, same(pops.single),
          reason: 'the freeze never re-mounted or replaced the pop');
    });

    test('the third crash adds no pop of its own — the panel speaks',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      game.onCrash();
      playOutStall(game);
      await tickAndSettle(game);
      game.onCrash();
      playOutStall(game);
      await tickAndSettle(game);
      game.onCrash(busCrash());

      expect(
        game.descendants().whereType<LifeLostPop>(),
        hasLength(2),
        reason: 'the first two crashes each popped; the wreck panel is '
            'the third crash\'s explanation',
      );
    });

    test('the pop rises away once the world resumes', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      game.onCrash(busCrash());
      playOutStall(game);
      await tickAndSettle(game);
      expect(game.descendants().whereType<LifeLostPop>(), isNotEmpty);

      advanceGameTime(game, LifeLostPop.lifetime + 0.1);
      expect(game.descendants().whereType<LifeLostPop>(), isEmpty,
          reason: 'like every award pop, it removes itself');
    });
  });

  group('LivesTracker', () {
    test('a shift starts with a full budget of three', () {
      final lives = LivesTracker();

      expect(LivesTracker.maxLives, 3);
      expect(lives.remaining, 3);
      expect(lives.isLastLife, isFalse);
      expect(lives.isExhausted, isFalse);
    });

    test('each spend costs one life and the last one is flagged', () {
      final lives = LivesTracker();

      expect(lives.spend(), 2);
      expect(lives.isLastLife, isFalse);

      expect(lives.spend(), 1);
      expect(lives.isLastLife, isTrue,
          reason: 'the next crash ends the shift');
      expect(lives.isExhausted, isFalse);

      expect(lives.spend(), 0);
      expect(lives.isExhausted, isTrue);
    });

    test('spending past zero floors at zero', () {
      final lives = LivesTracker()..spend()..spend()..spend();

      expect(lives.spend(), 0, reason: 'a double ruling cannot go negative');
      expect(lives.remaining, 0);
    });

    test('reset refills the budget for a fresh shift', () {
      final lives = LivesTracker()..spend()..spend()..spend();
      expect(lives.isExhausted, isTrue);

      lives.reset();

      expect(lives.remaining, LivesTracker.maxLives);
      expect(lives.isExhausted, isFalse);
    });
  });

  group('a crash in an endless shift', () {
    test('the first crash spends a life and breaks the chain, and the '
        'shift stalls', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final coinsBefore = gameState.totalCoins;

      // Something to lose: a delivered fare arms a 2x chain.
      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      expect(game.fareChain.multiplier, 2);

      game.onCrash();

      expect(game.lives.remaining, LivesTracker.maxLives - 1);
      expect(game.fareChain.multiplier, 1,
          reason: 'the crash resets the chain multiplier to 1x');
      expect(game.fareChain.score, fare0.reward,
          reason: 'the unbanked score survives the crash');
      expect(gameState.totalCoins, coinsBefore + fare0.reward,
          reason: 'and it has not been paid out');
      expect(game.isGameActive, isFalse,
          reason: 'the world stalls before the shift resumes');

      // No end-of-shift panel, and never the level-fail one.
      expect(game.overlays.activeOverlays, isEmpty);
    });

    test('the stall resumes the shift: the next fare pays at 1x',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      expect(game.fareChain.multiplier, 2);

      game.onCrash();
      expect(game.isGameActive, isFalse);

      playOutStall(game);

      expect(game.isGameActive, isTrue,
          reason: 'the stall ends and the shift resumes');
      expect(game.overlays.activeOverlays, isEmpty);

      // The course kept its place: the next fare is waiting, and with
      // the chain broken it pays value x 1.
      await tickAndSettle(game);
      final fare1 = game.course!.fare(1);
      deliverFare(game, fare1);
      expect(game.score, fare0.reward + fare1.reward);
      expect(game.fareChain.multiplier, 2, reason: 'the chain rebuilds');
    });

    test('each crash costs exactly one life', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      game.onCrash();
      playOutStall(game);
      expect(game.lives.remaining, 2);

      game.onCrash();
      playOutStall(game);
      expect(game.lives.remaining, 1);
      expect(game.lives.isLastLife, isTrue);
      expect(game.isGameActive, isTrue,
          reason: 'two strikes and the shift is still alive');
      expect(game.overlays.activeOverlays, isEmpty);
    });

    test('a crash is not judged while the stall holds the world', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      game.onCrash();
      expect(game.lives.remaining, 2);

      game.onCrash();

      expect(game.lives.remaining, 2,
          reason: 'the shift is frozen; there is nothing left to crash');
    });

    test('the third crash ends the shift and forfeits everything unbanked',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final coinsBefore = gameState.totalCoins;

      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      expect(game.score, fare0.reward);

      game.onCrash();
      playOutStall(game);
      game.onCrash();
      playOutStall(game);
      // The final crash carries its telemetry, like a real collision:
      // the impact juice fires and the wreck panel defers behind the
      // hit-stop (issue #7).
      game.onCrash(busCrash());

      expect(game.lives.remaining, 0);
      expect(game.isGameActive, isFalse, reason: 'the shift is over');
      expect(game.player.isAccelerating, isFalse,
          reason: 'the taxi is frozen for good');

      // The wreck panel waits out the crash hit-stop (issue #7), like
      // the level-fail panel always has.
      expect(game.overlays.isActive('shiftWrecked'), isFalse);
      advanceGameTime(game, ImpactFx.crashHitStopDuration + 0.01);
      expect(game.overlays.isActive('shiftWrecked'), isTrue);
      expect(game.overlays.isActive('levelFailed'), isFalse,
          reason: 'endless shifts never show the level-fail panel');

      // The forfeit: only the fare's base coins ever reached the wallet.
      // The score — worth exactly as many coins at the bank window —
      // died with the shift.
      expect(gameState.totalCoins, coinsBefore + fare0.reward);
    });

    test('a crash kills the open bank prompt without paying it out',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      expect(game.bankPrompt.isActive, isTrue);
      expect(game.fareChain.multiplier, 2);

      game.onCrash();

      expect(game.bankPrompt.isActive, isFalse);
      expect(game.overlays.isActive('bankOrPush'), isFalse);
      expect(game.fareChain.multiplier, 1,
          reason: 'the dismissal charges the chain, not a push bonus');
    });

    test('no further crash is judged once the shift is over', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      game.onCrash();
      playOutStall(game);
      game.onCrash();
      playOutStall(game);
      game.onCrash();
      advanceGameTime(game, ImpactFx.crashHitStopDuration + 0.01);
      expect(game.overlays.isActive('shiftWrecked'), isTrue);

      game.onCrash();

      expect(game.lives.remaining, 0);
      expect(game.isGameActive, isFalse);
      expect(game.overlays.isActive('shiftWrecked'), isTrue,
          reason: 'the dead shift cannot fail again');
    });

    test('a fresh shift refills the budget', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      game.onCrash();
      playOutStall(game);
      expect(game.lives.remaining, 2);

      // What the DRIVE AGAIN button does: tear the panel down, start a
      // new shift with a new seed.
      game.overlays.remove('shiftWrecked');
      await game.startEndlessRun(seed: 43);

      expect(game.lives.remaining, LivesTracker.maxLives);
      expect(game.lives.isExhausted, isFalse);
      expect(game.fareChain.score, 0);
      expect(game.fareChain.multiplier, 1);
      expect(game.isGameActive, isTrue);
    });
  });

  group('the crash is routed per mode', () {
    test('a real collision in an endless shift spends a life', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final player = game.player;

      // Taxi flat out (150) into an oncoming bus (60): 210 px/s closing,
      // a crash by the fairness rule (issue #6).
      player.velocity = Vector2(0, -150);
      final bus = oncomingBus(Vector2(200, -40), 60);
      game.world.add(bus);
      await game.ready();

      player.onCollisionStart({Vector2(200, -20)}, bus);

      expect(game.lastImpact, isNotNull);
      expect(game.lives.remaining, LivesTracker.maxLives - 1,
          reason: 'the judged crash went through the three-strike flow');
      expect(game.hitStop.isActive, isTrue, reason: 'the impact juice fired');
      expect(game.isGameActive, isFalse, reason: 'then the stall took over');
      expect(game.overlays.activeOverlays, isEmpty,
          reason: 'one crash is not the end of the shift');
    });

    test('a level crash still fails the level and never spends a life',
        () async {
      final game = await mountGame(levelGame());
      final player = game.player;

      player.velocity = Vector2(0, -150);
      final bus = oncomingBus(Vector2(200, 40), 60);
      game.world.add(bus);
      await game.ready();

      player.onCollisionStart({Vector2(200, 70)}, bus);

      expect(game.isGameActive, isFalse,
          reason: 'the tutorial ladder keeps its own behaviour: one '
              'crash fails the level');
      expect(game.lives.remaining, LivesTracker.maxLives);

      advanceGameTime(game, ImpactFx.crashHitStopDuration + 0.01);
      expect(game.overlays.isActive('levelFailed'), isTrue);
      expect(game.overlays.isActive('shiftWrecked'), isFalse);
    });
  });

  group('the HUD lives badge', () {
    Widget hudFor(TaxiGame game) =>
        ChangeNotifierProvider<GameStateService>.value(
          value: gameState,
          child: MaterialApp(home: Scaffold(body: HudOverlay(game: game))),
        );

    testWidgets('an endless shift shows all three lives', (tester) async {
      // Unmounted is fine: the badge only reads the budget.
      final game = endlessGame(5);
      await tester.pumpWidget(hudFor(game));
      await tester.pump(const Duration(milliseconds: 150)); // poll tick

      expect(find.byKey(const ValueKey('lives_badge')), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNWidgets(3));
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    });

    testWidgets('spent lives render hollow', (tester) async {
      final game = endlessGame(5)
        ..lives.spend()
        ..lives.spend();
      await tester.pumpWidget(hudFor(game));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byIcon(Icons.favorite), findsNWidgets(1));
      expect(find.byIcon(Icons.favorite_border), findsNWidgets(2));
    });

    testWidgets('a level run shows no lives badge', (tester) async {
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      );
      await tester.pumpWidget(hudFor(game));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byKey(const ValueKey('lives_badge')), findsNothing);
      expect(find.byIcon(Icons.favorite), findsNothing,
          reason: 'nothing on the ladder level reads as lives');
    });
  });
}
