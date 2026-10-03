import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/virtual_stick.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The one-thumb relative-drag virtual stick (issue #29): the response
/// curve's rules (dead zone, amplification, clamp, axis independence)
/// and the event-driven wiring that feeds the taxi — including the crash
/// stall's suspension of it (issue #91): a thumb held through a
/// non-fatal crash keeps owning the stick, so the shift resumes under a
/// thumb that drives instead of one that must lift and land again — and
/// the claim that crosses the freeze (issue #105): a thumb that lifts
/// and *lands* mid-stall claims the stick the same way, so the resume
/// hands it over without a third press. The pause menu's RESUME re-feeds
/// the same way (issue #103): a thumb that moved during the pause is
/// tracked, and the cab must not leave the menu driving the axes it
/// entered with. The release's fade-out draws throughout (issue #202):
/// the ring's geometry outlives the thumb exactly as long as the fade
/// does, so the ring and knob are painted while they fade instead of
/// vanishing the instant the thumb lifts. The thumb handover (issue
/// #200): a second thumb that lands while the first holds is
/// remembered, and the owner's lift hands the stick straight to it —
/// no dead coast, no third press.
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

    /// Mounts [mounted] headlessly (the endless-run test pattern:
    /// [Game.mount] is what GameWidget calls in production).
    Future<void> mountGame(TaxiGame mounted) async {
      game = mounted;
      game.onGameResize(Vector2(400, 800));
      await game.onLoad();
      // ignore: invalid_use_of_internal_member
      game.mount();
      await game.ready();
      stick = game.virtualStick!;
    }

    /// The mounted endless shift these tests drive. Headless games have
    /// no overlay builder map; the crash flow adds 'shiftWrecked' at the
    /// third endless crash and the pause flow adds 'pauseMenu', so
    /// stand-ins are registered as GameScreen does (the three-strikes and
    /// bank-or-push test patterns).
    Future<void> mountRun() => mountGame(TaxiGame(
          levelLoader: LevelLoaderService(),
          gameState: gameState,
          endlessSeed: 42,
        )
          ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
          ..overlays.addEntry('pauseMenu', (_, __) => const SizedBox.shrink()));

    /// Advances game time by [seconds], in clamped frames (issue #36): no
    /// single frame may consume more than [TaxiGame.maxUpdateDelta], so
    /// fast-forwarding the crash stall means many small frames — exactly
    /// the invariant the live game runs under.
    void advanceGameTime(double seconds) {
      var remaining = seconds;
      while (remaining > 0) {
        final step = math.min(remaining, TaxiGame.maxUpdateDelta);
        game.update(step);
        remaining -= step;
      }
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

    /// A drag update with the semantics the real dispatcher has: the
    /// globalPosition Flutter's `MultiDragPointerState._move` reports is
    /// the thumb's position *after* the move, and the delta is that same
    /// event's movement. [glide] above pins globalPosition at the touch
    /// origin — the pre-move convention — under which the old
    /// canvasEndPosition arithmetic accidentally agreed with the truth;
    /// these events are the ones that exposed the double count (issue
    /// #41).
    DragUpdateEvent move(Offset delta, Offset thumb) => DragUpdateEvent(
          7,
          game,
          DragUpdateDetails(delta: delta, globalPosition: thumb),
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

    test('a flick back to centre steers nothing (issue #41)', () async {
      await mountRun();

      // The report's path, in its two large steps: down at (210, 700),
      // one big move right-and-up to (245, 670), then one big move
      // straight back above the origin at (210, 670).
      stick.onDragStart(touchDown(at: const Offset(210, 700)));
      stick.onDragUpdate(
        move(const Offset(35, -30), const Offset(245, 670)),
      );
      expect(game.player.steeringInput, greaterThan(0),
          reason: 'the first step really is to the right');

      stick.onDragUpdate(
        move(const Offset(-35, 0), const Offset(210, 670)),
      );

      // The thumb now rests directly above the origin: no steering, and
      // only the (0, -30) glide's throttle. Under the double count the
      // computed offset after the second step was (-35, -30) — full left
      // lock while the thumb sat on the origin, and the cab dived for
      // the left kerb.
      expect(game.player.steeringInput, 0);
      expect(game.player.throttleInput, greaterThan(0));
      // The whole offset is (0, -30): exactly the pure-up glide's share.
      expect(
        game.player.throttleInput,
        closeTo(
          VirtualStick.resolve(
            Vector2(0, -30),
            radius: VirtualStick.stickRadius,
          ).throttle,
          1e-9,
        ),
      );
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

    /// A second thumb's landing while the owner holds (issue #200),
    /// with the position the thumb rests at by then.
    DragStartEvent secondThumbDown() => DragStartEvent(
          8,
          game,
          DragStartDetails(globalPosition: const Offset(120, 700)),
        );

    DragUpdateEvent secondThumbGlide(Offset delta, Offset thumb) =>
        DragUpdateEvent(
          8,
          game,
          DragUpdateDetails(delta: delta, globalPosition: thumb),
        );

    test('the waiting thumb inherits the stick the moment the owner '
        'lifts (issue #200)', () async {
      await mountRun();

      // The owner drives; a second thumb lands lower-half mid-drive and
      // glides while it waits — 60 px right, to rest at (180, 700).
      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(0, -60)));
      expect(game.player.throttleInput, greaterThan(0));

      stick.onDragStart(secondThumbDown());
      stick.onDragUpdate(
        secondThumbGlide(const Offset(60, 0), const Offset(180, 700)),
      );
      expect(stick.isActive, isTrue,
          reason: 'the owner still holds the stick');
      expect(game.player.throttleInput, greaterThan(0),
          reason: 'the waiting thumb\'s glide feeds nothing while the '
              'owner holds');

      // The lift is the handover: no dead coast, no third press. The
      // new owner starts at dead centre, so nothing feeds yet.
      stick.onDragEnd(DragEndEvent(7, DragEndDetails()));
      expect(stick.isActive, isTrue,
          reason: 'the waiting thumb owns the stick the moment the '
              'owner lifts');
      expect(game.player.throttleInput, 0,
          reason: 'a fresh origin sits inside the dead zone');

      // The inherited origin is where the waiting thumb *rests* —
      // (180, 700), tracked through the glide — not where it landed at
      // (120, 700). Gliding back to the landing point is therefore a
      // 60 px left glide: full left lock. A stale origin would compute
      // a (0, 0) offset and read dead centre.
      stick.onDragUpdate(
        secondThumbGlide(const Offset(-60, 0), const Offset(120, 700)),
      );
      expect(game.player.steeringInput, -1.0,
          reason: 'the handover tracked the waiting thumb, so the origin '
              'moved with it');
      expect(game.player.throttleInput, 0, reason: 'the glide was pure '
          'horizontal');
    });

    test('a waiting thumb that lifts before the owner hands nothing over '
        '(issue #200)', () async {
      await mountRun();

      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(0, -60)));
      stick.onDragStart(secondThumbDown());

      // The waiting thumb gives up and lifts first: its claim dies with
      // it, so the owner's later lift releases outright rather than
      // handing the stick to a pointer that left the screen.
      stick.onDragEnd(DragEndEvent(8, DragEndDetails()));
      stick.onDragEnd(DragEndEvent(7, DragEndDetails()));

      expect(stick.isActive, isFalse,
          reason: 'no handover: the waiting thumb lifted first');
      expect(game.player.throttleInput, 0);

      // And the dropped pointer feeds nothing afterwards — the exact
      // dead-stick symptom the old code left every second thumb with.
      stick.onDragUpdate(
        secondThumbGlide(const Offset(0, -60), const Offset(120, 640)),
      );
      expect(game.player.throttleInput, 0,
          reason: 'a pointer that lifted owns nothing');
    });

    test('a run ending under two thumbs hands the stick to nobody '
        '(issue #200)', () async {
      await mountRun();

      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(0, -60)));
      stick.onDragStart(secondThumbDown());

      // The third crash ends the run under both thumbs: the terminal
      // freeze releases through _freezePlayer, which empties the
      // waiting room with the ownership — a waiting thumb must not
      // inherit a dead run when the owner's lift arrives after the end.
      game.onCrash();
      advanceGameTime(TaxiGame.crashStallSeconds + 0.01);
      game.onCrash();
      advanceGameTime(TaxiGame.crashStallSeconds + 0.01);
      game.onCrash();
      expect(game.isGameActive, isFalse, reason: 'the shift is over');

      stick.onDragEnd(DragEndEvent(7, DragEndDetails()));
      expect(stick.isActive, isFalse,
          reason: 'the ending cleared the waiting room: no handover');

      stick.onDragUpdate(
        secondThumbGlide(const Offset(0, -60), const Offset(120, 640)),
      );
      expect(game.player.throttleInput, 0,
          reason: 'the once-waiting thumb feeds nothing on a dead run');
    });

    test('a thumb landing while paused waits for nothing (issue #200)',
        () async {
      await mountRun();

      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(0, -60)));
      game.pauseGame();

      // Pause outranks the waiting room as it outranks the claim (the
      // issue #105 ordering): a menu owns the screen, so this landing
      // is refused outright and queues nothing.
      stick.onDragStart(secondThumbDown());
      stick.onDragEnd(DragEndEvent(7, DragEndDetails()));
      expect(stick.isActive, isFalse,
          reason: 'nothing was queued while paused, so the lift '
              'releases outright');

      game.resumeGame();
      expect(game.player.throttleInput, 0,
          reason: 'the resume re-feeds an owner that does not exist');
      stick.onDragUpdate(
        secondThumbGlide(const Offset(0, -60), const Offset(120, 640)),
      );
      expect(game.player.throttleInput, 0,
          reason: 'the refused landing never became an owner');
    });

    test('a crash under a held thumb suspends the stick, not kills it '
        '(issue #91)', () async {
      await mountRun();

      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(36, -36)));
      expect(game.player.throttleInput, greaterThan(0));

      game.onCrash(); // one life down, the world stalls

      // The frozen cab must not keep driving on the thumb's inputs — but
      // unlike a run *ending*, the thumb keeps ownership: the shift
      // resumes in 1.2 s under this same pointer. The release the stall
      // used to do cleared the pointer id, and the stick then sat dead
      // until the thumb lifted and landed again.
      expect(stick.isActive, isTrue,
          reason: 'a stall is not an ending; the thumb keeps the stick');
      expect(game.player.steeringInput, 0);
      expect(game.player.throttleInput, 0);

      // Through the stall the offset keeps tracking but nothing is fed:
      // the events are the thumb's, the world is not listening yet.
      stick.onDragUpdate(glide(const Offset(72, -144)));
      expect(game.player.steeringInput, 0);
      expect(game.player.throttleInput, 0);
    });

    test('a thumb held dead still through the stall drives at the resume '
        '(issue #91)', () async {
      await mountRun();

      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(0, -60)));
      expect(game.player.throttleInput, greaterThan(0));

      game.onCrash();
      // No drag update at all from here on: the thumb simply holds where
      // it was. A still thumb emits no events, so the resume itself must
      // re-feed the offset it holds.
      advanceGameTime(TaxiGame.crashStallSeconds + 0.01);

      expect(game.isGameActive, isTrue, reason: 'the stall has expired');
      expect(game.player.throttleInput, greaterThan(0),
          reason: 'the held offset drives the moment the world moves '
              'again, without waiting for a move event');
      expect(game.player.steeringInput, 0, reason: 'the glide was pure up');
    });

    test('a drag update from the held thumb drives after the stall '
        '(issue #91)', () async {
      await mountRun();

      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(0, -60)));
      game.onCrash();
      advanceGameTime(TaxiGame.crashStallSeconds + 0.01);

      // The report's exact repro: one drag update from the same pointer
      // after the stall — dropped entirely by the pointer guard before
      // the fix, because the stall had released the stick's ownership.
      stick.onDragUpdate(glide(const Offset(-60, 0)));

      expect(game.player.steeringInput, -1.0,
          reason: 'the diagonal past the rim is full left lock');
      expect(game.player.throttleInput, greaterThan(0));
    });

    test('a thumb that lifts and lands again mid-stall still drives the '
        'resume (issue #105)', () async {
      await mountRun();

      // The issue's path: drive into the crash, lift the thumb during
      // the freeze, and land a *new* finger before the stall ends. #91
      // kept a thumb held at crash time driving; one landing mid-freeze
      // was gated out of the claim, and the resume then had no owner to
      // hand the stick to — a dead cab until that finger lifted and
      // pressed a third time.
      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(0, -60)));
      game.onCrash();
      stick.onDragEnd(DragEndEvent(7, DragEndDetails()));
      expect(stick.isActive, isFalse, reason: 'the thumb lifted');

      expect(game.isCrashStall, isTrue, reason: 'precondition: mid-freeze');
      stick.onDragStart(DragStartEvent(
        9,
        game,
        DragStartDetails(globalPosition: const Offset(200, 600)),
      ));
      expect(stick.isActive, isTrue,
          reason: 'the claim crosses the stall — the world is coming back');
      expect(game.player.throttleInput, 0,
          reason: 'nothing is fed while the world is frozen');

      // The new thumb glides: the offset tracks, the feed waits for the
      // resume.
      stick.onDragUpdate(DragUpdateEvent(
        9,
        game,
        DragUpdateDetails(
          delta: const Offset(0, -60),
          globalPosition: const Offset(200, 540),
        ),
      ));
      expect(game.player.throttleInput, 0);

      advanceGameTime(TaxiGame.crashStallSeconds + 0.01);

      expect(game.isGameActive, isTrue, reason: 'the stall has expired');
      expect(stick.isActive, isTrue);
      expect(game.player.throttleInput, greaterThan(0),
          reason: 'the stall\'s own resume hands the stick to the thumb '
              'that landed during it — no third press needed');
      expect(game.player.steeringInput, 0, reason: 'the glide was pure up');
    });

    test('a touch while paused mid-stall is still refused (issue #105)',
        () async {
      await mountRun();

      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(0, -60)));
      game.onCrash();
      stick.onDragEnd(DragEndEvent(7, DragEndDetails()));

      // The pause menu opens through the freeze: a menu is up, so a
      // landing thumb claims nothing — the stall is the only freeze a
      // claim may cross, and pause outranks it.
      game.pauseGame();
      expect(game.paused, isTrue);
      expect(game.isCrashStall, isTrue, reason: 'still mid-stall');
      stick.onDragStart(touchDown());
      expect(stick.isActive, isFalse,
          reason: 'pause outranks the stall: the menu owns the screen');

      game.resumeGame();
      advanceGameTime(TaxiGame.crashStallSeconds + 0.01);

      expect(game.isGameActive, isTrue);
      expect(stick.isActive, isFalse,
          reason: 'the refused claim never became an owner');
      expect(game.player.throttleInput, 0,
          reason: 'nothing drives a resume no thumb claimed');
    });

    test('the third crash still releases the stick for good (issue #91)',
        () async {
      await mountRun();

      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(0, -60)));
      expect(game.player.throttleInput, greaterThan(0));

      game.onCrash();
      advanceGameTime(TaxiGame.crashStallSeconds + 0.01);
      expect(stick.isActive, isTrue, reason: 'one crash is survivable');
      game.onCrash();
      advanceGameTime(TaxiGame.crashStallSeconds + 0.01);
      expect(stick.isActive, isTrue, reason: 'two crashes are survivable');

      game.onCrash(); // the third: the shift ends as a wreck

      expect(game.isGameActive, isFalse, reason: 'the shift is over');
      expect(stick.isActive, isFalse,
          reason: 'a terminal ending drops the thumb — the run will not '
              'resume, so the stick must not pretend it will');
      expect(game.player.throttleInput, 0);
      stick.onDragUpdate(glide(const Offset(72, -144)));
      expect(game.player.throttleInput, 0,
          reason: 'the stale pointer feeds nothing after a release');
    });

    test('a level fail still releases the stick (issue #91)', () async {
      // The tutorial ladder's terminal path shares the endless endings'
      // halt; pin it in level mode too, where the crash routes through
      // onLevelFailed instead of the three-strike flow.
      await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      )..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink()));

      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(0, -60)));
      expect(game.player.throttleInput, greaterThan(0));

      game.onLevelFailed();

      expect(stick.isActive, isFalse,
          reason: 'the level\'s terminal ending releases the stick');
      expect(game.player.throttleInput, 0);
      stick.onDragUpdate(glide(const Offset(72, -144)));
      expect(game.player.throttleInput, 0,
          reason: 'the stale pointer feeds nothing after a release');
    });

    test('a thumb that centred under the pause menu drives nothing after '
        'RESUME (issue #103)', () async {
      await mountRun();

      stick.onDragStart(touchDown());
      // Full lock right and half throttle, as a running player holds it.
      stick.onDragUpdate(glide(const Offset(36, -36)));
      expect(game.player.steeringInput, 1.0);
      expect(game.player.throttleInput, greaterThan(0));

      game.pauseGame();

      // The thumb glides back to the origin while the menu is up: the
      // offset keeps tracking, but the stick feeds nothing while paused —
      // so the cab still carries its pre-pause axes, the exact stale
      // drive the issue names, and only the resume can replace them.
      stick.onDragUpdate(glide(const Offset(-36, 36)));
      expect(game.player.throttleInput, greaterThan(0),
          reason: 'the pause itself feeds nothing, so the last fed value '
              'stands until the resume re-feeds');

      game.resumeGame();

      // The re-fed offset is the origin: dead centre, both axes. Before
      // the fix the stale full-lock drive survived the menu, and the cab
      // kept steering and throttling until the thumb next moved.
      expect(game.paused, isFalse);
      expect(stick.isActive, isTrue,
          reason: 'a pause is not an ending; the thumb still owns the stick');
      expect(game.player.steeringInput, 0);
      expect(game.player.throttleInput, 0);
    });

    test('RESUME re-feeds the offset the thumb actually holds, not the one '
        'it entered the pause with (issue #103)', () async {
      await mountRun();

      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(0, -60)));
      // The offset the thumb will rest at after the pause: 24 px of the
      // 60 px glide returned, and no further events at all — a dead-still
      // thumb emits nothing for a resume to ride on.
      final held = VirtualStick.resolve(
        Vector2(0, -36),
        radius: VirtualStick.stickRadius,
      );

      game.pauseGame();
      stick.onDragUpdate(glide(const Offset(0, 24)));

      game.resumeGame();

      expect(
        game.player.throttleInput,
        closeTo(held.throttle, 1e-9),
        reason: 'the resume drives with where the thumb is, not where it '
            'was when the pause landed',
      );
      expect(game.player.steeringInput, 0, reason: 'the glide was pure up');
    });

    test('suspend zeroes and resume re-feeds, and only a live game is fed',
        () async {
      await mountRun();

      // Without an owning thumb, resume is a no-op — not a crash on the
      // absent offset.
      stick.resume();
      expect(game.player.throttleInput, 0);

      stick.onDragStart(touchDown());
      stick.onDragUpdate(glide(const Offset(0, -60)));
      expect(game.player.throttleInput, greaterThan(0));

      // Paused: suspension zeroes, and the resume must not re-feed —
      // the same gate every feeding entry point carries.
      game.paused = true;
      stick.suspend();
      expect(game.player.throttleInput, 0);
      stick.resume();
      expect(game.player.throttleInput, 0, reason: 'paused feeds nothing');

      game.paused = false;
      stick.resume();
      expect(game.player.throttleInput, greaterThan(0),
          reason: 'the live game re-feeds the held offset');
    });

    test('the ring fades out after release and in while held (issue #202)',
        () async {
      await mountRun();

      stick.onDragStart(touchDown());
      stick.update(1);
      expect(stick.opacity, 1.0);

      stick.release();
      // The thumb is gone but the ring is not: the fade-out needs the
      // geometry for its whole 125 ms, where the bug's release() nulled
      // the origin and offset the instant the thumb lifted — an opacity
      // faithfully fading over a ring that was already undrawable.
      expect(stick.hasGeometry, isTrue,
          reason: 'release keeps the geometry the fade still draws');
      stick.update(0.05); // half a second of the 8/s fade
      expect(stick.opacity, closeTo(0.6, 1e-9));
      expect(stick.hasGeometry, isTrue,
          reason: 'mid-fade, the ring is still drawable');

      stick.update(1);
      expect(stick.opacity, 0.0);
      expect(stick.hasGeometry, isFalse,
          reason: 'the finished fade drops the geometry it kept');

      // A fresh claim starts from a clean slate either way: the dropped
      // geometry is not the last touch's ghost.
      stick.onDragStart(touchDown(at: const Offset(120, 700)));
      stick.update(1);
      expect(stick.hasGeometry, isTrue);
    });
  });
}
