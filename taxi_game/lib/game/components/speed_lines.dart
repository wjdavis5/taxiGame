import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../taxi_game.dart';

/// Screen-space speed lines (issue #7): vertical streaks that stream down
/// the screen while the taxi is near top speed, so velocity reads without
/// looking at a number.
///
/// Mounted on the camera viewport, so it draws over the world in viewport
/// coordinates — the streaks are a property of the windshield, not of the
/// road. Nothing is drawn (or moved) while [intensity] is zero, so the
/// component is free until the taxi is actually fast.
class SpeedLines extends PositionComponent with HasGameReference<TaxiGame> {
  SpeedLines({this.streakCount = 16, math.Random? random})
      : _random = random ?? math.Random();

  /// How many streaks the effect uses. Fixed — streaks are recycled, so
  /// the per-frame cost never grows.
  final int streakCount;

  final math.Random _random;

  /// 0..1 — set from the taxi's forward speed every frame by [TaxiGame].
  double intensity = 0;

  /// Vertical position of each streak, exposed so tests can watch the
  /// streaks stream.
  Iterable<double> get streakYs => _streaks.map((s) => s.y);

  late final List<_Streak> _streaks;
  late final Vector2 _screenSize;

  final Paint _paint = Paint()
    ..strokeWidth = 2.0
    ..strokeCap = StrokeCap.round;

  @override
  void onLoad() {
    super.onLoad();

    // The viewport has a fixed virtual resolution (400x800); children are
    // laid out in that space regardless of the physical canvas.
    _screenSize = game.camera.viewport.virtualSize.clone();

    _streaks = List.generate(streakCount, (i) {
      return _Streak(
        x: _randomX(),
        y: _random.nextDouble() * _screenSize.y,
        length: 40 + 60 * _random.nextDouble(),
        baseAlpha: 0.25 + 0.35 * _random.nextDouble(),
        speedFactor: 0.7 + 0.6 * _random.nextDouble(),
      );
    });
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (intensity <= 0) return;

    // The taxi drives up, so the air rushes down the windshield.
    final fallSpeed = 300 + 1100 * intensity;
    for (final streak in _streaks) {
      streak.y += fallSpeed * streak.speedFactor * dt;
      if (streak.y - streak.length > _screenSize.y) {
        // Recycle off the bottom back to just above the top.
        streak.y = -_random.nextDouble() * 80;
        streak.x = _randomX();
        streak.length = 40 + 60 * _random.nextDouble();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (intensity <= 0) return;

    for (final streak in _streaks) {
      _paint.color = const Color(0xFFFFFFFF)
          .withValues(alpha: streak.baseAlpha * intensity);
      canvas.drawLine(
        Offset(streak.x, streak.y - streak.length),
        Offset(streak.x, streak.y),
        _paint,
      );
    }
  }

  double _randomX() =>
      8 + _random.nextDouble() * (_screenSize.x - 16);
}

class _Streak {
  _Streak({
    required this.x,
    required this.y,
    required this.length,
    required this.baseAlpha,
    required this.speedFactor,
  });

  double x;
  double y;
  double length;
  final double baseAlpha;
  final double speedFactor;
}
