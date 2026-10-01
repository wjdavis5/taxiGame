import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../taxi_game.dart';
import 'fare_glyph.dart';
import 'player_vehicle.dart';
import '../../models/passenger_data.dart';

/// Visual marker for passenger dropoff location
class DropoffZone extends CircleComponent with HasGameReference<TaxiGame>, CollisionCallbacks {
  final PassengerData passenger;
  final VoidCallback onDropoff;

  bool _isActive = false; // Only active after passenger is picked up
  bool _isCompleted = false;
  double _pulseAnimation = 0.0;

  // The pulse breathes this private brush radius, never the component's
  // own `radius`: CircleComponent's radius setter rewrites `size`, and
  // under anchor.center every resize slides the top-left local origin
  // that the fixed-offset children hang from — the detection
  // CircleHitbox at (baseRadius, baseRadius), the special-fare label at
  // (baseRadius, 2·baseRadius + 18) — while render() keeps the drawn
  // flag dead on its kerb, so the detection circle drifted up to 5 px
  // per axis off the marker the player aims at and the label wobbled
  // with it (issue #143). The component stays baseRadius square for
  // life; only the brush shrinks and grows. An inactive dropoff never
  // pulses at all: _drawRadius sits at baseRadius, exactly the resting
  // size the grey flag always drew at.
  double _drawRadius = baseRadius;

  static const double baseRadius = 30.0;
  static const double detectionRadius = 40.0;

  DropoffZone({
    required Vector2 position,
    required this.passenger,
    required this.onDropoff,
  }) : super(
          position: position,
          radius: baseRadius,
          anchor: Anchor.center,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // Add collision detection, centered on the visible circle
    add(CircleHitbox(
      radius: detectionRadius,
      position: Vector2.all(baseRadius),
      anchor: Anchor.center,
    ));

    // A special fare's destination names itself too (issue #25): with
    // several fares live at once, the flag the meter is running toward
    // has to be findable — the awkward fare's far-side kerb above all.
    if (!passenger.fareType.isStandard) {
      add(TextComponent(
        text: passenger.fareType.zoneLabel,
        anchor: Anchor.center,
        position: Vector2(baseRadius, 2 * baseRadius + 18),
        textRenderer: TextPaint(
          style: TextStyle(
            color: passenger.fareType.markerColor,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    // Check if passenger has been picked up
    if (!_isActive && passenger.isPickedUp) {
      _isActive = true;
    }

    if (!_isActive || _isCompleted) return;

    // Pulse animation
    _pulseAnimation += dt * 2.0;
    _drawRadius = baseRadius + (math.sin(_pulseAnimation) * 5.0);
  }

  @override
  void render(Canvas canvas) {
    if (_isCompleted) return;

    // Skip CircleComponent's default paint and draw centered on the
    // component (local origin is the top-left corner, not the center).
    // Every circle below reads _drawRadius, the pulsing brush — size
    // never moves, so this translate lands on the same kerb all shift.
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);

    final color = _isActive ? Colors.blue : Colors.grey;
    final opacity = _isActive ? 0.6 : 0.3;

    // Draw outer glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, _drawRadius + 10, glowPaint);

    // Draw main circle
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset.zero, _drawRadius, paint);

    // Draw border
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(Offset.zero, _drawRadius, borderPaint);

    // Draw the fare kind's glyph at the dropoff's lower weight (issue #35).
    _drawKindGlyph(canvas, _isActive ? Colors.white : Colors.grey.shade400);

    canvas.restore();
  }

  /// The same glyph the pickup marker wears (issue #35), stroked rather
  /// than filled: the lighter weight so a fare's destination and its
  /// departure read apart even in greyscale, and the shape still says
  /// which kind of fare the meter is running toward.
  void _drawKindGlyph(Canvas canvas, Color inkColor) {
    paintFareGlyph(
      canvas,
      passenger.fareType,
      ink: Paint()
        ..color = inkColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);

    if (!_isActive || _isCompleted) return;

    // A settled run delivers nothing (issue #71): the world keeps
    // ticking under the end-of-run panel, and a cab coasting on its
    // last velocity must not roll in and complete a fare the ending
    // already forfeited.
    if (game.isShiftOver) return;

    // Check if player entered the zone with passenger
    if (other is PlayerVehicle && passenger.isPickedUp) {
      _dropoffPassenger();
    }
  }

  void _dropoffPassenger() {
    if (_isCompleted) return;

    _isCompleted = true;
    passenger.isDelivered = true;

    // Call the dropoff callback
    onDropoff();

    // Remove this zone from the game
    removeFromParent();
  }
}
