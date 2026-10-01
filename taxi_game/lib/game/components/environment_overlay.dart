import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../taxi_game.dart';

/// The windshield (issue #24): a screen-space layer that makes weather and
/// time of day *felt*, mounted over the world like [SpeedLines] but under
/// the Flutter HUD.
///
///  - **darkness** tints the whole viewport toward night and punches the
///    taxi's headlight pool and forward throw back out of the tint, so a
///    night shift reads as lit-by-you, not dimmed uniformly;
///  - **fog** lays a translucent grey card with a soft hole around the
///    taxi — the world beyond it simply is not there;
///  - **rain** streams slanted streaks down the glass.
///
/// [TaxiGame] drives all three intensities from the run environment every
/// frame; the component itself only animates the rain streaks. Every layer
/// is free (draws and updates nothing) when its intensity is zero, so a
/// clear day costs nothing.
class EnvironmentOverlay extends PositionComponent
    with HasGameReference<TaxiGame> {
  /// 0..1, from the run's time of day.
  double darkness = 0;

  /// 0..1, from the run's weather.
  double rainIntensity = 0;
  double fogIntensity = 0;

  /// How far the headlight throw punches through darkness/fog, in px.
  static const double headlightReach = 260.0;

  /// Radius of the always-visible pool around the taxi.
  static const double ambientRadius = 130.0;

  final math.Random _random = math.Random();
  late final List<_RainStreak> _streaks;
  late final Vector2 _screenSize;

  final Paint _layerPaint = Paint();
  final Paint _streakPaint = Paint()
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round;

  @override
  void onLoad() {
    super.onLoad();

    // The viewport has a fixed virtual resolution (400x800); children are
    // laid out in that space regardless of the physical canvas.
    _screenSize = game.camera.viewport.virtualSize.clone();

    _streaks = List.generate(28, (_) => _spawnStreak(initial: true));
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (rainIntensity <= 0) return;

    // Rain falls fast and slants back with the taxi's motion; streaks
    // recycle off the bottom back above the top.
    for (var i = 0; i < _streaks.length; i++) {
      final s = _streaks[i];
      s.y += s.speed * dt;
      s.x -= s.speed * 0.12 * dt;
      if (s.y - s.length > _screenSize.y) {
        _streaks[i] = _spawnStreak();
      }
    }
  }

  _RainStreak _spawnStreak({bool initial = false}) {
    return _RainStreak(
      x: 8 + _random.nextDouble() * (_screenSize.x - 16),
      y: initial
          ? _random.nextDouble() * _screenSize.y
          : -_random.nextDouble() * 90,
      length: 22 + 34 * _random.nextDouble(),
      speed: 900 + 700 * _random.nextDouble(),
      alpha: 0.18 + 0.25 * _random.nextDouble(),
    );
  }

  @override
  void render(Canvas canvas) {
    if (fogIntensity > 0) _renderFog(canvas);
    if (darkness > 0) _renderDarkness(canvas);
    if (rainIntensity > 0) _renderRain(canvas);
  }

  /// Where the taxi currently sits in this viewport's coordinate space:
  /// the world offset by the viewfinder (the camera is horizontally locked
  /// on the road and vertically on the taxi).
  Offset _playerScreenPos() {
    final viewfinder = game.camera.viewfinder.position;
    final half = _screenSize / 2;
    final p = game.isMounted && game.isPlayerReady
        ? game.player.position
        : viewfinder;
    return Offset(
      p.x - (viewfinder.x - half.x),
      p.y - (viewfinder.y - half.y),
    );
  }

  void _renderDarkness(Canvas canvas) {
    final player = _playerScreenPos();

    canvas.saveLayer(
      Offset.zero & _screenSize.toSize(),
      _layerPaint,
    );

    // Night tint over everything the viewport shows.
    canvas.drawRect(
      Offset.zero & _screenSize.toSize(),
      Paint()
        ..color = const Color(0xFF050A18)
            .withValues(alpha: 0.62 * darkness)
        ..style = PaintingStyle.fill,
    );

    // Punch the headlight throw back out: a long soft ellipse ahead of
    // the taxi plus an ambient pool around it.
    _cutLight(
        canvas,
        Offset(player.dx, player.dy - headlightReach * 0.55),
        const Size(110, headlightReach));
    _cutLight(
        canvas,
        player,
        const Size.square(ambientRadius));

    // A warm additive glow so the light reads as light, not just as
    // visible road.
    canvas.drawCircle(
      Offset(player.dx, player.dy - headlightReach * 0.45),
      60,
      Paint()
        ..color = const Color(0xFFFFE9B0)
            .withValues(alpha: 0.10 * darkness)
        ..blendMode = BlendMode.plus,
    );

    canvas.restore();
  }

  /// Erases the tint in a soft ellipse — the headlight's footprint.
  void _cutLight(Canvas canvas, Offset center, Size radius) {
    canvas.drawOval(
      Rect.fromCenter(center: center, width: radius.width * 2,
          height: radius.height * 2),
      Paint()
        // dstOut, not clear: clear zeroes every pixel the oval covers,
        // reading neither the paint nor its shader — the gradient below
        // was dead weight and the cut came out a hard-edged, fully
        // clear oval (issue #142). dstOut multiplies the destination
        // by (1 − source alpha), so the gradient finally does its job:
        // ~95% of the tint erased at the centre, fading to untouched at
        // the rim — the soft pool of light the doc comments promise.
        ..blendMode = BlendMode.dstOut
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.95),
            const Color(0xFFFFFFFF).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCenter(
            center: center, width: radius.width * 2,
            height: radius.height * 2)),
    );
  }

  void _renderFog(Canvas canvas) {
    final player = _playerScreenPos();

    canvas.saveLayer(
      Offset.zero & _screenSize.toSize(),
      _layerPaint,
    );
    canvas.drawRect(
      Offset.zero & _screenSize.toSize(),
      Paint()
        ..color = const Color(0xFFB8BEC6).withValues(alpha: 0.55 *
            fogIntensity)
        ..style = PaintingStyle.fill,
    );

    // The air around the cab is clearer — a soft bubble of sight.
    _cutLight(canvas, player, const Size.square(ambientRadius * 1.15));
    _cutLight(
        canvas,
        Offset(player.dx, player.dy - headlightReach * 0.5),
        const Size(120, headlightReach * 0.9));

    canvas.restore();
  }

  void _renderRain(Canvas canvas) {
    for (final s in _streaks) {
      _streakPaint.color =
          const Color(0xFFCFE4FF).withValues(alpha: s.alpha * rainIntensity);
      canvas.drawLine(
        Offset(s.x, s.y - s.length),
        Offset(s.x + s.length * 0.12, s.y),
        _streakPaint,
      );
    }
  }
}

class _RainStreak {
  _RainStreak({
    required this.x,
    required this.y,
    required this.length,
    required this.speed,
    required this.alpha,
  });

  double x;
  double y;
  final double length;
  final double speed;
  final double alpha;
}
