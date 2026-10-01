import 'dart:math' as math;

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/dropoff_zone.dart';
import 'package:taxi_game/game/components/passenger_note.dart';
import 'package:taxi_game/game/components/pickup_zone.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/components/ghost_car.dart';
import 'package:taxi_game/game/components/road_segment.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/endless_fare_controller.dart';
import 'package:taxi_game/game/systems/fare_chain.dart';
import 'package:taxi_game/game/systems/road_chunk_manager.dart';
import 'package:taxi_game/game/systems/world_origin.dart';
import 'package:taxi_game/game/vehicle_sprites.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/models/fare_type.dart';
import 'package:taxi_game/models/ghost_trace.dart';
import 'package:taxi_game/models/passenger_data.dart';
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

  group('the pulsing zone markers (issue #143)', () {
    /// The pulse sweeps one full period every π s (2 rad/s), so 4 s of
    /// frames carries the sine through both extremes — drawn radii 25
    /// and 35. At either extreme the old code rewrote the component's
    /// `size`, sliding the top-left origin under every fixed-offset
    /// child by 5 px per axis while the drawn circle stayed dead on the
    /// kerb, so 4 s is enough to catch the wobble at its worst.
    Future<void> sweepPulse(TaxiGame game, void Function() assertHeld) async {
      for (var frame = 0; frame < 240; frame++) {
        game.update(1 / 60);
        assertHeld();
      }
    }

    test('the pickup detection circle stays centred on its marker', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // Geometry, not survival: the cab stands on the start line, out of
      // every lane, while the marker ahead breathes.
      game.player.children.whereType<RectangleHitbox>().single.collisionType =
          CollisionType.inactive;
      expect(game.player.hasPassenger, isFalse,
          reason: 'precondition: fare 0 still waits at its kerb');

      final zone = game.world.children.whereType<PickupZone>().single;
      final hitbox = zone.children.whereType<CircleHitbox>().single;

      // The hitbox hangs from the component's local origin at
      // (baseRadius, baseRadius); the marker is drawn at size/2. Those
      // are the same point only while the component never resizes — the
      // whole of issue #143's fix.
      await sweepPulse(game, () {
        expect(
          hitbox.absoluteCenter.distanceTo(zone.absoluteCenter),
          lessThan(0.001),
          reason: 'the detection circle slid off the marker the player '
              'aims at',
        );
        expect(zone.size, Vector2.all(30.0 * 2),
            reason: 'the component stays baseRadius square for life');
      });
    });

    test('the dropoff detection circle stays centred once its flag pulses',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // Board fare 0 so its dropoff activates — the flag only pulses
      // with a passenger aboard.
      final fare = game.course!.fare(0);
      game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
      game.update(1 / 60);
      expect(game.player.hasPassenger, isTrue, reason: 'passenger boarded');

      // Geometry, not survival: park at the boarding kerb, off the road.
      game.player.children.whereType<RectangleHitbox>().single.collisionType =
          CollisionType.inactive;

      final zone = game.world.children
          .whereType<DropoffZone>()
          .firstWhere((z) => z.passenger.id == 'endless_0');
      final hitbox = zone.children.whereType<CircleHitbox>().single;

      await sweepPulse(game, () {
        expect(
          hitbox.absoluteCenter.distanceTo(zone.absoluteCenter),
          lessThan(0.001),
          reason: 'the detection circle slid off the flag the player '
              'aims at',
        );
        expect(zone.size, Vector2.all(30.0 * 2),
            reason: 'the component stays baseRadius square for life');
      });
    });

    test('a special fare\'s label holds its offset while the marker pulses',
        () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // Geometry, not survival.
      game.player.children.whereType<RectangleHitbox>().single.collisionType =
          CollisionType.inactive;

      // The label is the issue's other victim and only a special fare
      // wears one, so mount a VIP outright rather than trusting the
      // seed to have dealt one: it waits on a quiet stretch of road the
      // controller does not know about, so nothing culls or boards it.
      final passenger = PassengerData(
        id: 'issue_143_vip',
        pickupLocation: Vector2(200, -1000),
        dropoffLocation: Vector2(200, -3000),
        reward: 42,
        fareType: FareType.vip,
      );
      final zone = PickupZone(
        position: Vector2(200, -1000),
        passenger: passenger,
        onPickup: () {},
      );
      game.world.add(zone);
      await tickAndSettle(game);

      final label = zone.children.whereType<TextComponent>().single;
      expect(zone.children.whereType<CircleHitbox>(), isNotEmpty,
          reason: 'precondition: the mounted zone built its hitbox');
      final restOffset = label.absoluteCenter - zone.absoluteCenter;

      // The label hangs at a fixed local offset under the marker, so its
      // offset from the (never-moving) marker centre must read the same
      // at every phase of the pulse. Before the fix it wobbled ±5 px in
      // both axes with the sine.
      await sweepPulse(game, () {
        expect(
          (label.absoluteCenter - zone.absoluteCenter).distanceTo(restOffset),
          lessThan(0.001),
          reason: 'the label wobbled with the pulse',
        );
      });
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
      final note = game.world.children.whereType<PassengerNote>().single;

      // And the sentence can actually be read (issue #50): the note is
      // born at the kerb the dropoff waited on, clamped so the whole
      // line stays on the phone. The branch follows the measured font:
      // a sentence that fits keeps its edges inside the margins, and the
      // test font's over-wide one (429 px against the 400 px viewport)
      // collapses onto the road's centre — clipped evenly, never lost
      // off one side.
      const roadWidth = 2 * TaxiGame.roadCenterX;
      if (note.width >= roadWidth - 2 * PassengerNote.edgeMargin) {
        expect(note.width, greaterThan(roadWidth),
            reason: 'the over-wide premise the branch asserts holds');
        expect(note.x, closeTo(TaxiGame.roadCenterX, 0.5),
            reason: 'an over-wide sentence centres on the road');
      } else {
        expect(note.x - note.width / 2,
            greaterThanOrEqualTo(PassengerNote.edgeMargin - 0.5),
            reason: 'the sentence\'s start is on screen');
        expect(note.x + note.width / 2,
            lessThanOrEqualTo(roadWidth - PassengerNote.edgeMargin + 0.5),
            reason: 'the sentence\'s end is on screen');
      }

      // Reaching the relocated kerb settles the fare: score lands and the
      // chain steps, exactly as an unmissed dropoff would.
      game.player.position = Vector2(relocated.x, relocated.y + 30);
      game.update(1 / 60);
      expect(game.fareController!.faresDelivered, 1);
      expect(game.player.hasPassenger, isFalse);
      expect(game.score, fare.reward, reason: 'on time: value x 1x');
      expect(game.fareChain.multiplier, 2, reason: 'the chain steps');
    });

    test('the note stays on the phone at both kerbs (issue #50)', () {
      // The clamp is the component's own, so its unit is testable
      // without driving a relocation: construct one at each kerb the
      // course deals dropoffs to — and dead centre, which must not move.
      const roadWidth = 2 * TaxiGame.roadCenterX;
      for (final kerbX in [60.0, TaxiGame.roadCenterX, 340.0]) {
        final note = PassengerNote(position: Vector2(kerbX, -1000));
        if (note.width >= roadWidth - 2 * PassengerNote.edgeMargin) {
          expect(note.width, greaterThan(roadWidth),
              reason: 'over-wide premise holds at kerb $kerbX');
          expect(note.x, closeTo(TaxiGame.roadCenterX, 0.5),
              reason: 'kerb $kerbX: over-wide collapses to the centre '
                  '(a naive clamp(lo, hi) would have thrown here)');
        } else {
          expect(note.x - note.width / 2,
              greaterThanOrEqualTo(PassengerNote.edgeMargin - 0.5),
              reason: 'kerb $kerbX: sentence start on screen');
          expect(note.x + note.width / 2,
              lessThanOrEqualTo(roadWidth - PassengerNote.edgeMargin + 0.5),
              reason: 'kerb $kerbX: sentence end on screen');
        }
      }
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
      advanceGameTime(game, FareChain.maxFareSeconds + 2);
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

      advanceGameTime(game, FareChain.maxFareSeconds + 2);
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

  group('traffic outlives its path while in view (issue #129)', () {
    /// A same-direction sedan driving up-screen at exactly [speed] px/s
    /// (its type multiplier is 1.0), its path ending [pathLength] px
    /// above [position] — the geometry of the issue: the path's end is
    /// road distance from the spawn, wherever that leaves it relative
    /// to the camera.
    TrafficVehicle carWithPath(
      Vector2 position,
      double speed,
      double pathLength,
    ) =>
        TrafficVehicle(
          position: position.clone(),
          vehicleType: TrafficVehicleType.sedan,
          baseSpeed: speed,
          path: [
            position.clone(),
            Vector2(position.x, position.y - pathLength),
          ],
        );

    /// Mounts a quiet endless run and settles it: the taxi stands on
    /// the start line (so the camera does too — the endless camera has
    /// no lead), its hitbox silenced so nothing collides with the test
    /// cars, and the world's systems all mounted.
    Future<TaxiGame> quietStreet(int seed) async {
      final game = await mountGame(endlessGame(seed));
      game.player.children.whereType<RectangleHitbox>().single.collisionType =
          CollisionType.inactive;
      await tickAndSettle(game);
      return game;
    }

    test('a car that runs out of path on screen keeps driving', () async {
      final game = await quietStreet(42);
      final cameraY = game.camera.viewfinder.position.y;

      // In view, path ending 100 px up — it runs out well inside the
      // ±400 px view band. Before the fix the car was deleted at that
      // end, in plain sight beside the cab.
      final car = carWithPath(Vector2(200, cameraY - 300), 120, 100);
      game.world.add(car);
      await game.ready();

      advanceGameTime(game, 2.0); // 240 px of driving, path ends at 100

      expect(car.shouldRemove, isFalse, reason: 'the path ending is not '
          'the car ending while it can still be seen');
      expect(car.isMounted, isTrue, reason: 'the car is still on the road');
      expect(car.position.y, lessThan(cameraY - 400),
          reason: 'the car drove on past its original path end');
      expect(car.currentWaypointIndex, lessThan(car.path.length),
          reason: 'a live car still has road to drive');

      // And it keeps moving, not parked at the old path's end.
      final sampledAt = car.position.clone();
      advanceGameTime(game, 0.5);
      expect(car.position.distanceTo(sampledAt), greaterThan(5.0),
          reason: 'the car drives on instead of idling at the path end');
    });

    test('the rebuilt schedule is anchored where the car stands', () async {
      final game = await quietStreet(42);
      final cameraY = game.camera.viewfinder.position.y;

      final car = carWithPath(Vector2(200, cameraY - 300), 120, 100);
      game.world.add(car);
      await game.ready();

      // Tick until the spawn path's last waypoint is replaced by the
      // rebuilt merge schedule — the moment the extension fires. The
      // detector is identity, not length: a rebuilt schedule may also
      // have two anchors when no taper sits inside its span. The y it
      // records is the car's position *before* that update — where the
      // car stood when the rebuild anchored — because the extension
      // frame now drives on like any other (issue #135) instead of
      // freezing the car at its old path's end.
      final originalEnd = car.path.last;
      var extendedAtY = double.nan;
      for (var i = 0; i < 240 && extendedAtY.isNaN; i++) {
        final yBefore = car.position.y;
        game.update(1 / 60);
        if (!identical(car.path.last, originalEnd)) {
          extendedAtY = yBefore;
        }
      }
      expect(extendedAtY.isNaN, isFalse,
          reason: 'the path ran out and was rebuilt');
      // First anchor at the car's own distance, on its lane centre —
      // the re-centring snaps the waypoint-reach drift a merge leaves
      // (≤ ~1.5 px) back onto the lane so the rebuilt polyline holds
      // the lane invariant from its first metre. The test car never
      // merges, so its x never drifted: the anchor is exact. The car
      // itself has since driven on past the anchor (one frame at
      // 120 px/s by the time the detector reads it).
      expect(car.path.first.y, closeTo(extendedAtY, 0.001));
      expect((car.path.first.x - car.position.x).abs(), lessThan(4.001));
      // And the fresh schedule drives the same 3,000 px extent from
      // there (mapped through the same world fold the spawn used:
      // last waypoint y = y − 3000).
      expect(car.path.last.y, closeTo(extendedAtY - 3000, 0.5));
      // The list is replaced, not appended: one bounded schedule.
      expect(car.path.length, lessThan(12));
    });

    test('the extension frame drives like every other frame (issue #135)',
        () async {
      final game = await quietStreet(42);
      final cameraY = game.camera.viewfinder.position.y;

      // Same car as the anchor test: on the lane centre, path ending
      // 100 px up. It sits at true distance ~400, so the rebuilt
      // schedule's span [400, 3400] lies wholly inside the opening
      // segment (4,000 px, no taper) — its first real leg is exactly
      // vertical, which is what lets the velocity assertions below be
      // exact rather than directional.
      final car = carWithPath(Vector2(200, cameraY - 300), 120, 100);
      game.world.add(car);
      await game.ready();

      // The anchor test's extension detector — identity of the last
      // waypoint — with a per-frame watch on either side of it: every
      // frame must read as a moving, up-screen car. The extension frame
      // used to break both halves at once: aiming at the on-car anchor
      // left velocity at zero (stopped) or pure sideways within the
      // 4 px re-centre drift, and the branch returned before the
      // position step — so for that one frame the car neither read nor
      // moved as driving, and a touch on it was ruled on a velocity the
      // car does not have (a scrape's closing crossing the crash
      // threshold).
      final originalEnd = car.path.last;
      var extended = false;
      for (var i = 0; i < 240; i++) {
        final yBefore = car.position.y;
        game.update(1 / 60);
        if (!extended && !identical(car.path.last, originalEnd)) {
          extended = true;
          // The extension frame itself: the on-car anchor is skipped
          // and the first real leg driven — straight up this road, at
          // exactly the car's speed.
          expect(car.currentWaypointIndex, 1,
              reason: 'the rebuild aims past the anchor that sits on '
                  'the car');
          expect(car.velocity.x, closeTo(0, 0.001),
              reason: 'no sideways lurch on the re-centre');
          expect(car.velocity.y, closeTo(-120, 0.001),
              reason: 'the extension frame drives at full speed');
        }
        expect(car.velocity.y, lessThan(0),
            reason: 'frame $i: a same-direction car in motion reads as '
                'moving up-screen, never stopped or crabbing sideways');
        expect(car.position.y, lessThan(yBefore),
            reason: 'frame $i: y strictly decreases — no frozen frame '
                'while the schedule is rebuilt');
      }
      expect(extended, isTrue,
          reason: 'the path ran out and was rebuilt inside the window');
    });

    test('a car that pulls a screen and a half ahead is culled', () async {
      final game = await quietStreet(42);
      final cameraY = game.camera.viewfinder.position.y;

      // Well outside the ±400 px view, 500 px past the ahead cull's
      // line, with plenty of path left — only the cull can remove it.
      final car = carWithPath(Vector2(200, cameraY - 1500), 120, 3000);
      game.world.add(car);
      await game.ready();

      game.update(1 / 60);

      expect(car.shouldRemove, isTrue,
          reason: 'out of view ahead, the car goes (#18 kept: nothing '
              'lingers past the view band)');
      // Flame applies removals through its queue: settle and the car is
      // gone from the world.
      await tickAndSettle(game);
      expect(game.world.children.whereType<TrafficVehicle>(),
          isNot(contains(car)));
    });

    test('a car behind the camera still goes', () async {
      final game = await quietStreet(42);
      final cameraY = game.camera.viewfinder.position.y;

      // The pre-existing rule, unchanged: a car the taxi has long since
      // passed is culled a screen below the view.
      final car = carWithPath(Vector2(200, cameraY + 1500), 120, 3000);
      game.world.add(car);
      await game.ready();

      game.update(1 / 60);

      expect(car.shouldRemove, isTrue);
      await tickAndSettle(game);
      expect(game.world.children.whereType<TrafficVehicle>(),
          isNot(contains(car)));
    });

    test('a level car still despawns at its path\'s end', () async {
      // Level mode has no living road (game.environment is null), so
      // neither the extension nor the ahead cull applies: its paths are
      // clamped to the street's end (#31) and arrival is the despawn.
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));
      await tickAndSettle(game);
      final cameraY = game.camera.viewfinder.position.y;

      final car = carWithPath(Vector2(200, cameraY - 300), 120, 100);
      game.world.add(car);
      await game.ready();

      advanceGameTime(game, 1.2); // the 100 px path ends at ~0.83 s

      expect(car.shouldRemove, isTrue,
          reason: 'the level street ends (#31); its cars arrive, they '
              'do not overflow');
      await tickAndSettle(game);
      expect(game.world.children.whereType<TrafficVehicle>(),
          isNot(contains(car)));
    });
  });

  /// Asserts the live chunks cover the camera's visible band with no gap:
  /// every stretch of road the viewport shows falls inside some existing
  /// chunk, and the chunk indices are contiguous across the band (a hole
  /// anywhere between them is a stripe of bare sky mid-road).
  void expectViewportCovered(TaxiGame game) {
    final manager = game.roadChunks!;
    final centerY = game.camera.viewfinder.position.y;
    final halfView = game.camera.viewport.size.y / 2;
    // The viewport's band of true distance (issue #30): world y folds,
    // the distance it stands for does not.
    final topDistance = game.worldShift - (centerY - halfView);
    final bottomDistance = game.worldShift - (centerY + halfView);
    final topIndex = RoadChunkManager.chunkIndexForDistance(topDistance);
    final bottomIndex =
        RoadChunkManager.chunkIndexForDistance(bottomDistance);
    for (var i = bottomIndex; i <= topIndex; i++) {
      expect(manager.hasChunk(i), isTrue,
          reason: 'chunk $i missing at camera y $centerY — '
              'the viewport would show bare sky');
    }
    // Chunk [i] holds distances [i·L, (i+1)·L], so the band is gapless
    // exactly when the topmost chunk reaches above the view top.
    expect(
      (topIndex + 1) * RoadChunkManager.chunkLength,
      greaterThanOrEqualTo(topDistance),
      reason: 'the topmost chunk does not reach the view top',
    );
  }

  group('the road never leaves the viewport (issue #30)', () {
    test('a 30-minute camera path always has road under the view',
        () async {
      final game = await mountGame(endlessGame(20260927));
      await preloadSprites(game);

      // Coverage, not survival: silence the taxi's hitbox so contacts
      // cannot end the run; the stall pauses below are scripted instead.
      game.player.children.whereType<RectangleHitbox>().single.collisionType =
          CollisionType.inactive;

      const dt = 0.1; // 10 fps sim: same wall clock, a tenth of the ticks
      const cruiseSpeed = 150.0; // px/s, the top cruise of the starter cab
      const totalSeconds = 30 * 60;

      var frame = 0;
      var stallFramesLeft = 0;
      var secondsUntilNextStall = 240.0;

      for (var s = 0.0; s < totalSeconds; s += dt) {
        if (stallFramesLeft > 0) {
          // A crash stall: the world holds still — the camera goes nowhere
          // — but the loop keeps ticking, exactly like the live game's.
          stallFramesLeft--;
        } else {
          game.player.position += Vector2(0, -cruiseSpeed * dt);
          secondsUntilNextStall -= dt;
          if (secondsUntilNextStall <= 0) {
            stallFramesLeft = (TaxiGame.crashStallSeconds / dt).ceil();
            secondsUntilNextStall = 240.0;
          }
        }
        game.update(dt);
        expectViewportCovered(game);

        // Let component mounts complete, as the real loop does.
        frame++;
        if (frame % 60 == 0) await drain();
      }

      // The run really happened: hundreds of chunks rolled past — and two
      // world folds went by (100,800 px each) without the road noticing.
      expect(game.runDistance, greaterThanOrEqualTo(240000),
          reason: 'the camera travelled half an hour of road');
      expect(game.worldShift, greaterThanOrEqualTo(2 * WorldOrigin.period),
          reason: 'the world folded at least twice on the way');
      expect(game.player.position.y, inInclusiveRange(-WorldOrigin.period, 0),
          reason: 'world coordinates stay folded near the origin');
      expect(game.roadChunks!.chunkIndices.reduce(math.max), greaterThan(290),
          reason: 'chunks were recycled the whole way, not hoarded');
      expect(game.roadChunks!.chunkCount, lessThanOrEqualTo(10),
          reason: 'the steady-state chunk count stays small');
      expectViewportCovered(game);
    }, timeout: const Timeout(Duration(minutes: 8)));
  });

  group('the world fold (issue #30)', () {
    Future<TaxiGame> mountQuietGame(int seed) async {
      final game = await mountGame(endlessGame(seed));
      // Coverage and geometry, not survival.
      game.player.children.whereType<RectangleHitbox>().single.collisionType =
          CollisionType.inactive;
      return game;
    }

    /// Drives the taxi to true distance [target] in one teleport and
    /// settles the fold, mounts, and chunk sync that follow it.
    Future<TaxiGame> driveTo(int seed, double target) async {
      final game = await mountQuietGame(seed);
      game.player.position = Vector2(200, -target);
      await tickAndSettle(game);
      return game;
    }

    test('crossing the boundary folds the world without losing the road',
        () async {
      const target = WorldOrigin.period + 2000.0;
      final game = await driveTo(424242, target);

      // The world folded exactly once, the taxi sits near the origin, and
      // true distance is untouched.
      expect(game.worldShift, WorldOrigin.period);
      expect(game.player.position.y, inInclusiveRange(-WorldOrigin.period, 0));
      expect(game.runDistance, closeTo(target, 1.0));
      expect(game.camera.viewfinder.position.y,
          inInclusiveRange(-WorldOrigin.period, 0),
          reason: 'the camera folded with the world');

      // The road still covers the viewport after the fold.
      expectViewportCovered(game);

      // Fares past the fold generate in the live frame: skip the ~70
      // slots the teleport jumped over, then the next fare spawns near
      // the taxi — at its true distance, not a whole fold away.
      var zones = <PickupZone>[];
      for (var i = 0; i < 40 && zones.isEmpty; i++) {
        await tickAndSettle(game);
        zones = game.world.children.whereType<PickupZone>().toList();
      }
      expect(zones, isNotEmpty,
          reason: 'the course keeps producing fares past a fold');
      final cameraDistance =
          game.worldShift - game.camera.viewfinder.position.y;
      for (final zone in zones) {
        final zoneDistance = game.worldShift - zone.position.y;
        expect(
          zoneDistance,
          inInclusiveRange(
            cameraDistance - EndlessFareController.cullBehind - 10,
            cameraDistance + EndlessFareController.generationAhead + 10,
          ),
          reason: 'a fare past the fold waits in the live frame, '
              'not one period away in a stale one',
        );
        expect(zone.position.y, inInclusiveRange(-WorldOrigin.period, 0),
            reason: 'fares land in the live frame, not a stale one');
      }
    });

    test('multiple folds in one leap all apply', () async {
      final game = await driveTo(5150, 2.5 * WorldOrigin.period);

      expect(game.worldShift, 2 * WorldOrigin.period,
          reason: 'both crossed boundaries folded in one tick');
      expect(game.runDistance, closeTo(2.5 * WorldOrigin.period, 1.0));
      expectViewportCovered(game);
    });

    test('a car spawned on the frame before a fold rides it (issue #98)',
        () async {
      final game = await mountQuietGame(989898);
      await preloadSprites(game);

      // Park just short of the first fold and settle there: the boundary
      // is still ahead and no traffic exists yet.
      game.player.position = Vector2(200, -(WorldOrigin.period - 50));
      await tickAndSettle(game);
      expect(game.worldShift, 0, reason: 'the fold is still ahead');
      expect(game.trafficSpawner.activeVehicleCount, 0,
          reason: 'precondition: no traffic before the spawn loop');

      // Roll frames WITHOUT draining microtasks until the spawner fires.
      // `add` only queues the car; the queue is applied inside the next
      // frame's tree walk, so the moment this loop exits the car is
      // provably still unmounted — not in world.children, invisible to
      // the fold's walk over the tree, the exact one-frame window of
      // issue #98.
      var ticks = 0;
      while (game.trafficSpawner.activeVehicleCount == 0 && ticks < 600) {
        game.update(1 / 60);
        ticks++;
      }
      expect(game.trafficSpawner.activeVehicleCount, greaterThan(0),
          reason: 'traffic spawned in the pre-fold frame');
      expect(game.world.children.whereType<TrafficVehicle>(), isEmpty,
          reason: 'the spawned car is queued, not yet mounted');

      // Cross the boundary: this one update folds the world first (the
      // car is still unmounted), then mounts the car inside its tree
      // walk — the same order the live loop runs.
      game.player.position = Vector2(200, -(WorldOrigin.period + 200));
      game.update(1 / 60);
      expect(game.worldShift, WorldOrigin.period, reason: 'the fold fired');

      // Settle: the car mounts, its onLoad computes a velocity, and its
      // first update advances past the zero-offset spawn waypoint.
      await tickAndSettle(game);

      // Position and waypoints must share the folded frame: every
      // mounted car sits within one leg of the waypoint it drives to
      // (a same-direction leg spans 3,000 px). The frozen car of the
      // bug sat a whole period — 100,800 px — from its first waypoint,
      // a gap no amount of driving could close, and reappeared one
      // period later as a car parked in the road.
      final cars = game.world.children.whereType<TrafficVehicle>().toList();
      expect(cars, isNotEmpty, reason: 'the spawned car is mounted and live');
      for (final car in cars) {
        expect(car.currentWaypointIndex, lessThan(car.path.length),
            reason: 'a live car still has road to drive');
        expect(
          car.position.distanceTo(car.path[car.currentWaypointIndex]),
          lessThan(5000),
          reason: 'position and waypoints live in the same world frame '
              '(issue #98)',
        );
      }

      // And the car drives: half a second of ticks moves every car that
      // survives the window. The frozen one never moved at all.
      final spawnedAt = {
        for (final car in cars) car: car.position.clone(),
      };
      advanceGameTime(game, 0.5);
      await drain();
      final stillLive =
          game.world.children.whereType<TrafficVehicle>().toSet();
      for (final car in cars.where(stillLive.contains)) {
        expect(car.position.distanceTo(spawnedAt[car]!), greaterThan(5.0),
            reason: 'the car drives on instead of parking in the road');
      }
    });

    test('a ghost replay re-enters the live frame across a fold', () async {
      final game = await mountQuietGame(777);
      await preloadSprites(game);
      game.player.position = Vector2(200, -(WorldOrigin.period + 500.0));
      await tickAndSettle(game);
      expect(game.worldShift, WorldOrigin.period);

      // A trace recorded in true-distance coordinates: its car drove past
      // true 50,000 px. In the folded frame that rides at the trace y
      // plus the world's shift.
      final ghost = GhostCar(
        trace: const GhostTrace(
          dateKey: '2026-09-27',
          score: 0,
          banked: true,
          vehicleId: 'taxi_yellow',
          samples: [200, -50000, 200, -50000],
        ),
        sprite: Sprite(game.images.fromCache(
            VehicleSprites.playerSpritePath(gameState.selectedVehicle))),
      );
      game.world.add(ghost);
      await tickAndSettle(game);

      expect(ghost.position.y, closeTo(-50000 + WorldOrigin.period, 0.01),
          reason: 'the ghost rides the same folded frame as the road');
    });

    test('a folded run records its ghost trace in true distance', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final dailyGameState = GameStateService(storage);
      await dailyGameState.loadSaveData();

      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: dailyGameState,
        endlessSeed: 314,
        isDailyShift: true,
      )
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink());
      final daily = await mountGame(game);
      daily.player.children
          .whereType<RectangleHitbox>()
          .single
          .collisionType = CollisionType.inactive;

      // Drive past the fold, then spend all three lives to settle the run
      // and its trace (the wreck is what records it, issue #15).
      daily.player.position = Vector2(200, -(WorldOrigin.period + 1000.0));
      await tickAndSettle(game);
      expect(game.worldShift, WorldOrigin.period);
      for (var life = 0; life < 3; life++) {
        game.onCrash();
        // Run out the crash stall between lives.
        advanceGameTime(game, TaxiGame.crashStallSeconds + 0.01);
      }
      await drain();

      final stored = dailyGameState.ghostFor(DailyShift.todayKey);
      expect(stored, isNotNull);
      // The last recorded sample sits at the taxi's true distance.
      final lastY = stored!.samples.last.toDouble();
      expect(-lastY, closeTo(game.runDistance, 2.0),
          reason: 'traces count true road, not folded world y');
    });
  });

  group('creeping across a world fold (issue #53)', () {
    /// Issue #53's reproduction shape: the old tests teleported straight
    /// past the boundary, which never builds anything *ahead* of a fold
    /// the taxi has not crossed yet. A slow crossing does, and everything
    /// built in that band must land in the frame the world is in *now* —
    /// not the frame its true distance canonically belongs to, a whole
    /// period ahead.
    Future<TaxiGame> mountAtCreepStart(int seed) async {
      final game = await mountGame(endlessGame(seed));
      // Coverage and geometry, not survival.
      game.player.children.whereType<RectangleHitbox>().single.collisionType =
          CollisionType.inactive;
      await preloadSprites(game);
      // Just short of the first fold (100,800): everything the next
      // ~3,000 px builds straddles the boundary.
      game.player.position = Vector2(200, -98000);
      await tickAndSettle(game);
      expect(game.worldShift, 0, reason: 'the fold has not happened yet');
      return game;
    }

    test('every step of a slow crossing keeps chunks and fares in the '
        'live frame', () async {
      final game = await mountAtCreepStart(424242);

      // The fare invariant is judged on zones the frame they appear: a
      // fare spawned correctly waits inside [camera − cullBehind,
      // camera + generationAhead] of true distance. The bug's fare was
      // placed a whole period off, read as hopelessly behind, and culled
      // by the same update that spawned it — so only its spawn frame can
      // catch it. (Counters alone cannot: a frame may legitimately cull
      // one driven-past fare and spawn the next, 1,400 px apart.)
      var knownZones = game.world.children.whereType<PickupZone>().toSet();

      // Creep 60 px per frame across the boundary and 3,200 px beyond.
      // The taxi moves *relatively* — absolute y re-folds every frame
      // past the boundary — and the loop drains between frames so Flame
      // flushes the deferred world adds each tick queues.
      for (var i = 0; i < 100; i++) {
        game.player.position += Vector2(0, -60);
        game.update(1 / 60);
        await drain();

        // Every live chunk sits exactly where its pinned true distance
        // says it must, in the frame the world is in right now. Before
        // the fix, the chunks built ahead of the pending fold sat a full
        // period off, and the road for true distance 100,000-102,400 px
        // was never drawn.
        for (final segment in game.world.children.whereType<RoadSegment>()) {
          expect(
            segment.position.y,
            closeTo(game.worldShift - segment.distanceAtTop, 0.5),
            reason: 'a chunk built ahead of the fold landed a whole '
                'period away (top distance ${segment.distanceAtTop})',
          );
        }

        // Every fare that appeared this frame waits in the live frame,
        // within the generation window the controller spawns into.
        final zones = game.world.children.whereType<PickupZone>().toSet();
        final cameraDistance =
            game.worldShift - game.camera.viewfinder.position.y;
        for (final zone in zones.difference(knownZones)) {
          final zoneDistance = game.worldShift - zone.position.y;
          expect(
            zoneDistance,
            inInclusiveRange(
              cameraDistance - EndlessFareController.cullBehind - 50,
              cameraDistance + EndlessFareController.generationAhead + 50,
            ),
            reason: 'a fare spawned a whole period off its slot at camera '
                'distance ${cameraDistance.toStringAsFixed(0)} (issue #53 '
                'would have culled it unseen this very frame)',
          );
        }
        knownZones = zones;
      }

      expect(game.worldShift, WorldOrigin.period,
          reason: 'the creep really crossed the boundary');
      // The fold was crossed with fares in play and none lost to it. The
      // teleport to the creep start skips slots 0-69 behind (counted
      // missed, never spawned — the legitimate path), so what generated
      // here is the approach band and beyond: the generator must have
      // dealt and passed fare 72, the issue's culled-unseen fare.
      expect(game.fareController!.nextFareIndex, greaterThan(72),
          reason: 'fare 72, the first slot past the fold, was dealt '
              'during the creep');
      // And the road covers the viewport at the end of it all.
      expectViewportCovered(game);
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('a fare picked up before the fold carries its stored dropoff '
        'across it', () async {
      final game = await mountGame(endlessGame(424242));
      await preloadSprites(game);
      final fare = game.course!.fare(71);

      // Sanity: this slot really does straddle the crossing — pickup in
      // the fold's approach band, the delivery effects' frozen vectors
      // riding across it. Slot 71 spans [99,400, 100,800).
      expect(fare.pickupDistance, lessThan(WorldOrigin.period));
      expect(fare.pickupDistance,
          greaterThan(WorldOrigin.period - EndlessCourse.slotLength),
          reason: 'the pickup waits in the fold\'s approach band');

      // No traffic for the boarding: the approach band sits at full
      // pressure, and one stray car through a parked cab would freeze
      // the run mid-test. (The creep below inactivates the hitbox
      // anyway — this test is about geometry, not survival.)
      game.trafficSpawner.clear();

      // Pull up *short* of the kerb first, so the generator deals the
      // approach band's fares around the taxi — a zone that materializes
      // already overlapping a stationary cab never fires its collision
      // start, so the boarding needs the overlap to begin.
      game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 200);
      await tickAndSettle(game);

      // The passenger data is what the delivery effects read (burst,
      // coin flight): capture it now, while the zone still exists — the
      // pickup removes the zone from the world. The teleport's catch-up
      // burn (70 skipped slots) leaves the generator a few ticks behind,
      // so wait for the zone like the fold tests do.
      PickupZone? zone;
      for (var i = 0; i < 40 && zone == null; i++) {
        await tickAndSettle(game);
        for (final z in game.world.children.whereType<PickupZone>().toList()) {
          if ((z.position - fare.pickup).length < 1.0) zone = z;
        }
      }
      expect(zone, isNotNull,
          reason: 'fare 71\'s pickup zone is live in the approach band');
      final passenger = zone!.passenger;

      // Then arrive at the kerb, the way the world-coherence harness
      // boards fares: onto a zone that already exists.
      game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
      game.update(1 / 60);
      await drain();
      expect(game.player.hasPassenger, isTrue, reason: 'passenger boarded');

      // Survive the crossing: coverage, not crashes.
      game.player.children.whereType<RectangleHitbox>().single.collisionType =
          CollisionType.inactive;

      // Creep across the fold holding the passenger.
      for (var i = 0; i < 90; i++) {
        game.player.position += Vector2(0, -60);
        game.update(1 / 60);
        await drain();
      }
      expect(game.worldShift, WorldOrigin.period);
      expect(game.player.hasPassenger, isTrue,
          reason: 'the carried fare was never culled across the fold');
      expect(game.fareController!.faresRelocated, greaterThan(0),
          reason: 'the creep drove past the original dropoff, so the '
              'forgiveness rule moved it — across the fold, where the old '
              'placement dealt it a whole period away and the fare died');

      // The invariant that survives both the fold *and* relocations: the
      // frozen dropoff vector agrees with the live zone it belongs to,
      // in the live frame. The fold moved the zone; the relocations
      // moved it further; the stored vector must have ridden both, or
      // the delivery's burst and coins land a whole period from the kerb
      // the fare actually settles at.
      final dropoffZone = game.world.children
          .whereType<DropoffZone>()
          .where((z) => z.passenger == passenger)
          .single;
      expect(dropoffZone.position.y,
          inInclusiveRange(-WorldOrigin.period, 0),
          reason: 'the relocated dropoff waits in the live frame, not a '
              'stale one');
      expect(
        passenger.dropoffLocation.y,
        closeTo(dropoffZone.position.y, 1.0),
        reason: 'the stored dropoff stayed in the live frame across the '
            'fold (issue #53)',
      );
    }, timeout: const Timeout(Duration(minutes: 4)));
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
