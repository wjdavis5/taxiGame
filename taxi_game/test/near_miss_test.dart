import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/burst_particles.dart';
import 'package:taxi_game/game/components/close_call_pop.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/systems/fare_chain.dart';
import 'package:taxi_game/game/systems/impact_fx.dart';
import 'package:taxi_game/game/systems/lives.dart';
import 'package:taxi_game/game/systems/near_miss.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/passenger_data.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/game/vehicle_sprites.dart';

/// Close-call scoring (issue #23): the geometry a cleared pass is judged
/// on, the way its points ride the existing fare chain, and the pass
/// detection end to end on a live run.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NearMissRules geometry', () {
    final playerPosition = Vector2(200, 0);
    final playerSize = Vector2(40, 60);

    test('lateral gap is the edge-to-edge daylight between the bodies',
        () {
      // Lane spacing on the endless road: 100 px between centres, so two
      // 40-px bodies leave 60 px of daylight before anyone straddles.
      expect(
        NearMissRules.lateralGap(
          playerPosition: playerPosition,
          playerSize: playerSize,
          vehiclePosition: Vector2(150, -40),
          vehicleSize: Vector2(40, 60),
        ),
        10.0,
        reason: 'riding the lane border shaves to 10 px',
      );
      expect(
        NearMissRules.lateralGap(
          playerPosition: playerPosition,
          playerSize: playerSize,
          vehiclePosition: Vector2(250, -40),
          vehicleSize: Vector2(40, 60),
        ),
        10.0,
        reason: 'the gap is symmetric in x',
      );
      expect(
        NearMissRules.lateralGap(
          playerPosition: playerPosition,
          playerSize: playerSize,
          vehiclePosition: Vector2(210, -40),
          vehicleSize: Vector2(40, 60),
        ),
        -30.0,
        reason: 'overlapping bodies read negative',
      );
    });

    test('a tight pass at speed is a close call', () {
      expect(
        NearMissRules.isCloseCall(gap: 10, playerForwardSpeed: 150),
        isTrue,
      );
    });

    test('the gap window is bounded', () {
      // At the threshold a pass still counts; one px wider does not.
      expect(
        NearMissRules.isCloseCall(
            gap: NearMissRules.gapThreshold, playerForwardSpeed: 150),
        isTrue,
      );
      expect(
        NearMissRules.isCloseCall(
            gap: NearMissRules.gapThreshold + 0.5, playerForwardSpeed: 150),
        isFalse,
        reason: 'lane-keeping daylight is not a close call',
      );
    });

    test('a pass can sit slightly into the bodies and still count', () {
      // Contact is ruled on the tightened hitboxes (issue #6), so two
      // logical bodies can interleave a few px and both drive away.
      expect(
        NearMissRules.isCloseCall(gap: -1, playerForwardSpeed: 150),
        isTrue,
      );
      expect(
        NearMissRules.isCloseCall(gap: -NearMissRules.contactSlack + 0.5,
            playerForwardSpeed: 150),
        isTrue,
      );
      expect(
        NearMissRules.isCloseCall(gap: -NearMissRules.contactSlack,
            playerForwardSpeed: 150),
        isFalse,
        reason: 'deeper than the hitbox slack is an artefact, not a pass',
      );
    });

    test('a crawl never scores, however tight the pass', () {
      expect(
        NearMissRules.isCloseCall(gap: 2, playerForwardSpeed: 0),
        isFalse,
      );
      expect(
        NearMissRules.isCloseCall(gap: 2,
            playerForwardSpeed: NearMissRules.minPassSpeed - 1),
        isFalse,
      );
      expect(
        NearMissRules.isCloseCall(gap: 2,
            playerForwardSpeed: NearMissRules.minPassSpeed),
        isTrue,
      );
    });

    test('the speed floor is the speed-line floor', () {
      // "Fast enough to score" and "fast enough to look fast" are the
      // same number on purpose — the docs pin them together.
      expect(NearMissRules.minPassSpeed, ImpactFx.speedLinesStartSpeed);
    });
  });

  group('close calls ride the fare chain', () {
    PassengerData fareOf(String id) => PassengerData(
          id: id,
          pickupLocation: Vector2(85, 400),
          dropoffLocation: Vector2(85, -300),
          reward: 50,
        );

    test('a close call pays the base at 1x into the chain score', () {
      final chain = FareChain();

      final points = chain.awardNearMiss();

      expect(points, FareChain.nearMissScore);
      expect(chain.score, FareChain.nearMissScore,
          reason: 'close-call points are chain points, not a second score');
      expect(chain.multiplier, 1, reason: 'shaving traffic does not build '
          'the chain — deliveries and pushes do');
      expect(chain.nearMisses, 1);
    });

    test('the live multiplier prices the close call', () {
      final chain = FareChain();
      final passenger = fareOf('a');
      chain.startFare(passenger);
      chain.completeFare(passenger, fareValue: 50);
      expect(chain.multiplier, 2);

      expect(chain.awardNearMiss(), 2 * FareChain.nearMissScore);
      expect(chain.score, 50 + 2 * FareChain.nearMissScore,
          reason: 'the fare and the shave stack in the same score');
      expect(chain.multiplier, 2,
          reason: 'the award leaves the multiplier exactly as it was');
    });

    test('a close call on a broken chain pays 1x', () {
      final chain = FareChain();
      final passenger = fareOf('a');
      chain.startFare(passenger);
      chain.completeFare(passenger, fareValue: 50);
      expect(chain.multiplier, 2);

      chain.breakChain();
      expect(chain.awardNearMiss(), FareChain.nearMissScore,
          reason: 'the chain the crash broke is the price the shave pays');
      expect(chain.nearMisses, 1,
          reason: 'the count records the skill either way');
    });

    test('close calls accumulate with everything else in the score', () {
      final chain = FareChain();
      for (var i = 0; i < 3; i++) {
        chain.awardNearMiss();
      }
      expect(chain.nearMisses, 3);
      expect(chain.score, 3 * FareChain.nearMissScore);
    });

    test('reset clears the count with the run', () {
      final chain = FareChain();
      chain.awardNearMiss();
      chain.awardNearMiss();

      chain.reset();

      expect(chain.nearMisses, 0);
      expect(chain.score, 0);
    });
  });

  group('pass detection on a live run', () {
    late GameStateService gameState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      gameState = GameStateService(storage);
      await gameState.loadSaveData();
    });

    /// Mounts [game] headlessly so component `onLoad` hooks and collision
    /// callbacks run (the pattern the endless-run tests use).
    Future<TaxiGame> mountGame(TaxiGame game) async {
      game.onGameResize(Vector2(400, 800));
      await game.onLoad();
      // ignore: invalid_use_of_internal_member
      game.mount();
      await game.ready();
      return game;
    }

    /// A headless game has no overlay builder map — register stand-ins as
    /// [GameScreen] does in production.
    TaxiGame endlessGame(int seed) => TaxiGame(
          levelLoader: LevelLoaderService(),
          gameState: gameState,
          endlessSeed: seed,
        )
          ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
          ..overlays.addEntry(
              'shiftWrecked', (_, __) => const SizedBox.shrink())
          ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
          ..overlays.addEntry(
              'shiftBanked', (_, __) => const SizedBox.shrink());

    /// Puts the vehicle sprites in the game's image cache so traffic
    /// `onLoad`s complete after a single microtask hop (the endless-run
    /// tests' determinism trick).
    Future<void> preloadSprites(TaxiGame game) async {
      await game.images
          .load(VehicleSprites.playerSpritePath(gameState.selectedVehicle));
      for (final type in TrafficVehicleType.values) {
        await game.images.load(VehicleSprites.trafficSpritePath(type));
      }
    }

    Future<void> drain() async {
      for (var i = 0; i < 8; i++) {
        await Future<void>.value();
        await Future<void>.delayed(Duration.zero);
      }
    }

    /// A sedan parked in the player's path: zero speed, straight path, so
    /// the tests control the pass geometry exactly.
    TrafficVehicle parkedSedan(Vector2 position) => TrafficVehicle(
          position: position.clone(),
          vehicleType: TrafficVehicleType.sedan,
          baseSpeed: 0,
          path: [position.clone(), Vector2(position.x, position.y + 3000)],
        );

    /// Puts the taxi at [x], 0 and holds it at full throttle.
    Future<void> driveUp(TaxiGame game, {double x = 200}) async {
      game.player.position = Vector2(x, 0);
      game.player.isAccelerating = true;
      game.player.velocity = Vector2(0, -game.player.maxSpeed);
      game.update(1 / 60);
      await drain();
      game.update(1 / 60); // applies the queue the first tick built
      await drain();
    }

    /// One more tick after a driving loop: components added mid-update
    /// (the feedback FX) mount at the next tick start.
    Future<void> settle(TaxiGame game) async {
      game.update(1 / 60);
      await drain();
    }

    test('a tight pass at speed awards once and pops the feedback',
        () async {
      final game = await mountGame(endlessGame(42));
      await preloadSprites(game);
      await driveUp(game);

      // A sedan in the oncoming lane, 40 px ahead: the pass crosses with
      // 10 px of daylight (100 px between centres, two 40-px bodies).
      game.world.add(parkedSedan(Vector2(150, -40)));
      await drain();

      var frames = 0;
      while (game.player.position.y > -45 && frames < 120) {
        game.update(1 / 60);
        frames++;
      }
      await settle(game);

      expect(game.player.position.y, lessThanOrEqualTo(-40),
          reason: 'the pass completed');
      expect(game.fareChain.nearMisses, 1);
      expect(game.fareChain.score, FareChain.nearMissScore,
          reason: 'the points are chain points at the live 1x');

      // Driving on never re-arms the same vehicle.
      for (var i = 0; i < 10; i++) {
        game.update(1 / 60);
      }
      expect(game.fareChain.nearMisses, 1);

      // The feedback landed where the pass happened.
      expect(
        game.world.children.whereType<CloseCallPop>(),
        hasLength(1),
      );
      expect(
        game.world.children.whereType<BurstParticles>(),
        hasLength(1),
        reason: 'the slipstream burst rides with the pop',
      );
    });

    test('threading a needle pays once per vehicle', () async {
      final game = await mountGame(endlessGame(42));
      await preloadSprites(game);
      await driveUp(game);

      // Sedans parked in both lanes, one pass through the middle: 10 px
      // of daylight on each side.
      game.world.add(parkedSedan(Vector2(150, -40)));
      game.world.add(parkedSedan(Vector2(250, -40)));
      await drain();

      var frames = 0;
      while (game.player.position.y > -45 && frames < 120) {
        game.update(1 / 60);
        frames++;
      }
      await settle(game);

      expect(game.fareChain.nearMisses, 2,
          reason: 'the flagship moment outranks a single shave by paying '
              'both vehicles, no special case required');
      expect(game.fareChain.score, 2 * FareChain.nearMissScore);
      expect(
        game.world.children.whereType<CloseCallPop>(),
        hasLength(2),
      );
    });

    test('lane-keeping daylight scores nothing', () async {
      final game = await mountGame(endlessGame(42));
      await preloadSprites(game);
      await driveUp(game, x: 250);

      // The sedan sits in the oncoming lane; the player holds the other
      // lane: 60 px of daylight at the pass.
      game.world.add(parkedSedan(Vector2(150, -40)));
      await drain();

      var frames = 0;
      while (game.player.position.y > -45 && frames < 120) {
        game.update(1 / 60);
        frames++;
      }
      await settle(game);

      expect(game.player.position.y, lessThanOrEqualTo(-40),
          reason: 'the pass completed');
      expect(game.fareChain.nearMisses, 0);
      expect(game.fareChain.score, 0);
      expect(game.world.children.whereType<CloseCallPop>(), isEmpty);
    });

    test('a pass made below the speed floor scores nothing', () async {
      final game = await mountGame(endlessGame(42));
      await preloadSprites(game);

      // Roll from a standing start (throttle held, no initial speed).
      // The starter cab ramps at 400 px/s^2, so it is still under the
      // speed floor when it crosses a sedan parked 8 px ahead — and the
      // pass is judged at that crossing, never retroactively once the
      // taxi is up to speed.
      game.player.isAccelerating = true;
      game.world.add(parkedSedan(Vector2(150, -8)));
      await drain();

      var frames = 0;
      while (game.player.position.y > -13 && frames < 120) {
        game.update(1 / 60);
        frames++;
      }
      await settle(game);

      expect(game.player.position.y, lessThanOrEqualTo(-8),
          reason: 'the pass completed');
      expect(-game.player.velocity.y, greaterThan(95),
          reason: 'the taxi is at speed now — the miss was the slow pass, '
              'not the speed');
      expect(game.fareChain.nearMisses, 0);
    });

    test('a vehicle the taxi touched is disqualified at the pass',
        () async {
      final game = await mountGame(endlessGame(42));
      await preloadSprites(game);

      // A sedan parked dead ahead, box to box: first contact is a scrape
      // (a standing start closes far under the crash threshold). The
      // touched vehicle is out of the running for a close call, however
      // the eventual pass looks.
      game.player.isAccelerating = true;
      game.world.add(parkedSedan(Vector2(200, -3)));
      await drain();

      var frames = 0;
      while (game.player.position.y > -60 && frames < 300) {
        game.update(1 / 60);
        frames++;
      }
      await settle(game);

      expect(game.fareChain.nearMisses, 0);
      expect(game.lives.remaining, LivesTracker.maxLives,
          reason: 'the contact was a scrape — the disqualification is the '
              'near-miss rule working, not a crash ending the run');
    });
  });
}
