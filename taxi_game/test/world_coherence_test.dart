import 'package:flame/components.dart';
import 'package:flutter/material.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/dropoff_zone.dart';
import 'package:taxi_game/game/components/pickup_zone.dart';
import 'package:taxi_game/game/components/road_segment.dart';
import 'package:taxi_game/game/systems/collision_rules.dart';
import 'package:taxi_game/game/systems/road_chunk_manager.dart';
import 'package:taxi_game/game/systems/world_origin.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// World coherence across a shift-ending overlay's retry (issue #32).
///
/// TestFlight build 1033 rendered two runs' geometry at once after a bank
/// and DRIVE AGAIN: the ended shift's street and the fresh shift's street
/// sharing one frame at a hard vertical seam. Whatever the rendering path,
/// the invariant it breaks is absolute — after any retry, the scene tree
/// contains exactly one run's world: one chunk manager, chunks that belong
/// to it and render the current run's environment, one road surface under
/// the taxi, and the taxi standing on that surface.
///
/// Every shift-ending overlay's retry routes through the same teardown
/// ([TaxiGame.retryShift] or [TaxiGame.restartLevel] — both call
/// [TaxiGame.startEndlessRun]), so each test below drives one real ending
/// and then holds the whole tree to that invariant.
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

  TaxiGame endlessGame(int seed) => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: seed,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());

  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // Internal on purpose: this is exactly the call GameWidget makes once
    // the game has loaded. Without it the world never mounts and mid-update
    // adds take Flame's direct-add path.
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  Future<void> drain() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.value();
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// One simulated tick plus the drains for everything it queued to mount,
  /// then a second tick so the queue is applied.
  Future<void> tickAndSettle(TaxiGame game) async {
    game.update(1 / 60);
    await drain();
    game.update(1 / 60);
    await drain();
  }

  /// Drives the freshly-started shift a little way down the road — the
  /// TestFlight screenshot was taken 12 m into the new run — settling as
  /// the real loop does between frames.
  Future<void> driveMetres(TaxiGame game, double metres) async {
    final px = metres * 10; // RunSummary.pixelsPerMetre
    var driven = 0.0;
    var step = 0;
    while (driven < px) {
      game.player.position += Vector2(0, -20);
      driven += 20;
      game.update(1 / 60);
      if (step++ % 5 == 0) await drain();
    }
    await drain();
    game.update(1 / 60);
    await drain();
  }

  /// Delivers the first fare the course offers, ending in the timed
  /// bank-or-push prompt, then banks. Returns with the banked panel up
  /// and the shift settled.
  ///
  /// The camera jump down to the kerbs leaves the chunk manager syncing a
  /// window one tick behind the taxi — the same state a player driving to
  /// a dropoff is always in — so the shift's final tick queues chunk adds
  /// that have not mounted yet. Banking and retrying right there is the
  /// exact tap timing that orphaned geometry on device (issue #32).
  Future<void> bankViaFirstFare(TaxiGame game) async {
    final fare = game.course!.fare(0);
    game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
    game.update(1 / 60);
    game.player.position = Vector2(fare.dropoff.x, fare.dropoff.y + 30);
    game.update(1 / 60);
    await drain();
    expect(game.bankPrompt.isActive, isTrue, reason: 'the choice is up');

    // Drive on past the dropoff — one tick of it — so the last sync
    // before the panel queued fresh window chunks, then bank mid-flow,
    // the way a fast tap lands.
    game.player.position += Vector2(0, -2000);
    game.update(1 / 60);
    game.bankShift();
    expect(game.overlays.isActive('shiftBanked'), isTrue);
    expect(game.isGameActive, isFalse, reason: 'the shift is settled');
  }

  /// Spends all three lives so the shift ends wrecked and the wreck panel
  /// goes up. When [queueStragglers] is set, the taxi jumps down the road
  /// one tick before the third crash, leaving the ended run's final sync
  /// with chunk adds still queued to mount — the state the wreck panel's
  /// DRIVE AGAIN tap inherits on device (issue #32).
  Future<void> wreckTheShift(TaxiGame game,
      {bool queueStragglers = false}) async {
    for (var life = 0; life < 3; life++) {
      if (life > 0) {
        // Run out the previous crash's stall so the next crash counts.
        for (var i = 0; i < 3; i++) {
          game.update(1.0);
        }
      }
      if (queueStragglers && life == 2) {
        // Jump down the road, then give the loop two ticks: the first
        // moves the camera (the world updates before the camera, so the
        // manager's sync still reads the old view), the second has the
        // sync queue the fresh window's chunks — mounted only at the
        // next tick's start, i.e. pending when the panel goes up.
        game.player.position += Vector2(0, -2000);
        game.update(1 / 60);
        game.update(1 / 60);
      }
      game.onCrash();
    }
    await drain();
    expect(game.overlays.isActive('shiftWrecked'), isTrue);
  }

  /// The issue #32 invariant, in full. Broken anywhere, any time, after
  /// any retry, this fails — the guard that keeps the sheared-world
  /// defect from ever coming back through a new teardown path.
  void expectWorldCoherent(TaxiGame game) {
    // 1. Exactly one chunk manager, and it is the game's current one.
    final managers =
        game.world.children.whereType<RoadChunkManager>().toList();
    expect(managers, hasLength(1),
        reason: 'a second (stale) chunk manager survives the retry');
    final manager = managers.single;
    expect(identical(manager, game.roadChunks), isTrue,
        reason: 'the surviving manager is the run in progress');

    // 2. Every road segment in the tree belongs to that manager: tracked
    //    by it, placed by its index math in the live world frame, and
    //    rendering the current run's environment — never the previous
    //    run's.
    final segments = game.world.children.whereType<RoadSegment>().toList();
    expect(segments.length, manager.chunkCount,
        reason: 'every road segment in the tree is a chunk the live '
            'manager tracks — an untracked segment is the previous '
            'run\'s geometry');
    for (final segment in segments) {
      // Chunk i's band is [i·L, (i+1)·L) and its pinned topDistance is the
      // band's far edge (i+1)·L, so the key the manager tracks it under is
      // one below the index its top distance floor-rounds to.
      final index =
          RoadChunkManager.chunkIndexForDistance(segment.distanceAtTop) - 1;
      expect(manager.hasChunk(index), isTrue,
          reason: 'chunk $index is tracked by the live manager');
      expect(segment.environment, same(game.environment),
          reason: 'chunk $index renders the current run\'s environment');
      expect(
          segment.position.y,
          closeTo(
              WorldOrigin.worldYForDistance(segment.distanceAtTop), 0.5),
          reason: 'chunk $index sits in the live world frame');
    }
    expect(manager.chunkCount, lessThanOrEqualTo(10),
        reason: 'the chunk count stays within the manager\'s window');

    // 3. The player stands on the current run's road geometry.
    final road = game.environment!.roadAt(game.runDistance);
    expect(game.player.position.x, inInclusiveRange(road.leftX, road.rightX),
        reason: 'the taxi is on the road surface');

    // 4. Exactly one road surface under the taxi: two overlapping chunks
    //    at the taxi's y is two streets composited into one frame.
    final taxiY = game.player.position.y;
    final underTaxi = segments.where((segment) {
      final top = segment.position.y; // anchor: topCentre
      return taxiY >= top && taxiY <= top + segment.length;
    }).toList();
    expect(underTaxi, hasLength(1),
        reason: 'exactly one road surface exists under the taxi');
  }

  group('after a banked shift, DRIVE AGAIN (issue #32)', () {
    test('the fresh run\'s world is coherent', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      await bankViaFirstFare(game);

      // DRIVE AGAIN: a fresh shift, and 12 m down the road — where the
      // TestFlight screenshot caught two runs' geometry in one frame —
      // the world must still be one run's world.
      game.retryShift();
      expect(game.isGameActive, isTrue, reason: 'the fresh shift is live');
      await tickAndSettle(game);
      expect(game.score, 0, reason: 'the fresh shift starts at zero');
      await driveMetres(game, 12);

      expectWorldCoherent(game);
    });
  });

  group('after a wrecked shift, DRIVE AGAIN (issue #32)', () {
    test('the fresh run\'s world is coherent', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      await wreckTheShift(game, queueStragglers: true);

      // DRIVE AGAIN from the wreck panel.
      game.retryShift();
      await tickAndSettle(game);
      await driveMetres(game, 12);

      expectWorldCoherent(game);
    });

    test('the fresh run\'s world is coherent when the retry lands inside '
        'the crash juice', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // Two lives spent the ordinary way — hit-stop and stall run out
      // between crashes, as the live game does.
      for (var life = 0; life < 2; life++) {
        game.onCrash(_fakeCrashReport());
        game.update(0.11); // expires the 0.1 s hit-stop
        game.update(1.2); // runs out the 1.2 s crash stall
      }

      // The third crash right on top of a down-road jump: two ticks so
      // the ended run's final sync has chunk adds queued, then the
      // hit-stop freezes the tree with them pending while the wreck
      // panel waits. A fast DRIVE AGAIN tap — [TaxiGame.update] still
      // skipping the tree — must still come up coherent once the world
      // unfreezes.
      game.player.position += Vector2(0, -2000);
      game.update(1 / 60);
      game.update(1 / 60);
      game.onCrash(_fakeCrashReport());
      expect(game.hitStop.isActive, isTrue,
          reason: 'the crash froze the frame');
      expect(game.overlays.isActive('shiftWrecked'), isFalse,
          reason: 'the wreck panel waits out the hit-stop');
      game.retryShift();
      await driveMetres(game, 12);

      expectWorldCoherent(game);
    });
  });

  group('after a level-failed RETRY mid-shift (issue #32)', () {
    test('the restarted run\'s world is coherent', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      // The crash overlay's RETRY restarts an endless run on the same
      // seed through [TaxiGame.restartLevel] — the third route into the
      // shared teardown. Drive first so its final sync has chunk adds
      // queued when the restart lands.
      game.player.position += Vector2(0, -2000);
      game.update(1 / 60);
      game.update(1 / 60);
      game.restartLevel();
      await tickAndSettle(game);
      await driveMetres(game, 12);

      expect(game.runDistance, greaterThan(0), reason: 'the run restarted');
      expectWorldCoherent(game);
    });
  });

  group('after a run that crossed a world fold, DRIVE AGAIN (issue #32)',
      () {
    test('a banked shift past the fold leaves the fresh run coherent, '
        'back at the origin', () async {
      final game = await mountGame(endlessGame(424242));
      await tickAndSettle(game);

      // Drive past one fold boundary, then deliver a fare from the live
      // frame and bank the shift there.
      game.player.position = Vector2(200, -(WorldOrigin.period + 1000.0));
      await tickAndSettle(game);
      expect(game.worldShift, WorldOrigin.period, reason: 'the world folded');

      List<PickupZone> pickups() =>
          game.world.children.whereType<PickupZone>().toList();
      for (var i = 0; i < 40 && pickups().isEmpty; i++) {
        await tickAndSettle(game);
      }
      expect(pickups(), isNotEmpty,
          reason: 'the folded course still offers fares');
      final pickup = pickups().first;
      game.player.position = Vector2(pickup.position.x, pickup.position.y + 30);
      game.update(1 / 60);
      expect(game.player.hasPassenger, isTrue, reason: 'passenger boarded');

      final dropoff = game.world.children
          .whereType<DropoffZone>()
          .firstWhere((z) => z.passenger.isPickedUp && !z.passenger.isDelivered);
      game.player.position =
          Vector2(dropoff.position.x, dropoff.position.y + 30);
      game.update(1 / 60);
      await drain();
      expect(game.bankPrompt.isActive, isTrue);
      game.bankShift();
      expect(game.overlays.isActive('shiftBanked'), isTrue);

      // DRIVE AGAIN: the fold belongs to the ended run. The fresh shift
      // starts a fresh world frame at the origin and stays coherent.
      game.retryShift();
      await tickAndSettle(game);
      await driveMetres(game, 12);

      expect(game.worldShift, 0,
          reason: 'a fresh shift starts a fresh world frame');
      expect(game.camera.viewfinder.position.x, TaxiGame.roadCenterX,
          reason: 'the camera stays locked on the road');
      expectWorldCoherent(game);
    });
  });
}

/// A plausible crash report, as a real contact would carry, so the crash
/// juice (hit-stop, shake, burst) runs the same code paths a device crash
/// does.
CrashReport _fakeCrashReport() {
  final position = Vector2(200, 0);
  return CrashReport(
    severity: ContactSeverity.crash,
    vehicleKind: 'sedan',
    playerSpeed: 150,
    trafficSpeed: 0,
    closingSpeed: 150,
    closingSpeedAlongImpact: 150,
    playerPosition: position,
    trafficPosition: position + Vector2(0, -30),
    contactPoint: position,
  );
}
