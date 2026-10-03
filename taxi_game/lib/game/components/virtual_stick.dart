import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../taxi_game.dart';

/// The two axes a stick drag resolves to: [steering] −1..1 (left..right)
/// and [throttle] −1..1 (full brake..full speed). Pure data, so tests can
/// pin the response without a game.
class StickInput {
  const StickInput(this.steering, this.throttle);

  static const StickInput zero = StickInput(0, 0);

  final double steering;
  final double throttle;
}

/// The one-thumb relative-drag virtual stick (issue #29), replacing the
/// old hold-anywhere pedal: wherever the thumb first lands in the lower
/// half of the screen becomes the stick's origin, and the input is the
/// drag offset from that origin — horizontal glides steer, vertical ones
/// throttle and brake. The thumb never has to find a widget, and the
/// ring is drawn under the thumb that owns it, so nothing on the street
/// above is hidden.
///
/// Mounted on the camera viewport, so it draws over the world and the
/// weather layer but under the Flutter HUD. Its hit test
/// ([containsLocalPoint]) claims the whole canvas — letterbox bands
/// included (issue #148) — so every drag on the game reaches
/// [onDragStart], which then applies its own gates (live game, lower
/// half, one owner at a time — a second lower-half landing waits and
/// inherits the stick at the owner's lift, issue #200). Events drive
/// everything — no position polling — exactly like the tap input it
/// replaces.
class VirtualStick extends PositionComponent
    with DragCallbacks, HasGameReference<TaxiGame> {
  // --- Sensitivity constants — the playtest retuning knobs (issue #29) ---
  /// Glide distance from origin to rim, in canvas (logical) px. The thumb
  /// works in physical screen space, so this is canvas-sized on purpose.
  static const double stickRadius = 72;

  /// Offsets under this fraction of [stickRadius] input nothing, so a
  /// resting thumb or a jittery lift is not a command.
  static const double deadZoneFraction = 0.10;

  /// Fraction of [stickRadius] at which steering reaches full lock — half
  /// a glide (~36 px) is enough to slam the wheel over; the rest of the
  /// radius is reserved for throttle headroom on the same diagonal.
  static const double fullLockFraction = 0.5;

  /// Ring fade in/out speed, opacity units per second.
  static const double fadeSpeed = 8;

  /// Drawn ring and knob sizes, in viewport px.
  static const double ringRadius = 34;
  static const double knobRadius = 15;

  int? _activePointerId;

  /// The thumb waiting to inherit the stick (issue #200): the last
  /// lower-half landing while an owner already holds it, with that
  /// thumb's current canvas position — tracked by summed deltas in
  /// [onDragUpdate] exactly like the owner's offset, so the handover's
  /// fresh origin is where the waiting thumb rests, not where it first
  /// landed. One slot: a later eligible landing replaces an earlier
  /// one, and a thumb that lifts before the owner does empties it.
  int? _pendingPointerId;
  Vector2? _pendingPosition;

  /// Touch origin and current thumb offset, in canvas coordinates — the
  /// space the thumb physically moves in. Canvas positions are always
  /// valid; local ones go NaN when a drag leaves a component's bounds.
  Vector2? _origin;
  Vector2? _knobOffset;

  /// The axes currently being fed to the taxi.
  StickInput _input = StickInput.zero;

  /// Ring opacity, faded toward 1 while active and 0 when released.
  double opacity = 0;

  /// True while a thumb owns the stick.
  bool get isActive => _activePointerId != null;

  /// True while the ring has geometry to draw — a live origin and
  /// offset. Kept through the released state's fade-out (issue #202) so
  /// [render] has something to paint while the opacity drains, and
  /// dropped by [update] once it has; the geometry exists exactly as
  /// long as the ring could draw. For tests pinning the fade-out: the
  /// bug's state was an opacity faithfully fading over geometry that
  /// [release] had already thrown away.
  @visibleForTesting
  bool get hasGeometry => _origin != null && _knobOffset != null;

  /// The axes this stick is feeding the taxi right now.
  StickInput get input => _input;

  /// The stick's whole response curve, pure and stateless: a raw thumb
  /// offset becomes the two axes the taxi drives with. Dead zone first,
  /// then a radial amplification that starts at zero at the zone's edge
  /// and reaches full at the rim, then per-axis shaping — steering hits
  /// full lock at [fullLockFraction] of a radius, throttle spans it all.
  /// Clamp at both stages: past the rim nothing gets stronger.
  static StickInput resolve(Vector2 offset, {double radius = stickRadius}) {
    final units = offset / radius; // thumb offset in stick radii
    final magnitude = units.length;

    // Dead zone: jitters under the gate input nothing at all.
    if (magnitude <= deadZoneFraction) return StickInput.zero;

    // Clamp past the rim, then amplify so the response ramps from zero
    // at the dead-zone edge to full at the rim.
    final clamped = math.min(magnitude, 1.0);
    final amplified = (clamped - deadZoneFraction) / (1.0 - deadZoneFraction);
    final direction = units / magnitude;

    // The amplified magnitude at the full-lock distance is the divisor
    // that puts steering's saturation exactly on [fullLockFraction].
    const fullLockInput =
        (fullLockFraction - deadZoneFraction) / (1.0 - deadZoneFraction);
    final steering = (direction.x * amplified / fullLockInput)
        .clamp(-1.0, 1.0);

    // Canvas y grows downward, so dragging up (negative) accelerates.
    final throttle = (-direction.y * amplified).clamp(-1.0, 1.0);

    return StickInput(steering, throttle);
  }

  @override
  void onLoad() {
    super.onLoad();
    // Cover the whole fixed-resolution viewport so every drag starts
    // inside this component and Flame delivers it here; the lower-half
    // gate below decides which drags actually stick.
    position = Vector2.zero();
    size = game.camera.viewport.virtualSize.clone();
  }

  /// Claims every touch, wherever on the canvas it lands. [size] covers
  /// the 400×800 virtual viewport, but the canvas letterboxes whenever its
  /// aspect differs: on a 16:9 iPhone (375×667) the viewport renders
  /// 333.5 px wide with ~21 px bands at each side, and a thumb landing in
  /// a band maps to a local x outside [size.x] — Flame delivers drag
  /// starts only to components whose [containsLocalPoint] accepts the
  /// point, so [onDragStart] never fired there and the thumb sat dead
  /// until it lifted and landed again in the picture (issue #148).
  /// Returning true steals from nobody — this is the only component in
  /// the game with event mixins — and [onDragStart]'s own gates (live,
  /// unpaused, lower half, one pointer at a time) still decide which
  /// touches become input.
  @override
  bool containsLocalPoint(Vector2 point) => true;

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    // Same live-game gate the tap input had. Paused too: an overlay is
    // up, and a thumb parked through a pause must not drive on resume —
    // and pause outranks everything below, a stall included (issue
    // #105): a menu over a frozen street owns the screen.
    if (game.paused) return;
    // The crash stall is the one freeze a claim may cross (issue #105):
    // the thumb that lands mid-stall is the thumb the shift resumes
    // under. The claim below already records the pointer and zeroes the
    // feed — exactly [suspend]'s state — so the resume's own re-feed
    // hands the offset over with no other change. #91 kept a thumb held
    // *at* crash time driving; one landing during the freeze used to be
    // gated out here, leaving the cab dead until that thumb lifted and
    // pressed again. Every other not-live state — a terminal ending, an
    // overlay before the run — still refuses the claim.
    if (!game.isGameActive && !game.isCrashStall) return;
    // Relative stick, lower half: the origin is wherever the thumb
    // landed, but only when it landed in thumb reach. Hoisted above the
    // one-thumb gate (issue #200): the lower half is also the waiting
    // room's admission test, so it has to run for a second thumb too.
    final local = game.camera.viewport.globalToLocal(event.canvasPosition);
    if (local.y <= game.camera.viewport.virtualSize.y / 2) return;
    // The waiting room (issue #200): a second thumb used to be dropped
    // right here, and once the owner lifted, that thumb's every update
    // failed the pointer guard in [onDragUpdate] — the cab coasts dead
    // until the thumb lifts and lands a third time. Now the landing is
    // remembered with its position, and the owner's lift hands the
    // stick straight to it. Only a lower-half landing in a claimable
    // state reaches this far — the gates above queue nothing — and one
    // waiting thumb is all a handover needs; while it waits, it changes
    // nothing the old rule did not already promise.
    if (isActive) {
      _pendingPointerId = event.pointerId;
      _pendingPosition = event.canvasPosition.clone();
      return;
    }
    _activePointerId = event.pointerId;
    _origin = event.canvasPosition.clone();
    _knobOffset = Vector2.zero();
    _apply(StickInput.zero);
    // A thumb that lands here has found the stick — the first real
    // input the control hint (issue #37) was waiting for, a tap on the
    // hint included, since the hint sits inside this same region.
    game.onStickEngaged();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    // The waiting thumb tracks too (issue #200): the handover's fresh
    // origin must be where that thumb rests when the owner lifts, not
    // where it landed — a still thumb emits no further updates, so an
    // untracked wait would hand the next owner a stale landing point.
    // Summed deltas, the owner's own issue #41 arithmetic. Tracking
    // only: a second thumb changes nothing while the first holds — the
    // handover, not the glide, is what feeds.
    if (event.pointerId == _pendingPointerId &&
        _pendingPosition != null) {
      _pendingPosition!.add(event.canvasDelta);
      return;
    }
    if (event.pointerId != _activePointerId) return;
    // Track the thumb by summing deltas, never by reading
    // canvasEndPosition (issue #41): Flutter's drag dispatcher reports
    // globalPosition as the *post-move* thumb position (multidrag.dart's
    // `_move` passes `event.position`), while Flame's DragUpdateEvent
    // adds that same event's delta on top — so canvasEndPosition
    // overshot the real thumb by exactly the last event's delta, every
    // update after the first. A flick back to centre then left the knob
    // drawn off to one side and the cab steering the wrong way while the
    // thumb rested on the origin. Summed deltas are the true offset in
    // both update kinds — the first update's delta is the whole
    // accumulated pending delta, later ones are per-event — and
    // [_knobOffset] starts zeroed at drag start.
    _knobOffset!.add(event.canvasDelta);
    final offset = _knobOffset!.clone();
    // A stall or a pause under a held thumb: ownership survives (the
    // crash stall suspends rather than releases, issue #91), the offset
    // keeps tracking so the resume reads where the thumb really is, and
    // feeding waits for a live, unpaused world. A run that *ended* under
    // the thumb released us outright, so its stale pointer never gets
    // past the guard above.
    if (!game.isGameActive || game.paused) return;
    _apply(resolve(offset));
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    // The waiting thumb leaves before the owner does: its claim goes
    // with it, so the owner's later lift cannot hand the stick to a
    // pointer that is no longer on the screen (issue #200).
    if (event.pointerId == _pendingPointerId) {
      _pendingPointerId = null;
      _pendingPosition = null;
      return;
    }
    if (event.pointerId != _activePointerId) return;
    // The handover, captured before release() empties the waiting room
    // below (issue #200): the lift is the one path that may pass the
    // stick on. A terminal ending releases through
    // [TaxiGame._freezePlayer] instead of here, and a waiting thumb
    // must not inherit a dead run.
    final nextPointer = _pendingPointerId;
    final nextPosition = _pendingPosition;
    release();
    if (nextPointer != null && nextPosition != null) {
      // The new owner's claim, exactly a fresh landing's: its resting
      // position as the origin and a zero offset — dead centre, so
      // nothing feeds until the thumb glides — with the ring never
      // leaving the screen the way a release-and-re-press would.
      _activePointerId = nextPointer;
      _origin = nextPosition.clone();
      _knobOffset = Vector2.zero();
      _apply(StickInput.zero);
    }
  }

  /// Ends the touch and zeroes the inputs it was feeding. Also called by
  /// [TaxiGame._freezePlayer] when the run *ends* under the thumb — the
  /// terminal endings' halt, never the crash stall, which [suspend]s
  /// instead so the held thumb survives it (issue #91).
  void release() {
    _activePointerId = null;
    // The geometry deliberately outlives the touch (issue #202): the
    // fade-out still has to draw the ring and knob where the thumb
    // left them, so nulling here — as this used to — left render()
    // nothing to paint from the instant the thumb lifted, and the
    // 125 ms fade computed an opacity nothing consumed. Every reader
    // of the geometry is pointer-guarded ([onDragUpdate] and [resume]
    // both bail without an owning pointer, which release just cleared)
    // and a fresh claim overwrites it at drag start; [update] drops it
    // once the fade has fully emptied. The waiting room empties with
    // the owner (issue #200): terminal endings release through here,
    // and a waiting thumb must not inherit a dead run — nor may a
    // later lift resurrect a pointer that stopped waiting.
    _pendingPointerId = null;
    _pendingPosition = null;
    _apply(StickInput.zero);
  }

  /// Zeroes the fed inputs but keeps the touch: ownership
  /// ([_activePointerId]), the origin, and the tracked offset all
  /// survive, so [resume] — or the next [onDragUpdate] from the same
  /// pointer — drives again without a re-press. A non-fatal crash's
  /// stall suspends rather than releases (issue #91): the shift resumes
  /// 1.2 s later under a thumb that never lifted, and the release the
  /// stall used to do is exactly what made the stick dead through it —
  /// the pointer id was gone, so [onDragUpdate]'s guard dropped every
  /// event from the held thumb until it lifted and landed again.
  void suspend() {
    _apply(StickInput.zero);
  }

  /// Re-feeds the offset a suspended thumb is holding (issue #91): a
  /// dead-still thumb emits no drag updates, so without this the cab
  /// would sit still after the stall until the thumb next moved — right
  /// when the player most needs it moving. Idempotent on a live stick
  /// (the same offset resolves to the same input), a no-op with no
  /// owning thumb, and — like every entry point that feeds — it stays
  /// silent unless the shift is live and unpaused.
  void resume() {
    if (_activePointerId == null || _knobOffset == null) return;
    if (!game.isGameActive || game.paused) return;
    _apply(resolve(_knobOffset!));
  }

  void _apply(StickInput input) {
    _input = input;
    game.player.setSteering(input.steering);
    game.player.setThrottle(input.throttle);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final target = isActive ? 1.0 : 0.0;
    final step = fadeSpeed * dt;
    opacity = opacity < target
        ? math.min(target, opacity + step)
        : math.max(target, opacity - step);
    // The end of the released fade: no thumb owns the stick and the
    // opacity has fully drained, so the geometry release() kept for the
    // fade has nothing left to draw — drop it here, where the fade
    // itself ends, rather than the moment the thumb lifted. The two
    // lifetimes stay in lockstep: [render] needs both a non-zero
    // opacity and the geometry, and this is the one frame where the
    // last need expires. A stick whose updates stop before then (the
    // paused ticker) keeps its frozen opacity too — the ring is drawn
    // at exactly the brightness it stalled at, never more.
    if (!isActive && opacity <= 0) {
      _origin = null;
      _knobOffset = null;
    }
  }

  @override
  void render(Canvas canvas) {
    if (opacity <= 0 || _origin == null || _knobOffset == null) return;

    // Canvas -> viewport space, this component's own drawing space.
    final origin = game.camera.viewport.globalToLocal(_origin!);
    final knobOffset = _knobOffset!.clone();
    if (knobOffset.length > stickRadius) {
      knobOffset.scaleTo(stickRadius);
    }
    final knob = origin + knobOffset;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.35 * opacity);
    canvas.drawCircle(origin.toOffset(), ringRadius, ringPaint);

    final knobPaint = Paint()
      ..color = const Color(0xFFFFC933).withValues(alpha: 0.65 * opacity);
    canvas.drawCircle(knob.toOffset(), knobRadius, knobPaint);
  }
}
