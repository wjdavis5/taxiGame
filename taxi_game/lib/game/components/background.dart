import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../systems/run_environment.dart';
import 'district_palette.dart';

/// Background component with sky and simple scenery.
///
/// [darkness] (issue #24) is how far into night the run has driven, 0..1 —
/// [TaxiGame] sets it from the run environment every frame. The sky lerps
/// from midday blue to midnight navy and the buildings dim with it, so the
/// arc of a long shift is legible in the skyline alone: distance you can
/// see, not just a counter.
///
/// [profile] (issue #280) is the district the taxi is in. Each profile
/// builds its own skyline silhouette, raises its own landmark over it, and
/// paints with its own [DistrictPalette] colours — a low brick roofline
/// with a clock tower, a field of setback towers around a monument, or
/// Midtown's blocks with the rooftop water tower. The district changes
/// with the road's own segment roll, so the skyline is seed-exact with no
/// draw of its own.
///
/// Everything the component paints is cached (issue #251). The sky's
/// gradient shader is a native object and the stars, buildings, and lit
/// windows are fixed geometry; all of it is a pure function of the two
/// inputs, [darkness] and [profile]. So the paints are rebuilt whenever
/// either changes at all, byte-identical to the old per-frame recompute,
/// the skyline is rebuilt only when [profile] changes, and the geometry is
/// laid out once in [onLoad]. While the day holds (darkness pinned at 0,
/// which covers all of level mode and any parked cab) and the district
/// holds, a frame allocates nothing at all.
class Background extends PositionComponent {
  /// 0..1 — 0 is midday, 1 is the depth of night.
  double darkness = 0;

  /// The district whose skyline, landmark, and colours paint (issue #280).
  /// Standard — the classic Midtown look — until a run says otherwise.
  RoadProfile profile = RoadProfile.standard;

  /// The shading inputs the cached paints and skyline were built from;
  /// null before the first build, so the first [render] always paints.
  double _shadedDarkness = double.nan;
  RoadProfile? _shadedProfile;

  final Paint _skyPaint = Paint();
  final Paint _starPaint = Paint();
  final Paint _buildingPaint = Paint()..style = PaintingStyle.fill;
  final Paint _landmarkPaint = Paint()..style = PaintingStyle.fill;
  final Paint _windowPaint = Paint()..style = PaintingStyle.fill;

  /// The fixed pseudo-random star field (issue #251): centre and radius,
  /// `(i * 97) % width`, `(i * 53) % 380`, and the old twinkle
  /// `1.4 + ((i * 31) % 10) / 8` halved. Precomputed so the sky never
  /// flickers and the frame loop allocates no `Offset`s.
  late final List<(Offset, double)> _stars;

  /// The district's skyline bodies and their lit windows, in paint order
  /// (left side top to bottom, then right side).
  late List<({Path shape, List<Rect> windows})> _buildings;

  /// The district's landmark over the roofline: the filled shape, plus an
  /// optionally lit detail (the clock tower's face) painted with the
  /// window colour.
  late List<({Path shape, Path? lit})> _landmarks;

  /// The sky card the gradient shader is built over, once per rebuild.
  late final Rect _skyRect = Rect.fromLTWH(0, 0, size.x, size.y);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    size = Vector2(400, 800);
    position = Vector2.zero();

