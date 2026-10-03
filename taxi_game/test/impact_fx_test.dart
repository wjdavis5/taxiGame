import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/burst_particles.dart';
import 'package:taxi_game/game/components/coin_pop.dart';
import 'package:taxi_game/game/components/dropoff_zone.dart';
import 'package:taxi_game/game/components/pickup_zone.dart';
import 'package:taxi_game/game/components/speed_lines.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/systems/impact_fx.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/widgets/hud_overlay.dart';

/// Mounts [game] headlessly (the pattern flame_test uses) so component
/// `onLoad` hooks run, then returns it.

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
  await game.ready();
  return game;
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
  });

  /// A headless game has no overlay builder map — register stand-ins so
  /// the crash/complete paths can add overlays without tripping Flame's
  /// unknown-overlay assertion.
  TaxiGame freshGame() => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry(
            'levelComplete', (_, __) => const SizedBox.shrink());

  /// A bus standing still at [position] (zero speed, so tests control the
  /// closing geometry exactly).
  TrafficVehicle parkedBus(Vector2 position) => TrafficVehicle(
        position: position.clone(),
        vehicleType: TrafficVehicleType.bus,
        baseSpeed: 0,
        path: [position.clone(), Vector2(position.x, position.y - 3000)],
      );

  /// An oncoming bus driving down-screen at exactly [speed] px/s.
  TrafficVehicle oncomingBus(Vector2 position, double speed) => TrafficVehicle(
        position: position.clone(),
        vehicleType: TrafficVehicleType.bus,
        baseSpeed: speed / 0.6, // undo the bus type's speed multiplier
        path: [
          Vector2(position.x, position.y + 3000),
          Vector2(position.x, position.y + 3001),
        ],
      );

  group('ImpactFx tuning math', () {
    test('crash shake scales with impact speed and clamps', () {
      expect(ImpactFx.crashShakeMagnitudeFor(0), 0);
      expect(ImpactFx.crashShakeMagnitudeFor(130),
          closeTo(ImpactFx.crashShakeMagnitude / 2, 1e-9));
      expect(ImpactFx.crashShakeMagnitudeFor(ImpactFx.fullShakeClosingSpeed),
          ImpactFx.crashShakeMagnitude);
      // Beyond the reference speed the magnitude is clamped...
      expect(ImpactFx.crashShakeMagnitudeFor(10000),
          ImpactFx.crashShakeMagnitude);
      // ...and the ramp is monotonically increasing up to it.
      expect(ImpactFx.crashShakeMagnitudeFor(100),
          lessThan(ImpactFx.crashShakeMagnitudeFor(200)));
    });

    test('speed-line intensity only appears at speed and clamps', () {
      expect(ImpactFx.speedLineIntensityFor(0), 0);
      expect(ImpactFx.speedLineIntensityFor(ImpactFx.speedLinesStartSpeed), 0);
      expect(
        ImpactFx.speedLineIntensityFor(
          (ImpactFx.speedLinesStartSpeed + ImpactFx.speedLinesFullSpeed) / 2,
        ),
        closeTo(0.5, 1e-9),
      );
      expect(ImpactFx.speedLineIntensityFor(ImpactFx.speedLinesFullSpeed), 1);
      expect(ImpactFx.speedLineIntensityFor(1000), 1);
    });
  });

  group('ShakeEnvelope', () {
    test('offsets stay bounded by the magnitude and decay to zero', () {
      final shake = ShakeEnvelope(random: math.Random(7));
      shake.trigger(10, duration: 0.3);

      var maxOffset = 0.0;
      var frames = 0;
      while (shake.isActive) {
        final offset = shake.update(1 / 60);
        maxOffset = math.max(maxOffset, offset.length);
        frames++;
      }
      expect(maxOffset, greaterThan(0));
      expect(maxOffset, lessThanOrEqualTo(10.0 + 1e-9));
      expect(frames, greaterThan(0));

      // Once decayed the envelope reports idle and applies no offset.
      expect(shake.isActive, isFalse);
      expect(shake.update(1 / 60), Vector2.zero());
    });

    test('is deterministic under a fixed seed', () {
      final a = ShakeEnvelope(random: math.Random(11))
        ..trigger(8, duration: 0.3);
      final b = ShakeEnvelope(random: math.Random(11))
        ..trigger(8, duration: 0.3);

      for (var i = 0; i < 10; i++) {
        expect(a.update(1 / 60), b.update(1 / 60));
      }
    });

    test('a zero-magnitude trigger is ignored, and reset clears everything',
        () {
      final shake = ShakeEnvelope(random: math.Random(3));
      shake.trigger(0);
      expect(shake.isActive, isFalse);

      shake.trigger(5);
      expect(shake.isActive, isTrue);
      shake.reset();
      expect(shake.isActive, isFalse);
      expect(shake.update(1 / 60), Vector2.zero());
    });
  });

  group('HitStop', () {
    test('freezes for its duration, then deactivates', () {
      final hitStop = HitStop();
      expect(hitStop.isActive, isFalse);

      hitStop.trigger();
      expect(hitStop.isActive, isTrue);
      expect(hitStop.remaining, ImpactFx.crashHitStopDuration);

      hitStop.update(ImpactFx.crashHitStopDuration / 2);
      expect(hitStop.isActive, isTrue);

      hitStop.update(ImpactFx.crashHitStopDuration);
      expect(hitStop.isActive, isFalse);
      expect(hitStop.remaining, 0);
      // Updating while idle stays idle.
      hitStop.update(1);
      expect(hitStop.remaining, 0);
    });
  });

  group('BurstParticles', () {
    test('spawns its particles and removes itself when they are spent',
        () async {
      final game = await mountGame(freshGame());
      final burst = BurstParticles(
        position: Vector2(200, 400),
        colors: ImpactFxPalettes.pickup,
        count: 9,
        random: math.Random(5),
      );
      game.world.add(burst);
      await game.ready();

      expect(burst.liveParticles, 9);

      // Particles live at most [lifetime]; past that the burst is gone.
      burst.update(BurstParticles.defaultLifetime + 0.01);
      expect(burst.parent, isNull);
      expect(game.world.children.whereType<BurstParticles>(), isEmpty);
    });

    test('an early update leaves every particle alive', () async {
      final game = await mountGame(freshGame());
      final burst = BurstParticles(
        position: Vector2(200, 400),
        colors: ImpactFxPalettes.crash,
        count: 6,
        random: math.Random(2),
      );
      game.world.add(burst);
      await game.ready();

      burst.update(0.05);
      expect(burst.liveParticles, 6);
    });
  });

  group('CoinPop', () {
    /// The world point the coin aims at when no HUD has published a chip
    /// rect (issue #188's fallback): the fixed top-right inset of the
    /// visible world. Headless games never measure a chip, so this is
    /// what their coins home on.
    Vector2 hudTarget(TaxiGame game) {
      final visible = game.camera.visibleWorldRect;
      return Vector2(
        visible.right - CoinPop.hudInsetX,
        visible.top + CoinPop.hudInsetY,
      );
    }

    test('waits out its delay before flying, then lands and removes itself',
        () async {
      final game = await mountGame(freshGame());
      final start = Vector2(200, 400);
      final coin = CoinPop(
        startPosition: start,
        delay: 0.5,
        random: math.Random(9),
      );
      game.world.add(coin);
      await game.ready();

      // Still waiting: it has not moved while its delay burns off.
      coin.update(0.2);
      expect(coin.position, start);
      coin.update(0.29); // delay now nearly spent
      expect(coin.position, start);

      // Once airborne it leaves the spawn point, and it removes itself
      // once the flight completes.
      coin.update(0.1);
      expect(coin.position, isNot(start));
      coin.update(CoinPop.flightDuration + 0.01);
      expect(coin.parent, isNull);
    });

    test('flies to the world point under the fixed inset while no chip is '
        'measured (the fallback)', () async {
      final game = await mountGame(freshGame());
      expect(game.coinChipGlobalRect, isNull,
          reason: 'sanity: a headless game has never measured a chip');
      final start = Vector2(200, 400);
      final target = hudTarget(game);
      final coin = CoinPop(
        startPosition: start,
        random: math.Random(4),
      );
      game.world.add(coin);
      await game.ready();

      // Mid-flight the coin is on its way — away from the spawn, not yet
      // at the counter.
      coin.update(CoinPop.flightDuration / 2);
      expect(coin.position, isNot(start));
      expect(coin.position.distanceTo(target), isPositive);

      // It lands exactly at the counter and detaches.
      coin.update(CoinPop.flightDuration);
      expect(coin.position, target);
      expect(coin.parent, isNull);
    });

    test('the fallback homing leg closes on the counter monotonically',
        () async {
      final game = await mountGame(freshGame());
      final target = hudTarget(game);
      final coin = CoinPop(
        startPosition: Vector2(200, 400),
        random: math.Random(4),
      );
      game.world.add(coin);
      await game.ready();

      // Past the scatter portion, every tick is closer than the last.
      coin.update(CoinPop.flightDuration * CoinPop.scatterPortion + 0.01);
      var previous = coin.position.distanceTo(target);
      while (coin.parent != null) {
        coin.update(1 / 60);
        final current = coin.position.distanceTo(target);
        expect(current, lessThanOrEqualTo(previous));
        previous = current;
      }
      expect(coin.position, target);
    });

    test('homes on the HUD\'s measured chip the moment one is published',
        () async {
      final game = await mountGame(freshGame());
      // A chip parked mid-row, nowhere near the fixed top-right inset —
      // the issue's whole geometry: the real chip sits 60-160 px from
      // where the fallback aims (usually on the pause button).
      const chip = Rect.fromLTWH(140, 76, 90, 37);
      game.coinChipGlobalRect = chip;
      final target = game.camera.globalToLocal(
        Vector2(chip.center.dx, chip.center.dy),
      );
      final fallback = hudTarget(game);
      expect(target, isNot(fallback),
          reason: 'sanity: the measured chip is genuinely elsewhere');

      final coin = CoinPop(
        startPosition: Vector2(200, 400),
        random: math.Random(4),
      );
      game.world.add(coin);
      await game.ready();

      coin.update(CoinPop.flightDuration);
      expect(coin.position.x, closeTo(target.x, 1e-6));
      expect(coin.position.y, closeTo(target.y, 1e-6));
      expect(coin.parent, isNull);
    });

    test('same seed, same flight', () async {
      final game = await mountGame(freshGame());
      final a = CoinPop(
        startPosition: Vector2(150, 50),
        random: math.Random(21),
      )..addToParent(game.world);
      final b = CoinPop(
        startPosition: Vector2(150, 50),
        random: math.Random(21),
      )..addToParent(game.world);
      await game.ready();

      for (var i = 0; i < 20; i++) {
        a.update(1 / 60);
        b.update(1 / 60);
        expect(a.position, b.position);
      }
    });
  });

  group('SpeedLines', () {
    test('streaks stream down only while intensity is up', () async {
      final game = await mountGame(freshGame());
      final lines =
          game.camera.viewport.children.whereType<SpeedLines>().single;

      expect(lines.streakCount, 16);

      // Idle: nothing moves.
      lines.update(0.001);
      final idle = lines.streakYs.toList();
      lines.update(0.001);
      expect(lines.streakYs, idle);

      // At full intensity every streak advances down the screen.
      lines.intensity = 1;
      final before = lines.streakYs.toList();
      lines.update(0.001);
      final after = lines.streakYs.toList();
      for (var i = 0; i < after.length; i++) {
        expect(after[i], greaterThan(before[i]));
      }
    });

    test('is mounted on the camera viewport, not the world', () async {
      final game = await mountGame(freshGame());
      expect(
        game.camera.viewport.children.whereType<SpeedLines>(),
        isNotEmpty,
      );
      expect(game.world.children.whereType<SpeedLines>(), isEmpty);
    });
  });

  group('FX wiring in TaxiGame', () {
    test('a pickup bursts green without touching the camera', () async {
      final game = await mountGame(freshGame());
      final player = game.player;
      player.velocity = Vector2.zero();

      final pickup = game.world.children.whereType<PickupZone>().first;
      player.position = pickup.position.clone();
      pickup.onCollisionStart({pickup.position.clone()}, player);

      expect(game.world.children.whereType<BurstParticles>().length, 1);
      expect(game.world.children.whereType<CoinPop>(), isEmpty);
      expect(game.shake.isActive, isFalse);
      expect(game.hitStop.isActive, isFalse);
    });

    test('a dropoff bursts, pops coins at the HUD, and completes the level',
        () async {
      final game = await mountGame(freshGame());
      final player = game.player;
      player.velocity = Vector2.zero();

      final pickup = game.world.children.whereType<PickupZone>().first;
      player.position = pickup.position.clone();
      pickup.onCollisionStart({pickup.position.clone()}, player);

      // Let the dropoff zone notice the passenger is aboard.
      game.update(1 / 60);
      final dropoff = game.world.children.whereType<DropoffZone>().first;
      player.position = dropoff.position.clone();
      dropoff.onCollisionStart({dropoff.position.clone()}, player);

      // Pickup burst still airborne + the dropoff burst.
      expect(game.world.children.whereType<BurstParticles>().length, 2);
      // Three dropoff coins plus the six-coin level-complete volley.
      expect(game.world.children.whereType<CoinPop>().length, 9);
      expect(game.overlays.activeOverlays, contains('levelComplete'));
    });

    test('a crash bursts sparks, shakes hard, freezes time, and defers the '
        'failure overlay until the hit-stop ends', () async {
      final game = await mountGame(freshGame());
      final player = game.player;

      // Taxi flat out (150) into an oncoming bus (60): 210 px/s closing.
      player.position = Vector2(200, 100);
      player.velocity = Vector2(0, -150);
      final bus = oncomingBus(Vector2(200, 40), 60);
      game.world.add(bus);
      await game.ready();

      player.onCollisionStart({Vector2(200, 70)}, bus);

      // Impact juice: sparks at the contact point, shake scaled to the
      // closing speed, and the world frozen.
      expect(game.world.children.whereType<BurstParticles>().length, 1);
      expect(game.shake.isActive, isTrue);
      expect(game.shake.magnitude,
          closeTo(ImpactFx.crashShakeMagnitudeFor(210), 1e-9));
      expect(game.hitStop.isActive, isTrue);

      // The overlay waits for the hit-stop...
      expect(game.overlays.activeOverlays, isNot(contains('levelFailed')));
      advanceGameTime(game, ImpactFx.crashHitStopDuration + 0.01);
      expect(game.overlays.activeOverlays, contains('levelFailed'));

      // ...and the shake outlives the hit-stop.
      expect(game.shake.isActive, isTrue);
    });

    test('shake jitters the viewport and restores it when done', () async {
      final game = await mountGame(freshGame());
      await game.ready();

      final base = game.camera.viewport.position.clone();
      game.shake.trigger(12, duration: 0.3);

      var moved = false;
      var guard = 0;
      while (game.shake.isActive && guard < 600) {
        game.update(1 / 60);
        if (game.camera.viewport.position != base) moved = true;
        guard++;
      }
      game.update(1 / 60); // final idle tick applies the zero offset

      expect(moved, isTrue);
      // The delta-on-viewport scheme leaves no residue (within float
      // tolerance of many add/subtract round trips).
      expect(game.camera.viewport.position.x, closeTo(base.x, 1e-6));
      expect(game.camera.viewport.position.y, closeTo(base.y, 1e-6));
    });

    test('a scrape sheds sparks and jolts, but never stops time', () async {
      final game = await mountGame(freshGame());
      final player = game.player;
      player.position = Vector2(200, 100);
      player.velocity = Vector2(0, -40);
      final bus = parkedBus(Vector2(200, 80));
      game.world.add(bus);
      await game.ready();

      player.onCollisionStart({Vector2(200, 90)}, bus);

      expect(game.world.children.whereType<BurstParticles>().length, 1);
      expect(game.shake.isActive, isTrue);
      expect(game.shake.magnitude, ImpactFx.scrapeShakeMagnitude);
      expect(game.hitStop.isActive, isFalse);
      expect(game.isGameActive, isTrue);
    });

    test('speed lines track the taxi\'s forward speed and die with the run',
        () async {
      final game = await mountGame(freshGame());
      final lines =
          game.camera.viewport.children.whereType<SpeedLines>().single;
      final player = game.player;

      // Standing still: no lines.
      player.velocity = Vector2.zero();
      game.update(1 / 60);
      expect(lines.intensity, 0);

      // Flat out and accelerating (so velocity holds at max): full lines.
      player.startAccelerating();
      player.velocity = Vector2(0, -150);
      game.update(1 / 60);
      expect(lines.intensity, 1);
    });

    test('loading a level clears leftover juice', () async {
      final game = await mountGame(freshGame());
      final player = game.player;

      // Crash: the failure overlay is deferred behind the hit-stop...
      player.position = Vector2(200, 100);
      player.velocity = Vector2(0, -150);
      final bus = oncomingBus(Vector2(200, 40), 60);
      game.world.add(bus);
      await game.ready();
      player.onCollisionStart({Vector2(200, 70)}, bus);
      expect(game.hitStop.isActive, isTrue);

      // ...but reloading the level first must discard it, along with the
      // frozen time and the shake.
      await game.loadLevel(1);
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }

      expect(game.shake.isActive, isFalse);
      expect(game.hitStop.isActive, isFalse);
      expect(game.overlays.activeOverlays, isNot(contains('levelFailed')));
    });
  });

  group('HUD coin counter', () {
    testWidgets('pulses when coins are awarded, then settles', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<GameStateService>.value(
          value: gameState,
          child: MaterialApp(
            home: Scaffold(
              body: HudOverlay(
                game: TaxiGame(
                  levelLoader: LevelLoaderService(),
                  gameState: gameState,
                ),
              ),
            ),
          ),
        ),
      );
      // A fixed pump, not pumpAndSettle: the HUD's scoring bar (issue #12)
      // polls the game on a repeating timer, so the frame never goes quiet.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('0'), findsOneWidget);

      gameState.addCoins(50);
      await tester.pump();

      // The counter shows the new total mid-pulse...
      expect(find.text('50'), findsOneWidget);
      final pulse = tester.widget<Transform>(
        find
            .ancestor(
              of: find.text('50'),
              matching: find.byType(Transform),
            )
            .first,
      );
      // Transform.scale stores the uniform scale in storage[0] (m11).
      expect(pulse.transform.storage[0], greaterThan(1.0));

      // ...and settles back to rest. (Fixed pump again — see above.)
      await tester.pump(const Duration(milliseconds: 300));
      final settled = tester.widget<Transform>(
        find
            .ancestor(
              of: find.text('50'),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(settled.transform.storage[0], closeTo(1.0, 1e-9));
    });

    testWidgets('delivery coins land in the measured chip, not the pause '
        'button (issue #188)', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // The issue's phones: a 375 pt one, a 393 pt one, a 430 pt one —
      // three widths, three chip positions the fixed inset missed by
      // 60-160 px. The HUD is pumped alone (the existing pattern above);
      // the game is resized to the same surface so the canvas and the
      // widget tree share one coordinate space, exactly as the GameWidget
      // and its overlays do in the real game screen's Stack.
      for (final size in const [
        Size(375, 667),
        Size(393, 852),
        Size(430, 932),
      ]) {
        tester.view.physicalSize = size;

        // Mounted in the real async zone (the repo's widget-test
        // pattern): game loading touches real I/O — the level bundle,
        // the audio cache warm — which never completes in the tester's
        // fake-async zone on its own.
        final game = (await tester.runAsync<TaxiGame>(() async {
          final game = TaxiGame(
            levelLoader: LevelLoaderService(),
            gameState: gameState,
          );
          game.onGameResize(Vector2(size.width, size.height));
          await game.onLoad();
          await game.ready();
          return game;
        }))!;

        await tester.pumpWidget(
          ChangeNotifierProvider<GameStateService>.value(
            value: gameState,
            child: MaterialApp(
              home: Scaffold(body: HudOverlay(game: game)),
            ),
          ),
        );
        // Past the measurer's 100 ms tick — and past the next one after
        // a settled frame: pump fires timers *before* building the new
        // frame, so a tick always measures the last laid-out tree. The
        // pill's pulse starts at scale 1.3 on first build and settles at
        // 250 ms; a tick at 400 ms reads the *old* tree, so the second
        // pump crosses the 500 ms tick, which reads the settled
        // (scale 1.0) frame. Fixed pumps, not pumpAndSettle — the HUD
        // polls forever.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 200));

        final chip = game.coinChipGlobalRect;
        expect(chip, isNotNull,
            reason: 'the HUD published the chip rect at $size');
        expect(chip!.width, greaterThan(0), reason: 'chip rect at $size');
        expect(chip.height, greaterThan(0), reason: 'chip rect at $size');
        // Measured in the surface's own coordinates, not the fallback's
        // fixed inset: the chip sits inside the padded top row.
        expect(chip.top, greaterThanOrEqualTo(16),
            reason: 'chip rect at $size');
        expect(chip.right, lessThanOrEqualTo(size.width - 16),
            reason: 'chip rect at $size');

        // Fly a real coin to the published chip and read where it lands
        // on screen: inside the chip, outside the pause button beside
        // it. The world.add + ready hop runs in the real zone too. The
        // coin detaches itself on arrival, but its final position is
        // still read off the reference — that is the arrival point.
        late CoinPop coin;
        await tester.runAsync(() async {
          coin = CoinPop(
            startPosition: Vector2(200, 400),
            random: math.Random(4),
          );
          game.world.add(coin);
          await game.ready();
          coin.update(CoinPop.flightDuration);
        });
        expect(coin.parent, isNull,
            reason: 'the coin completed its flight at $size');
        final landed = game.camera.localToGlobal(coin.position);

        expect(chip.contains(Offset(landed.x, landed.y)), isTrue,
            reason: 'coin lands in the chip at $size (landed $landed, '
                'chip $chip)');
        final pauseRect = tester.getRect(find.byIcon(Icons.pause));
        expect(pauseRect.contains(Offset(landed.x, landed.y)), isFalse,
            reason: 'coin must not land on the pause button at $size '
                '(landed $landed, pause $pauseRect)');

        // Tearing the HUD down withdraws the measurement again.
        await tester.pumpWidget(const SizedBox.shrink());
        expect(game.coinChipGlobalRect, isNull,
            reason: 'dispose clears the published rect at $size');
      }
    });
  });
}
