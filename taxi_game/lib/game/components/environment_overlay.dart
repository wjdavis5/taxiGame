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

  /// How far the headlight throw reaches ahead of the taxi, in px. The
  /// cut ellipse is centred 0.55·reach up-screen and spans one reach
  /// beyond that, so the night beam fades out ~403 px (1.55·reach) ahead
  /// of the cab and fog's 0.9-reach bubble ~364 px — the long forward
  /// throw issue #147 restored.
  static const double headlightReach = 260.0;

  /// Radius of the always-visible pool around the taxi.
  static const double ambientRadius = 130.0;

  /// Leftward drift per px of fall — the rain's slant. One number feeds
  /// the streak's motion, the axis it is painted along, and how far
  /// upwind (right) spawning reaches, so the three can never disagree
  /// again. Issue #209 found them split three ways: the motion drifted
  /// −0.12 while the draw leaned +0.12 — every streak slanting against
  /// its own travel — and spawning covered only the viewport's width,
  /// so the drift dragged the whole field left of the columns it
  /// vacated and the screen's bottom-right never saw a drop.
  static const double rainDrift = 0.12;

  /// How many streaks the field keeps in flight.
  static const int rainStreakCount = 28;

  /// The one shader every cut shades with: a radial falloff from 95%
  /// erase at the centre to untouched at the rim, built over the unit
  /// circle so [_cutLight] can stretch it to each oval's shape. Cached
  /// because the pre-#147 code built a gradient and allocated its shader
  /// for every cut on every frame.
  late final Paint _cutPaint = Paint()
    ..blendMode = BlendMode.dstOut
    ..shader = RadialGradient(
      colors: [
        const Color(0xFFFFFFFF).withValues(alpha: 0.95),
        const Color(0xFFFFFFFF).withValues(alpha: 0.0),
      ],
    ).createShader(const Rect.fromLTWH(-1, -1, 2, 2));

  /// Reseedable, not final: [reseedRainForTest] swaps it so a test's
  /// rain is reproducible (the game itself never reseeds).
  math.Random _random = math.Random();

  /// Reassigned wholesale by [reseedRainForTest], hence not `final`.
  late List<_RainStreak> _streaks;
  late final Vector2 _screenSize;

  final Paint _layerPaint = Paint();
  final Paint _streakPaint = Paint()
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round;

  /// The viewport card every layer paints over (issue #255): the virtual
  /// size is fixed (400x800), so the rect and its conversions are built
  /// once instead of per layer per frame.
  late final Rect _screenRect = Offset.zero & _screenSize.toSize();

  /// The overlay paints, cached as fields (issue #255) and re-tinted by
  /// writing [Paint.color] per frame with the same value the per-frame
  /// constructor used to carry: a property write, never an allocation.
  final Paint _fogPaint = Paint()..style = PaintingStyle.fill;
  final Paint _darkPaint = Paint()..style = PaintingStyle.fill;
  final Paint _glowPaint = Paint()..blendMode = BlendMode.plus;

  @override
  void onLoad() {
    super.onLoad();

    // The viewport has a fixed virtual resolution (400x800); children are
    // laid out in that space regardless of the physical canvas.
    _screenSize = game.camera.viewport.virtualSize.clone();

    _streaks =
        List.generate(rainStreakCount, (_) => _spawnStreak(initial: true));
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (rainIntensity <= 0) return;

    // Rain falls fast and slants back with the taxi's motion: down and
    // to the left, along the shared [rainDrift] slope the painter draws
    // too. Streaks recycle once they have left the glass — off the
    // bottom they exit, or off the left edge the drift carries them
    // onto — so a streak blown off the side frees its slot immediately
    // instead of falling the rest of the way unseen.
    for (var i = 0; i < _streaks.length; i++) {
      final s = _streaks[i];
      s.y += s.speed * dt;
      s.x -= s.speed * rainDrift * dt;
      if (s.y - s.length > _screenSize.y || s.x < -8) {
        _streaks[i] = _spawnStreak();
      }
    }
  }

  _RainStreak _spawnStreak({bool initial = false}) {
    return _RainStreak(
      // The spawn range reaches upwind (right) past the viewport by the
      // drift a streak accrues falling from the top of the spawn band
      // to the bottom of the glass. Without that head start every
      // streak arrives at the lower rows already left of the columns it
      // vacated up top, and the screen's bottom-right goes rainless
      // (issue #209).
      x: 8 +
          _random.nextDouble() *
              (_screenSize.x - 16 + rainDrift * (_screenSize.y + 90)),
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
    // The taxi's screen position is projected once for whichever of fog
    // and darkness is active (issue #255); they used to read it again
    // each. The two layers cannot be merged into one saveLayer: the
    // darkness pass punches its headlight hole with `dstOut`, which in a
    // shared layer would also erase the fog tint beneath it (the two
    // layers' cut ovals overlap around the cab), and its additive glow
    // would add inside the layer instead of onto the composited fog.
    // Keeping two layers keeps the composite byte-for-byte; the paints
    // they paint with are now cached fields.
    final player =
        fogIntensity > 0 || darkness > 0 ? _playerScreenPos() : null;
    if (fogIntensity > 0) _renderFog(canvas, player!);
    if (darkness > 0) _renderDarkness(canvas, player!);
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

  void _renderDarkness(Canvas canvas, Offset player) {
    canvas.saveLayer(_screenRect, _layerPaint);

    // Night tint over everything the viewport shows.
    _darkPaint.color = const Color(0xFF050A18)
        .withValues(alpha: 0.62 * darkness);
    canvas.drawRect(_screenRect, _darkPaint);

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
    _glowPaint.color = const Color(0xFFFFE9B0)
        .withValues(alpha: 0.10 * darkness);
    canvas.drawCircle(
      Offset(player.dx, player.dy - headlightReach * 0.45),
      60,
      _glowPaint,
    );

    canvas.restore();
  }

  /// Erases the tint in a soft ellipse — the headlight's footprint.
  ///
  /// A radial gradient is round by construction: its radius is a fraction
  /// of the rect's *shortest* side, so shading a 220×520 oval directly
  /// still produced a circle of radius 110 — the #142 soft edge quietly
  /// capped the throw at ~250 px ahead, less than two-thirds of the ~403
  /// px the oval spans (issue #147). So the falloff is built once as a
  /// unit circle ([_cutPaint]) and stretched here: translate to the
  /// centre, scale by the oval's radii, and the round shader lands as a
  /// true ellipse that matches the oval it shades — the draw and the
  /// falloff keep the same footprint at every angle. The square ambient
  /// pools pass through the same path unchanged (uniform scale).
  void _cutLight(Canvas canvas, Offset center, Size radius) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(radius.width, radius.height);
    canvas.drawOval(
      const Rect.fromLTWH(-1, -1, 2, 2),
      _cutPaint,
    );
    canvas.restore();
  }

  void _renderFog(Canvas canvas, Offset player) {
    canvas.saveLayer(_screenRect, _layerPaint);
    _fogPaint.color = const Color(0xFFB8BEC6)
        .withValues(alpha: 0.55 * fogIntensity);
    canvas.drawRect(_screenRect, _fogPaint);

    // The air around the cab is clearer — a soft bubble of sight.
    _cutLight(canvas, player, const Size.square(ambientRadius * 1.15));
    _cutLight(
        canvas,
        Offset(player.dx, player.dy - headlightReach * 0.5),
        const Size(120, headlightReach * 0.9));

    canvas.restore();
  }

  /// The streak segments [_renderRain] paints, top end first, in
  /// viewport coordinates. Test seam (issue #209): the draw used to lean
  /// each streak one way (+drift) while the motion drifted the other
  /// (−drift); this exposes exactly the geometry the painter reads so a
  /// test can pin the painted axis to the travel axis.
  @visibleForTesting
  List<(Offset, Offset)> get rainSegments => [
        for (final s in _streaks) (s.topEnd, s.bottomEnd),
      ];

  /// Re-seeds the rain and respawns the whole field from the new
  /// stream, making a test's rain exactly reproducible. A statistical
  /// sweep cannot afford the assertion the coverage test wants: the
  /// upwind corner of the bottom band is crossed only a handful of
  /// times per ten seconds, so an unseeded field leaves a bin dry often
  /// enough to flake (issue #209).
  @visibleForTesting
  void reseedRainForTest(int seed) {
    _random = math.Random(seed);
    _streaks = List.generate(
        rainStreakCount, (_) => _spawnStreak(initial: true));
  }

  void _renderRain(Canvas canvas) {
    for (final s in _streaks) {
      _streakPaint.color =
          const Color(0xFFCFE4FF).withValues(alpha: s.alpha * rainIntensity);
      canvas.drawLine(s.topEnd, s.bottomEnd, _streakPaint);
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

  /// The streak's trailing end — the (x, y) the update moves, one
  /// length above the lead along the slanted axis.
  Offset get topEnd => Offset(x, y - length);

  /// The streak's leading end: down-screen and one length's drift to
  /// the LEFT. That is the same (−[EnvironmentOverlay.rainDrift], +1)
  /// slope the update falls along, so the painted streak leans with
  /// its travel instead of against it (issue #209 had the draw
  /// mirrored, leaning right while drifting left).
  Offset get bottomEnd =>
      Offset(x - length * EnvironmentOverlay.rainDrift, y);
}
