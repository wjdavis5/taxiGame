import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/dropoff_zone.dart';
import 'package:taxi_game/game/components/passenger_note.dart';
import 'package:taxi_game/game/components/pickup_zone.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/endless_fare_controller.dart';
import 'package:taxi_game/game/systems/fare_chain.dart';
import 'package:taxi_game/game/systems/road_chunk_manager.dart';
import 'package:taxi_game/game/vehicle_sprites.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/widgets/hud_overlay.dart';

/// The endless procedural run (issue #11): recycled road chunks, fares
/// generated continuously, traffic on the distance curve, and — above all
/// — the same seed producing the same run twice.
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

  /// Mounts [game] headlessly so component `onLoad` hooks run, then
  /// returns it. [Game.mount] is what GameWidget calls after load in
  /// production; without it the world never becomes mounted and Flame
  /// takes its direct-add path, which makes adding components during
  /// `update` mutate the tree mid-iteration. With it, mid-update adds are
  /// queued and applied at the next tick start — the same behaviour the
  /// shipped game has.
  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // Internal on purpose: this is exactly the call GameWidget makes once
    // the game has loaded (game_widget.dart). Without it the world never
    // mounts and mid-update adds take Flame's direct-add path.
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  /// Headless games have no overlay builder map; a crash adds
  /// 'levelFailed' in level mode or 'shiftWrecked' at the third endless
  /// crash (issue #14), and the bank-or-push flow (issue #13) adds
  /// 'bankOrPush' at a delivery and 'shiftBanked' at a bank, so register
  /// stand-ins as [GameScreen] does in production.
  TaxiGame endlessGame(int seed) => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: seed,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());

  /// Puts every vehicle sprite in the game's image cache so traffic
  /// `onLoad`s complete after a single microtask hop — that keeps
  /// simulated runs deterministic without real-IO timing leaking in.
  Future<void> preloadSprites(TaxiGame game) async {
    await game.images
        .load(VehicleSprites.playerSpritePath(gameState.selectedVehicle));
    for (final type in TrafficVehicleType.values) {
      await game.images.load(VehicleSprites.trafficSpritePath(type));
    }
  }

  /// Lets pending component mounts finish before the next simulated tick.
  Future<void> drain() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.value();
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// One simulated tick plus the drains for everything it queued to
  /// mount, then a second tick so the queue is applied. After this, every
  /// component the systems added is live in the world.
  Future<void> tickAndSettle(TaxiGame game) async {
    game.update(1 / 60);
    await drain();
    game.update(1 / 60);
    await drain();
  }

  group('an endless run', () {
    test('mounts with road chunks, the taxi, and its first fare', () async {
      final game = await mountGame(endlessGame(42));

      // Tick so the chunk manager and fare controller do their first pass,
      // and settle so everything they queued is live in the world.
      await tickAndSettle(game);

      expect(game.isEndless, isTrue);
      expect(game.isGameActive, isTrue);
      expect(game.player.position, Vector2(200, 0));

      // Road exists under and well ahead of the camera.
      expect(game.roadChunks!.hasChunk(0), isTrue);
      expect(game.roadChunks!.hasChunk(1), isTrue);
      expect(game.roadChunks!.hasChunk(-1), isTrue,
          reason: 'road behind the start line too');

      // The first fare is generated immediately; later slots wait.
      expect(game.fareController!.faresGenerated, 1);
      expect(game.fareController!.nextFareIndex, 1);
      final zones = game.world.children.whereType<PickupZone>().toList();
      expect(zones, hasLength(1));
    });

    test('recycles road chunks: coverage follows the camera, count does not '
        'grow', () async {
      final game = await mountGame(endlessGame(42));

      final manager = game.roadChunks!;

      // Drive 40,000 px in steps, as the camera would scroll.
      for (var i = 0; i < 200; i++) {
        game.player.position += Vector2(0, -200);
        game.update(1 / 60);
      }

      // Still a handful of chunks, now far up the road...
      expect(manager.chunkCount, lessThanOrEqualTo(10));
      expect(manager.chunkIndices.reduce(math.max), greaterThan(40));
      // ...nothing left behind at the start...
      expect(manager.chunkIndices.reduce(math.min), greaterThanOrEqualTo(-2));
      // ...and coverage still brackets the camera.
      final cameraY = game.camera.viewfinder.position.y;
      final topNeeded =
          RoadChunkManager.chunkIndexForY(cameraY - 400 - manager.aheadMargin);
      final bottomNeeded = RoadChunkManager.chunkIndexForY(
          cameraY + 400 + manager.behindMargin);
      for (var i = bottomNeeded; i <= topNeeded; i++) {
        expect(manager.hasChunk(i), isTrue, reason: 'chunk $i in range');
      }
    });

    test('delivers fares: pickup, dropoff, payout, and the next fare',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final coinsBefore = gameState.totalCoins;

      final fare = game.course!.fare(0);

      // Pull up to the kerb.
      game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
      game.update(1 / 60);
      expect(game.player.hasPassenger, isTrue, reason: 'passenger boarded');
      expect(game.fareController!.faresDelivered, 0);

      // Drive the ride.
      game.player.position = Vector2(fare.dropoff.x, fare.dropoff.y + 30);
      game.update(1 / 60);

      expect(game.fareController!.faresDelivered, 1);
      expect(game.player.hasPassenger, isFalse,
          reason: 'passenger delivered');
      expect(gameState.totalCoins, coinsBefore + fare.reward,
          reason: 'the fare pays out on delivery');

      // And the course keeps going: driving on brings the next fare in.
      game.player.position += Vector2(0, -900);
      await tickAndSettle(game);
      expect(game.fareController!.nextFareIndex, greaterThanOrEqualTo(2));
      expect(
        game.world.children.whereType<PickupZone>().length,
        greaterThanOrEqualTo(1),
        reason: 'a new passenger is waiting',
      );
    });

    test('culls fares the player drives past without collecting', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // Stay off the kerb (road centre) and drive far past the first
      // fare — far enough to skip fare 1's slot too.
      final missedPickupY = game.course!.fare(0).pickup.y;
      game.player.position = Vector2(200, missedPickupY + 30);
      game.update(1 / 60);
      game.player.position = Vector2(200, missedPickupY - 4000);
      await tickAndSettle(game);
      // One more tick so queued removals leave the world.
      game.update(1 / 60);
      await drain();

      expect(game.fareController!.faresMissed, 2,
          reason: 'both passed fares are gone');
      // The passed fares' zones are gone; later fares stream in behind
      // the skip.
      final passedIds = {'endless_0', 'endless_1'};
      expect(
        game.world.children
            .whereType<PickupZone>()
            .map((z) => z.passenger.id)
            .toSet()
            .intersection(passedIds),
        isEmpty,
      );
      expect(
        game.world.children
            .whereType<DropoffZone>()
            .map((z) => z.passenger.id)
            .toSet()
            .intersection(passedIds),
        isEmpty,
      );
      expect(
        game.world.children.whereType<PickupZone>(),
        isNotEmpty,
        reason: 'the course keeps producing fares',
      );
    });
  });

  group('a passed dropoff (issue #28)', () {
    DropoffZone dropoffZoneOf(TaxiGame game, EndlessFare fare) =>
        game.world.children.whereType<DropoffZone>().firstWhere(
              (z) => z.passenger.id == 'endless_${fare.index}',
            );

    test('passing a carried dropoff relocates it ahead, and the fare '
        'still settles', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      final fare = game.course!.fare(0);
      final zone = dropoffZoneOf(game, fare);
      expect(zone.position.y, closeTo(fare.dropoff.y, 1e-3));

      // Board the passenger at the kerb.
      game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
      game.update(1 / 60);
      expect(game.player.hasPassenger, isTrue);

      // Blow straight past the dropoff down the road's middle. The street
      // is one-way (velocity.y never goes positive), so before issue #28
      // this stranded the fare — and the passenger — forever.
      game.player.position = Vector2(
          200, fare.dropoff.y - EndlessFareController.passHysteresis - 10);
      await tickAndSettle(game);

      // The dropoff now waits ahead of the taxi, on a fresh curb.
      final relocated = game.course!.relocatedDropoff(fare.index);
      expect(zone.position.x, closeTo(relocated.x, 1e-3));
      expect(zone.position.y, closeTo(relocated.y, 1e-3));
      expect(zone.position.y, lessThan(fare.dropoff.y));
      expect(game.fareController!.faresRelocated, 1);
      expect(game.player.hasPassenger, isTrue,
          reason: 'the passenger is still aboard');
      expect(game.world.children.whereType<PassengerNote>(), isNotEmpty,
          reason: 'the passenger says where to meet them');

      // Reaching the relocated kerb settles the fare: score lands and the
      // chain steps, exactly as an unmissed dropoff would.
      game.player.position = Vector2(relocated.x, relocated.y + 30);
      game.update(1 / 60);
      expect(game.fareController!.faresDelivered, 1);
      expect(game.player.hasPassenger, isFalse);
      expect(game.score, fare.reward, reason: 'on time: value x 1x');
      expect(game.fareChain.multiplier, 2, reason: 'the chain steps');
    });

    test('the meter keeps running through the miss: a late delivery '
        'pays 1x', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      final fare = game.course!.fare(0);
      game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
      game.update(1 / 60);
      game.player.position = Vector2(
          200, fare.dropoff.y - EndlessFareController.passHysteresis - 10);
      game.update(1 / 60);
      await drain();
      expect(game.fareController!.faresRelocated, 1);

      // Sit on the road until the meter dies: relocation bought back the
      // fare, never the clock — the chain already prices the miss in time.
      final ticks = (FareChain.maxFareSeconds + 2).ceil();
      for (var i = 0; i < ticks; i++) {
        game.update(1.0);
      }
      expect(game.fareChain.multiplier, 1, reason: 'the meter broke the chain');

      final relocated = game.course!.relocatedDropoff(fare.index);
      game.player.position = Vector2(relocated.x, relocated.y + 30);
      game.update(1 / 60);

      expect(game.fareController!.faresDelivered, 1);
      expect(game.score, fare.reward, reason: 'late fare pays value x 1');
      expect(game.fareChain.multiplier, 1);
    });

    test('riding up to a dropoff without passing it leaves it in place',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      final fare = game.course!.fare(0);
      game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
      game.update(1 / 60);
      expect(game.player.hasPassenger, isTrue);

      // Approaching down the road's middle, still below the kerb: no
      // relocation — the delivery can still happen the normal way.
      game.player.position = Vector2(200, fare.dropoff.y + 70);
      game.update(1 / 60);
      expect(game.fareController!.faresRelocated, 0);

      // Just barely past, inside the pass hysteresis: still no
      // relocation — the taxi is not clearly beyond the zone's reach yet.
      game.player.position = Vector2(200, fare.dropoff.y - 50);
      game.update(1 / 60);
      expect(game.fareController!.faresRelocated, 0);
      expect(game.fareController!.hasActivePickup, isTrue,
          reason: 'the fare rides on either way');
    });

    test('passing the relocated dropoff relocates it again', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      final fare = game.course!.fare(0);
      game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
      game.update(1 / 60);
      game.player.position = Vector2(
          200, fare.dropoff.y - EndlessFareController.passHysteresis - 10);
      game.update(1 / 60);
      await drain();
      expect(game.fareController!.faresRelocated, 1);

      // Blow past the relocated kerb too: the passenger must still never
      // be stranded, wherever the taxi decides to go.
      final firstRelocated = game.course!.relocatedDropoff(fare.index);
      game.player.position = Vector2(
          200, firstRelocated.y - EndlessFareController.passHysteresis - 10);
      game.update(1 / 60);
      await drain();

      final secondRelocated =
          game.course!.relocatedDropoff(fare.index, attempt: 1);
      final zone = dropoffZoneOf(game, fare);
      expect(zone.position.x, closeTo(secondRelocated.x, 1e-3));
      expect(zone.position.y, closeTo(secondRelocated.y, 1e-3));
      expect(game.fareController!.faresRelocated, 2);

      // And the ride still ends at the newest kerb.
      game.player.position = Vector2(secondRelocated.x, secondRelocated.y + 30);
      game.update(1 / 60);
      expect(game.fareController!.faresDelivered, 1);
      expect(game.player.hasPassenger, isFalse);
    });
  });

  group('fare chain scoring (issue #12)', () {
    /// Delivers the fare with the given index by teleporting the taxi to
    /// its kerbs, the way the delivery test above does. Assumes the fare's
    /// zones are already mounted and live in the world.
    void deliverFare(TaxiGame game, EndlessFare fare) {
      game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
      game.update(1 / 60);
      expect(game.player.hasPassenger, isTrue, reason: 'passenger boarded');
      game.player.position = Vector2(fare.dropoff.x, fare.dropoff.y + 30);
      game.update(1 / 60);
    }

    test('chained deliveries multiply the payout', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final coinsBefore = gameState.totalCoins;

      // First fare pays 1x and arms a 2x chain.
      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      expect(game.fareChain.multiplier, 2);
      expect(game.score, fare0.reward);

      // Let the camera catch up so the next fare generates and mounts,
      // then deliver it: it pays 2x.
      await tickAndSettle(game);
      final fare1 = game.course!.fare(1);
      deliverFare(game, fare1);
      expect(game.fareChain.multiplier, 3);
      expect(game.score, fare0.reward + 2 * fare1.reward,
          reason: 'score accrues as fare value x current multiplier');
      expect(gameState.totalCoins, coinsBefore + fare0.reward + fare1.reward,
          reason: 'coins pay unbunched: the economy is unchanged');
    });

    test('letting the meter run out breaks the chain back to 1x', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // Chain a delivery first so there is something to lose.
      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      expect(game.fareChain.multiplier, 2);
      await tickAndSettle(game);

      // Pick up the next fare and sit on it until the meter dies. The
      // taxi is parked on the kerb, out of every traffic lane.
      final fare1 = game.course!.fare(1);
      game.player.position = Vector2(fare1.pickup.x, fare1.pickup.y + 30);
      game.update(1 / 60);
      expect(game.player.hasPassenger, isTrue);

      final ticks = (FareChain.maxFareSeconds + 2).ceil();
      for (var i = 0; i < ticks; i++) {
        game.update(1.0);
      }
      expect(game.fareChain.multiplier, 1,
          reason: 'expiry resets the multiplier the moment it happens');

      // Delivering late still pays the fare — at 1x, and the chain does
      // not grow.
      game.player.position = Vector2(fare1.dropoff.x, fare1.dropoff.y + 30);
      game.update(1 / 60);
      expect(game.score, fare0.reward + fare1.reward,
          reason: 'late fare pays value x 1');
      expect(game.fareChain.multiplier, 1);
    });
  });

  group('seed reproducibility', () {
    /// Runs [ticks] of scripted driving — throttle held, steering swept by
    /// a sine — capturing a full state fingerprint every [snapshotEvery]
    /// ticks. Traffic will crash this taxi partway; the fingerprint covers
    /// the aftermath too.
    Future<List<List<double>>> runScripted(
      TaxiGame game, {
      required int ticks,
      double dt = 1 / 30,
      int snapshotEvery = 15,
    }) async {
      await preloadSprites(game);
      final snapshots = <List<double>>[];

      game.player.startAccelerating();
      for (var i = 0; i < ticks; i++) {
        game.player.setSteering(math.sin(i * 0.037));
        game.update(dt);
        if (i % 30 == 29) await drain();
        if (i % snapshotEvery == 0) snapshots.add(captureState(game));
      }
      return snapshots;
    }

    test('the same seed produces the identical course twice', () async {
      const seed = 2026;
      final gameA = await mountGame(endlessGame(seed));
      final gameB = await mountGame(endlessGame(seed));

      final runA = await runScripted(gameA, ticks: 900); // 30 simulated s
      final runB = await runScripted(gameB, ticks: 900);

      expect(runA, hasLength(runB.length));
      for (var i = 0; i < runA.length; i++) {
        expect(runA[i], hasLength(runB[i].length),
            reason: 'snapshot $i field count');
        for (var j = 0; j < runA[i].length; j++) {
          expect(runA[i][j], closeTo(runB[i][j], 1e-9),
              reason: 'snapshot $i field $j');
        }
      }
    });

    test('different seeds produce different courses', () async {
      final gameA = await mountGame(endlessGame(1));
      final gameB = await mountGame(endlessGame(2));

      // Compare the generated fare slots — the road itself is uniform.
      final courseA = gameA.course!;
      final courseB = gameB.course!;
      var differing = 0;
      for (var i = 0; i < 10; i++) {
        final fa = courseA.fare(i);
        final fb = courseB.fare(i);
        if ((fa.pickup - fb.pickup).length > 0.001 ||
            (fa.dropoff - fb.dropoff).length > 0.001) {
          differing++;
        }
      }
      expect(differing, greaterThan(0));
    });

    test('restarting an endless run replays the same seed exactly',
        () async {
      final game = await mountGame(endlessGame(77));
      await preloadSprites(game);

      List<double> courseState() {
        final out = <double>[];
        for (var i = 0; i < 4; i++) {
          final fare = game.course!.fare(i);
          out.addAll([
            fare.pickup.x,
            fare.pickup.y,
            fare.dropoff.x,
            fare.dropoff.y,
            fare.reward.toDouble(),
          ]);
        }
        return out;
      }

      final before = courseState();
      before.addAll(captureState(game));

      // Drive away and deliver nothing; the road moves on.
      for (var i = 0; i < 120; i++) {
        game.player.position += Vector2(0, -150 / 60);
        game.update(1 / 60);
      }

      game.restartLevel();
      await drain();

      final after = courseState();
      after.addAll(captureState(game));

      expect(after, hasLength(before.length));
      for (var i = 0; i < before.length; i++) {
        expect(after[i], closeTo(before[i], 1e-9), reason: 'field $i');
      }
    });
  });

  group('a 30-minute simulated run', () {
    const longRun = Timeout(Duration(minutes: 6));

    test('stays bounded: no memory growth, world stays small', () async {
      final game = await mountGame(endlessGame(31337));
      await preloadSprites(game);

      // The scripted taxi drives blindly up the middle at top cruise speed
      // and must not be stopped by contacts, so its hitbox is silenced —
      // every other system (spawning, chunk recycling, fare generation and
      // culling, telegraphs) runs at full churn.
      final hitbox =
          game.player.children.whereType<RectangleHitbox>().single;
      hitbox.collisionType = CollisionType.inactive;

      const dt = 1 / 15.0; // 15 fps sim: same wall-clock, half the ticks
      const totalSeconds = 30 * 60;
      const cruiseSpeed = 150.0;

      var maxWorldChildren = 0;
      var maxTraffic = 0;
      var maxZones = 0;
      var maxActiveFares = 0;
      var samples = 0;

      for (var s = 0.0; s < totalSeconds; s += dt) {
        game.player.position += Vector2(0, -cruiseSpeed * dt);
        game.update(dt);

        if ((samples % 15) == 0) {
          maxWorldChildren = math.max(
              maxWorldChildren, game.world.children.length);
          maxTraffic = math.max(
              maxTraffic, game.trafficSpawner.activeVehicleCount);
          maxZones = math.max(
              maxZones,
              game.world.children
                  .whereType<PickupZone>()
                  .length);
          maxActiveFares =
              math.max(maxActiveFares, game.fareController!.activeFareCount);
        }
        samples++;

        // Let component mounts complete, as the real loop would between
        // frames.
        if (samples % 30 == 0) await drain();
      }

      // The run actually happened.
      expect(game.runDistance, greaterThanOrEqualTo(totalSeconds * cruiseSpeed * 0.99),
          reason: 'the taxi covered half an hour of road');
      expect(game.roadChunks!.chunkIndices.reduce(math.max), greaterThan(300),
          reason: 'the road rolled hundreds of chunks deep');
      expect(game.fareController!.faresGenerated, greaterThan(150),
          reason: 'fares kept coming the whole way');
      expect(game.fareController!.faresMissed, greaterThan(100),
          reason: 'the blind taxi missed (and culled) most of them');

      // ...and nothing accumulated while it did. Same-direction traffic
      // lives longest (the taxi barely outpaces it), so the traffic cap
      // sits well above its worst-case steady state.
      expect(maxWorldChildren, lessThan(200),
          reason: 'peak world children');
      expect(maxTraffic, lessThan(80), reason: 'peak live traffic');
      expect(maxZones, lessThan(12), reason: 'peak live fare zones');
      expect(maxActiveFares, lessThan(8), reason: 'peak active fares');
      expect(game.world.children.length, lessThan(200),
          reason: 'world size at the end of the run');
    }, timeout: longRun);
  });

  group('endless HUD', () {
    testWidgets('shows the distance driven, live', (tester) async {
      late TaxiGame game;
      await tester.runAsync(() async {
        game = await mountGame(endlessGame(9));
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<GameStateService>.value(
          value: gameState,
          child: MaterialApp(
            home: Scaffold(body: HudOverlay(game: game)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('0 m'), findsOneWidget);

      game.player.position = Vector2(200, -1230); // 123 m
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('123 m'), findsOneWidget);

      game.player.position = Vector2(200, -1000000); // 100 km
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('100.0 km'), findsOneWidget);
    });
  });
}

/// A fingerprint of everything that defines the run's state at one instant:
/// player, every traffic vehicle, every live fare zone, the road chunks in
/// memory, and the counters. Two runs with the same seed must produce
/// identical sequences of these.
List<double> captureState(TaxiGame game) {
  final out = <double>[];

  final player = game.player;
  out.addAll([
    player.position.x,
    player.position.y,
    player.velocity.x,
    player.velocity.y,
    player.hasPassenger ? 1 : 0,
    game.isGameActive ? 1 : 0,
  ]);

  final traffic = game.world.children.whereType<TrafficVehicle>().toList()
    ..sort((a, b) {
      final byY = a.position.y.compareTo(b.position.y);
      return byY != 0 ? byY : a.position.x.compareTo(b.position.x);
    });
  out.add(traffic.length.toDouble());
  for (final v in traffic) {
    out.addAll([
      v.vehicleType.index.toDouble(),
      v.position.x,
      v.position.y,
      v.velocity.x,
      v.velocity.y,
    ]);
  }
  out.add(game.trafficSpawner.activeVehicleCount.toDouble());

  final zones = <Vector2>[
    ...game.world.children.whereType<PickupZone>().map((z) => z.position),
    ...game.world.children.whereType<DropoffZone>().map((z) => z.position),
  ]..sort((a, b) {
      final byY = a.y.compareTo(b.y);
      return byY != 0 ? byY : a.x.compareTo(b.x);
    });
  out.add(zones.length.toDouble());
  for (final z in zones) {
    out.addAll([z.x, z.y]);
  }

  final chunks = game.roadChunks!.chunkIndices.toList()..sort();
  out.add(chunks.length.toDouble());
  out.addAll(chunks.map((c) => c.toDouble()));

  out.addAll([
    game.fareController!.nextFareIndex.toDouble(),
    game.fareController!.faresDelivered.toDouble(),
    game.fareController!.faresMissed.toDouble(),
  ]);

  return out;
}
