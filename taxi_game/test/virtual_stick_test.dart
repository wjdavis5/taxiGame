import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/virtual_stick.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The one-thumb relative-drag virtual stick (issue #29): the response
/// curve's rules (dead zone, amplification, clamp, axis independence)
/// and the event-driven wiring that feeds the taxi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stick response curve', () {
    const radius = VirtualStick.stickRadius;
    const fullLockInput =
        (VirtualStick.fullLockFraction - VirtualStick.deadZoneFraction) /
            (1 - VirtualStick.deadZoneFraction);

    test('the dead zone inputs nothing', () {
      // Just under the 10% gate in every direction, including the rim
      // edge itself.
      for (final offset in [
        Vector2(0, -0.09 * radius),
        Vector2(0.09 * radius, 0),
        Vector2(0, 0.09 * radius),
        Vector2(-0.09 * radius, 0),
        Vector2(0.06 * radius, -0.06 * radius), // diagonal inside the gate
        Vector2.zero(),
      ]) {
        final input = VirtualStick.resolve(offset, radius: radius);
        expect(input.steering, 0, reason: 'offset $offset');
        expect(input.throttle, 0, reason: 'offset $offset');
      }
    });

    test('the response ramps from zero at the dead-zone edge', () {
      // A hair past the gate: barely off zero, not a jump to cruising.
      final input = VirtualStick.resolve(
        Vector2(0, -0.11 * radius),
        radius: radius,
      );
      expect(input.throttle, greaterThan(0));
      expect(input.throttle, lessThan(0.05));
    });

    test('full steering lock lands at half the stick radius', () {
      final input = VirtualStick.resolve(
        Vector2(VirtualStick.fullLockFraction * radius, 0),
        radius: radius,
      );
      expect(input.steering, closeTo(1.0, 1e-9));
      expect(input.throttle, 0);
    });

    test('the amplification spans the full radius', () {
      // Half a radius up is about the dead-zone-to-rim midpoint.
      final half = VirtualStick.resolve(Vector2(0, -0.5 * radius), radius: radius);
      expect(half.throttle, closeTo(fullLockInput, 1e-9));
      // The rim is everything it has.
      final rim = VirtualStick.resolve(Vector2(0, -radius), radius: radius);
      expect(rim.throttle, 1.0);
    });

    test('input clamps past the rim — harder glides never add force', () {
      final atRim = VirtualStick.resolve(Vector2(4 * radius, 0), radius: radius);
      expect(atRim.steering, 1.0);
      final farUp = VirtualStick.resolve(Vector2(0, -9 * radius), radius: radius);
      expect(farUp.throttle, 1.0);
      final farDown =
          VirtualStick.resolve(Vector2(0, 9 * radius), radius: radius);
      expect(farDown.throttle, -1.0);
      // A huge diagonal saturates steering and gives throttle its
      // directional share (1/√2 at 45°) — the radial response splits
      // the axes instead of topping both.
      final diagonal =
          VirtualStick.resolve(Vector2(9 * radius, -9 * radius), radius: radius);
      expect(diagonal.steering, 1.0);
      expect(diagonal.throttle, closeTo(0.70710678, 1e-6));
    });

    test('the axes are independent', () {
      // Pure horizontal: steering only, exactly no throttle.
      final right = VirtualStick.resolve(Vector2(0.7 * radius, 0), radius: radius);
      expect(right.steering, greaterThan(0));
      expect(right.throttle, 0);
      final left = VirtualStick.resolve(Vector2(-0.7 * radius, 0), radius: radius);
      expect(left.steering, lessThan(0));
      expect(left.throttle, 0);
      // Pure vertical: throttle/brake only, exactly no steering.
      final up = VirtualStick.resolve(Vector2(0, -0.8 * radius), radius: radius);
      expect(up.throttle, greaterThan(0));
      expect(up.steering, 0);
      final down = VirtualStick.resolve(Vector2(0, 0.8 * radius), radius: radius);
      expect(down.throttle, lessThan(0));
      expect(down.steering, 0);
    });

    test('drag up accelerates, drag down brakes — never reverses', () {
      expect(
        VirtualStick.resolve(Vector2(0, -radius), radius: radius).throttle,
        1.0,
      );
      expect(
        VirtualStick.resolve(Vector2(0, radius), radius: radius).throttle,
        -1.0,
      );
    });

    test('the response is monotonic in glide distance', () {
      var previous = -1.0;
      for (var px = 0.11 * radius; px <= radius; px += 2) {
        final steering =
            VirtualStick.resolve(Vector2(px, 0), radius: radius).steering;
        expect(steering, greaterThanOrEqualTo(previous));
        previous = steering;
      }
    });
  });

  group('a stick wired to a live run', () {
    late GameStateService gameState;
    late TaxiGame game;
    late VirtualStick stick;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      gameState = GameStateService(storage);
      await gameState.loadSaveData();
    });

    /// Mounts an endless run headlessly (the endless-run test pattern:
    /// [Game.mount] is what GameWidget calls in production).
    Future<void> mountRun() async {
      game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: 42,
      );
      game.onGameResize(Vector2(400, 800));
      await game.onLoad();
      // ignore: invalid_use_of_internal_member
      game.mount();
      await game.ready();
      stick = game.virtualStick!;
    }

    /// A touch that starts at (200, 600) — lower half of the 400x800
    /// canvas — as [DragStartEvent] would carry it from the dispatcher
    /// (canvas positions are the identity when the game is headless).
    DragStartEvent touchDown({Offset at = const Offset(200, 600)}) =>
        DragStartEvent(7, game, DragStartDetails(globalPosition: at));

    DragUpdateEvent glide(Offset delta) => DragUpdateEvent(
          7,
          game,
          DragUpdateDetails(
            delta: delta,
            globalPosition: const Offset(200, 600),
          ),
        );

    test('a lower-half touch becomes the stick origin and holds the taxi '
        'still', () async {
      await mountRun();

      stick.onDragStart(touchDown());

      expect(stick.isActive, isTrue);
      // Touching alone is not the old hold-to-go pedal: a fresh origin
      // sits inside the dead zone, so nothing moves.
      expect(game.player.isAccelerating, isFalse);
      expect(game.player.throttleInput, 0);
      expect(game.player.steeringInput, 0);
    });

    test('a glide up-right steers and throttles the taxi', () async {
      await mountRun();

      stick.onDragStart(touchDown());
      // (36, -36) px: half a radius diagonally — full lock right, and a
      // solid throttle that stops short of the rim.
      stick.onDragUpdate(glide(const Offset(36, -36)));

      expect(game.player.steeringInput, 1.0);
      expect(game.player.throttleInput, greaterThan(0.4));
      expect(game.player.throttleInput, lessThan(0.6));
      expect(stick.input.throttle, game.player.throttleInput);
    });

    test('an upper-half touch is ignored', () async {
      await mountRun();

      stick.onDragStart(
        touchDown(at: const Offset(200, 200)), // upper half of 800
      );

      expect(stick.isActive, isFalse);
      stick.onDragUpdate(glide(const Offset(72, -72)));
      expect(game.player.steeringInput, 0);
      expect(game.player.throttleInput, 0);
    });

    test('a touch when the game is not live is ignored', () async {
      await mountRun();
      game.isGameActive = false;

      stick.onDragStart(touchDown());

      expect(stick.isActive, isFalse);
      stick.onDragUpdate(glide(const Offset(36, -36)));
      expect(game.player.steeringInput, 0);
      expect(game.player.throttleInput, 0);
    });

    test('a second thumb changes nothing while the first holds the stick',
        () async {
      await mountRun();

      stick.onDragStart(touchDown()); // pointer 7 owns the stick
      stick.onDragStart(
        DragStartEvent(
          8,
          game,
          DragStartDetails(globalPosition: const Offset(60, 600)),
        ),
      );
      stick.onDragUpdate(glide(const Offset(36, -36)));

      expect(stick.isActive, isTrue);
      expect(game.player.steeringInput, 1.0);

      // The stranger's release must not drop the owner's inputs.
      stick.onDragEnd(DragEndEvent(8, DragEndDetails()));
      expect(stick.isActive, isTrue);
      expect(game.player.throttleInput, greaterThan(0.4));

      // The owner's release does.
      stick.onDragEnd(DragEndEvent(7, DragEndDetails()));
      expect(stick.isActive, isFalse);
      expect(game.player.steeringInput, 0);
      expect(game.player.throttleInput, 0);
    });

    test('a crash under a held thumb releases the stick', () async {
      await mountRun();

      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(36, -36)));
      expect(game.player.throttleInput, greaterThan(0));

      game.onCrash(); // one life down, the world stalls

      expect(stick.isActive, isFalse);
      expect(game.player.steeringInput, 0);
      expect(game.player.throttleInput, 0);
      // Updates from the stale touch stay dead through the stall.
      stick.onDragUpdate(glide(const Offset(72, -144)));
      expect(game.player.steeringInput, 0);
      expect(game.player.throttleInput, 0);
    });

    test('the ring fades out after release and in while held', () async {
      await mountRun();

      stick.onDragStart(touchDown());
      stick.update(1);
      expect(stick.opacity, 1.0);

      stick.release();
      stick.update(0.05); // half a second of the 8/s fade
      expect(stick.opacity, closeTo(0.6, 1e-9));
      stick.update(1);
      expect(stick.opacity, 0.0);
    });
  });
}
