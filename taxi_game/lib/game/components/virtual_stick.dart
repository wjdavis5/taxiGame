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
/// weather layer but under the Flutter HUD, and so its bounds cover the
/// whole screen: every drag on the game reaches [onDragStart], which then
/// applies its own gates (live game, lower half, one touch at a time).
/// Events drive everything — no position polling — exactly like the tap
/// input it replaces.
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

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    // Same live-game gate the tap input had. Paused too: an overlay is
    // up, and a thumb parked through a pause must not drive on resume.
    if (!game.isGameActive || game.paused) return;
    // One stick at a time — a second thumb changes nothing until the
    // first is lifted.
    if (isActive) return;
    // Relative stick, lower half: the origin is wherever the thumb
    // landed, but only when it landed in thumb reach.
    final local = game.camera.viewport.globalToLocal(event.canvasPosition);
    if (local.y > game.camera.viewport.virtualSize.y / 2) {
      _activePointerId = event.pointerId;
      _origin = event.canvasPosition.clone();
      _knobOffset = Vector2.zero();
      _apply(StickInput.zero);
      // A thumb that lands here has found the stick — the first real
      // input the control hint (issue #37) was waiting for, a tap on the
      // hint included, since the hint sits inside this same region.
      game.onStickEngaged();
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (event.pointerId != _activePointerId) return;
    final offset = event.canvasEndPosition - _origin!;
    _knobOffset = offset.clone();
    // A crash can end the run under a held thumb; the freeze already
    // released us — keep tracking the pointer but feed nothing.
    if (!game.isGameActive || game.paused) return;
    _apply(resolve(offset));
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.pointerId != _activePointerId) return;
    release();
  }

  /// Ends the touch and zeroes the inputs it was feeding. Also called by
  /// [TaxiGame._freezePlayer] when the run ends under the thumb.
  void release() {
    _activePointerId = null;
    _origin = null;
    _knobOffset = null;
    _apply(StickInput.zero);
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
