import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../taxi_game.dart';

/// A coin that bursts out of a world position and flies to the HUD coin
/// counter (issue #7).
///
/// The counter itself is a Flutter widget above the game, so the coin aims
/// at the world point beneath it — the top-right corner of the visible
/// world — recomputed every frame, which keeps the coin on course while
/// the camera follows the taxi. Removes itself on arrival.
class CoinPop extends PositionComponent with HasGameReference<TaxiGame> {
  CoinPop({
    required Vector2 startPosition,
    this.delay = 0,
    math.Random? random,
  })  : _random = random ?? math.Random(),
        super(
          position: startPosition.clone(),
          anchor: Anchor.center,
          size: Vector2.all(radius * 2),
        );

  /// Seconds to wait before the coin appears — used to stagger volleys so
  /// coins stream to the counter instead of arriving as one clump.
  final double delay;

  /// How long the flight from spawn to the counter takes, seconds.
  static const double flightDuration = 0.55;

  /// The first portion of the flight pops the coin outward from where it
  /// spawned before it homes in on the counter.
  static const double scatterPortion = 0.25;

  /// The coin shrinks to this fraction of its size as it nears the HUD.
  static const double finalScale = 0.45;

  /// Coin radius in world px.
  static const double radius = 7.0;

  /// Where the HUD counter sits, inset from the top-right corner of the
  /// visible world (the HUD's own top-right coin chip).
  static const double hudInsetX = 64;
  static const double hudInsetY = 46;

  final math.Random _random;

  late double _delayRemaining;
  double _age = 0;

  /// Where the coin spawned, x fixed and y in true-distance terms: world
  /// y folds back toward the origin mid-flight (issue #30), so the stored
  /// anchors re-enter the live frame on every use.
  late final double _startX;
  late final double _startTrueY;

  /// The outward pop's offset from the spawn; the homing leg starts where
  /// it ends.
  late final Vector2 _scatterOffset;

  /// The spawn point in the world's live frame.
  Vector2 get _start => Vector2(_startX, _startTrueY + game.worldShift);

  final Paint _rimPaint = Paint()
    ..color = const Color(0xFFB8860B)
    ..style = PaintingStyle.fill;

  final Paint _facePaint = Paint()
    ..color = const Color(0xFFFFD700)
    ..style = PaintingStyle.fill;

  final Paint _shinePaint = Paint()
    ..color = const Color(0x99FFFFFF)
    ..style = PaintingStyle.fill;

  @override
  void onLoad() {
    super.onLoad();

    _delayRemaining = delay;
    _startX = position.x;
    _startTrueY = position.y - game.worldShift;

    // Pop outward in a random direction before homing in on the counter.
    final angle = _random.nextDouble() * 2 * math.pi;
    final distance = 26 + 18 * _random.nextDouble();
    _scatterOffset = Vector2(math.cos(angle), math.sin(angle)) * distance;
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (_delayRemaining > 0) {
      _delayRemaining -= dt;
      if (_delayRemaining > 0) return;
      // The delay ran out mid-tick: fall through so the flight starts on
      // this very frame instead of losing one to the wait.
    }

    _age += dt;
    final t = (_age / flightDuration).clamp(0.0, 1.0);

    if (t <= scatterPortion) {
      final s = t / scatterPortion;
      final easeOut = 1 - (1 - s) * (1 - s);
      position = _start + _scatterOffset * easeOut;
    } else {
      final p = (t - scatterPortion) / (1 - scatterPortion);
      final eased = p * p; // ease-in: the coin accelerates toward the HUD
      final target = _hudTarget();
      final scatterEnd = _start + _scatterOffset;
      position = Vector2(
        scatterEnd.x + (target.x - scatterEnd.x) * eased,
        scatterEnd.y + (target.y - scatterEnd.y) * eased,
      );
    }

    final s = 1.0 - (1.0 - finalScale) * t;
    scale.setValues(s, s);

    if (t >= 1.0) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (_delayRemaining > 0) return;

    canvas.drawCircle(Offset.zero, radius, _rimPaint);
    canvas.drawCircle(Offset.zero, radius - 2, _facePaint);
    canvas.drawCircle(const Offset(-2, -2), 1.8, _shinePaint);
  }

  /// The world point directly under the HUD coin counter.
  Vector2 _hudTarget() {
    final visible = game.camera.visibleWorldRect;
    return Vector2(visible.right - hudInsetX, visible.top + hudInsetY);
  }
}
