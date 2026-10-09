import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Background component with sky and simple scenery.
///
/// [darkness] (issue #24) is how far into night the run has driven, 0..1 —
/// [TaxiGame] sets it from the run environment every frame. The sky lerps
/// from midday blue to midnight navy and the buildings dim with it, so the
/// arc of a long shift is legible in the skyline alone: distance you can
/// see, not just a counter.
///
/// Everything the component paints is cached (issue #251). The sky's
/// gradient shader is a native object and the stars, buildings, and lit
/// windows are fixed geometry; all of it is a pure function of the one
/// input, [darkness]. So the paints are rebuilt only once [darkness] has
/// moved past [_rebuildEpsilon], and the geometry is laid out once in
/// [onLoad]. While the day holds (darkness pinned at 0 — all of level
/// mode, and any parked cab) a frame now allocates nothing at all.
class Background extends PositionComponent {
  /// 0..1 — 0 is midday, 1 is the depth of night.
  double darkness = 0;

  /// How far [darkness] must move before the cached paints are rebuilt.
  ///
  /// At 1/1000 the largest per-channel drift across every lerp below is
  /// a fraction of one 8-bit level, so a frame that reuses the cache is
  /// visually indistinguishable from one that rebuilt it; the win is
  /// that stretches where darkness sits still (or crawls) rebuild
  /// nothing.
  static const double _rebuildEpsilon = 1e-3;

  /// The darkness the cached paints were built from; NaN before the
  /// first build, so the first [render] always paints.
  double _shadedDarkness = double.nan;

  final Paint _skyPaint = Paint();
  final Paint _starPaint = Paint();
  final Paint _buildingPaint = Paint()..style = PaintingStyle.fill;
  final Paint _windowPaint = Paint()..style = PaintingStyle.fill;

  /// The fixed pseudo-random star field (issue #251): centre and radius,
  /// `(i * 97) % width`, `(i * 53) % 380`, and the old twinkle
  /// `1.4 + ((i * 31) % 10) / 8` halved. Precomputed so the sky never
  /// flickers and the frame loop allocates no `Offset`s.
  late final List<(Offset, double)> _stars;

  /// The buildings and their lit windows, in paint order (left side top
  /// to bottom, then right side).
  late final List<({Rect body, List<Rect> windows})> _buildings;

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
    _buildings = [
      for (var i = 0; i < 5; i++)
        _building(Rect.fromLTWH(10, i * 180.0, 60, 150), i),
      for (var i = 0; i < 5; i++)
        _building(Rect.fromLTWH(size.x - 70, i * 180.0, 60, 150), i + 5),
    ];
  }

  /// One building and its fixed pattern of lit windows, in the exact
  /// order the old per-frame scan visited them.
  ({Rect body, List<Rect> windows}) _building(Rect body, int seed) {
    final windows = <Rect>[];
    for (var wy = body.top + 14; wy < body.bottom - 10; wy += 22) {
      for (var wx = body.left + 10; wx < body.right - 10; wx += 18) {
        // A fixed pattern of lit windows per building.
        if ((wx.toInt() * 7 + wy.toInt() * 13 + seed * 29) % 5 < 2) {
          windows.add(Rect.fromLTWH(wx, wy, 6, 8));
        }
      }
    }
    return (body: body, windows: windows);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    _syncPaints();

    // Draw sky gradient — daylight blue sinking into night navy.
    canvas.drawRect(_skyRect, _skyPaint);

    // Stars fade in with the dark.
    if (darkness > 0.35) {
      for (final (centre, radius) in _stars) {
        canvas.drawCircle(centre, radius, _starPaint);
      }
    }

    // Draw simple buildings on sides (placeholders); windows light up as
    // the day dies.
    for (final building in _buildings) {
      canvas.drawRect(building.body, _buildingPaint);
      for (final window in building.windows) {
        canvas.drawRect(window, _windowPaint);
      }
    }
  }

  /// Rebuilds the cached paints when [darkness] has moved enough to
  /// matter (issue #251). Every colour below is byte-for-byte what the
  /// old per-frame renderer computed at the same darkness; only the
  /// moment of computation moved.
  void _syncPaints() {
    if ((darkness - _shadedDarkness).abs() <= _rebuildEpsilon) return;
    _shadedDarkness = darkness;

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

    _buildingPaint.color = Color.lerp(
        Colors.grey.shade700, const Color(0xFF14182A), darkness)!;
    _windowPaint.color =
        Colors.amber.withValues(alpha: 0.55 * darkness.clamp(0.0, 1.0));
  }
}