    _stars = [
      for (var i = 0; i < 24; i++)
        (
          Offset((i * 97.0) % size.x, (i * 53.0) % 380.0),
          (1.4 + ((i * 31) % 10) / 8.0) / 2,
        ),
    ];
    _buildSkyline();
  }

  /// Bounds of every skyline body — the silhouette a district paints,
  /// exposed so a test can tell the districts apart without pixels.
  @visibleForTesting
  List<Rect> get skylineBounds => [
        for (final building in _buildings) building.shape.getBounds(),
      ];

  /// Bounds of every landmark shape, the same way.
  @visibleForTesting
  List<Rect> get landmarkBounds => [
        for (final landmark in _landmarks) landmark.shape.getBounds(),
      ];

  /// Builds the skyline for the current [profile]. Called once from
  /// [onLoad] and again only when the district changes.
  void _buildSkyline() {
    switch (profile) {
      case RoadProfile.standard:
        _buildings = [
          for (var i = 0; i < 5; i++)
            _block(Rect.fromLTWH(10, i * 180.0, 60, 150), i),
          for (var i = 0; i < 5; i++)
            _block(Rect.fromLTWH(size.x - 70, i * 180.0, 60, 150), i + 5),
        ];
        _landmarks = [_waterTower()];
      case RoadProfile.narrow:
        const w = 56.0, h = 84.0, pitch = 112.0, top = 36.0;
        _buildings = [
          for (var i = 0; i < 7; i++)
            _gabledRowhouse(Rect.fromLTWH(6, top + i * pitch, w, h), i),
          for (var i = 0; i < 7; i++)
            _gabledRowhouse(
                Rect.fromLTWH(size.x - 62, top + i * pitch, w, h), i + 7),
        ];
        _landmarks = [_clockTower()];
      case RoadProfile.avenue:
        const w = 64.0, h = 170.0, pitch = 180.0, top = 64.0;
        _buildings = [
          for (var i = 0; i < 4; i++)
            _setbackTower(Rect.fromLTWH(12, top + i * pitch, w, h), i),
          for (var i = 0; i < 4; i++)
            _setbackTower(
                Rect.fromLTWH(size.x - 76, top + i * pitch, w, h), i + 4),
        ];
        _landmarks = [_obelisk()];
    }
  }

  /// One block of Midtown, and its fixed pattern of lit windows — the
  /// exact body, window scan, and order the pre-#280 background painted.
  ({Path shape, List<Rect> windows}) _block(Rect body, int seed) =>
      (shape: Path()..addRect(body), windows: _windows(body, seed));

  /// One low old-town rowhouse: the body, a pitched roof, and a chimney.
  ({Path shape, List<Rect> windows}) _gabledRowhouse(Rect body, int seed) {
    final roof = Path()
      ..moveTo(body.left - 2, body.top)
      ..lineTo(body.center.dx, body.top - 26)
      ..lineTo(body.right + 2, body.top)
      ..close();
    final chimney =
        Path()..addRect(Rect.fromLTWH(body.center.dx - 14, body.top - 22, 6, 12));
    return (
      shape: Path()
        ..addRect(body)
        ..addPath(roof, Offset.zero)
        ..addPath(chimney, Offset.zero),
      windows: _windows(body, seed),
    );
  }

  /// One avenue tower: a wide base with a narrower setback block on top —
  /// the stepped skyline a boulevard is drawn with.
  ({Path shape, List<Rect> windows}) _setbackTower(Rect body, int seed) {
    final upper =
        Rect.fromLTWH(body.center.dx - 20, body.top - 56, 40, 56);
    return (
      shape: Path()
        ..addRect(body)
        ..addPath(Path()..addRect(upper), Offset.zero),
      windows: [..._windows(body, seed), ..._windows(upper, seed + 20)],
    );
  }

  /// Midtown's rooftop water tower, standing on the third left block.
  ({Path shape, Path? lit}) _waterTower() {
    const x = 22.0, roofY = 360.0;
    return (
      shape: Path()
        ..addRect(const Rect.fromLTWH(x + 6, roofY - 6, 3, 6))
        ..addRect(const Rect.fromLTWH(x + 29, roofY - 6, 3, 6))
        ..addRect(const Rect.fromLTWH(x, roofY - 30, 38, 24))
        ..addPath(
            Path()
              ..moveTo(x, roofY - 30)
              ..lineTo(x + 19, roofY - 42)
              ..lineTo(x + 38, roofY - 30)
              ..close(),
            Offset.zero),
      lit: null,
    );
  }

  /// Old Town's clock tower: a stone shaft with a stepped crown and a
  /// spire, the face lit like a window once the day dies.
  ({Path shape, Path? lit}) _clockTower() {
    return (
      shape: Path()
        ..addRect(const Rect.fromLTWH(18, 250, 30, 240))
        ..addRect(const Rect.fromLTWH(23, 232, 20, 18))
        ..addPath(
            Path()
              ..moveTo(21, 232)
              ..lineTo(33, 210)
              ..lineTo(45, 232)
              ..close(),
            Offset.zero),
      lit: Path()
        ..addOval(Rect.fromCircle(center: const Offset(33, 270), radius: 9)),
    );
  }

  /// Grand Avenue's monument: a plinth, a pedestal, and a tapered shaft
  /// with a pyramidion.
  ({Path shape, Path? lit}) _obelisk() {
    return (
      shape: Path()
        ..addRect(const Rect.fromLTWH(336, 486, 48, 14))
        ..addRect(const Rect.fromLTWH(344, 462, 32, 24))
        ..addPath(
            Path()
              ..moveTo(348, 462)
              ..lineTo(372, 462)
              ..lineTo(363, 340)
              ..lineTo(357, 340)
              ..close(),
            Offset.zero)
        ..addPath(
            Path()
              ..moveTo(355, 342)
              ..lineTo(360, 320)
              ..lineTo(365, 342)
              ..close(),
            Offset.zero),
      lit: null,
    );
  }

  /// The fixed pattern of lit windows for [body], in the exact order the
  /// old per-frame scan visited them.
  List<Rect> _windows(Rect body, int seed) {
    final windows = <Rect>[];
    for (var wy = body.top + 14; wy < body.bottom - 10; wy += 22) {
      for (var wx = body.left + 10; wx < body.right - 10; wx += 18) {
        // A fixed pattern of lit windows per building.
        if ((wx.toInt() * 7 + wy.toInt() * 13 + seed * 29) % 5 < 2) {
          windows.add(Rect.fromLTWH(wx, wy, 6, 8));
        }
      }
    }
    return windows;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    _syncCaches();

    // Draw sky gradient — daylight blue sinking into night navy.
    canvas.drawRect(_skyRect, _skyPaint);

    // Stars fade in with the dark.
    if (darkness > 0.35) {
      for (final (centre, radius) in _stars) {
        canvas.drawCircle(centre, radius, _starPaint);
      }
    }

    // The district's skyline and its landmark; windows light up as the
    // day dies.
    for (final building in _buildings) {
      canvas.drawPath(building.shape, _buildingPaint);
    }
    for (final landmark in _landmarks) {
      canvas.drawPath(landmark.shape, _landmarkPaint);
    }
    for (final building in _buildings) {
      for (final window in building.windows) {
        canvas.drawRect(window, _windowPaint);
      }
    }
    for (final landmark in _landmarks) {
      final lit = landmark.lit;
      if (lit != null) canvas.drawPath(lit, _windowPaint);
    }
  }

  /// Rebuilds the skyline and the cached paints whenever [profile] or
  /// [darkness] changes (issues #251, #280). Every colour below is
  /// byte-for-byte what the old per-frame renderer computed at the same
  /// darkness for the standard district; only the moment of computation
  /// moved. Any epsilon here would reuse a paint from a different
  /// darkness, so the guard is exact equality.
  void _syncCaches() {
    if (darkness == _shadedDarkness && profile == _shadedProfile) return;

    if (profile != _shadedProfile) _buildSkyline();
    _shadedDarkness = darkness;
    _shadedProfile = profile;

    final topColor = Color.lerp(
        const Color(0xFF87CEEB), const Color(0xFF0A1030), darkness)!;
    final bottomColor = Color.lerp(
        const Color(0xFFE0F6FF), const Color(0xFF1A2340), darkness)!;
    final skyGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [topColor, bottomColor],
    );
    _skyPaint.shader = skyGradient.createShader(_skyRect);

    final starAlpha = ((darkness - 0.35) / 0.65).clamp(0.0, 1.0);
    _starPaint.color = Colors.white.withValues(alpha: 0.8 * starAlpha);

    final palette = DistrictPalette.of(profile);
    _buildingPaint.color =
        Color.lerp(palette.building, const Color(0xFF14182A), darkness)!;
    _landmarkPaint.color =
        Color.lerp(palette.landmark, const Color(0xFF14182A), darkness)!;
    _windowPaint.color =
        Colors.amber.withValues(alpha: 0.55 * darkness.clamp(0.0, 1.0));
  }
}
