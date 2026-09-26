import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Background component with sky and simple scenery.
///
/// [darkness] (issue #24) is how far into night the run has driven, 0..1 —
/// [TaxiGame] sets it from the run environment every frame. The sky lerps
/// from midday blue to midnight navy and the buildings dim with it, so the
/// arc of a long shift is legible in the skyline alone: distance you can
/// see, not just a counter.
class Background extends PositionComponent {
  /// 0..1 — 0 is midday, 1 is the depth of night.
  double darkness = 0;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    size = Vector2(400, 800);
    position = Vector2.zero();
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    // Draw sky gradient — daylight blue sinking into night navy.
    final topColor = Color.lerp(
        const Color(0xFF87CEEB), const Color(0xFF0A1030), darkness)!;
    final bottomColor = Color.lerp(
        const Color(0xFFE0F6FF), const Color(0xFF1A2340), darkness)!;
    final skyGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [topColor, bottomColor],
    );

    final paint = Paint()
      ..shader = skyGradient.createShader(
        Rect.fromLTWH(0, 0, size.x, size.y),
      );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      paint,
    );

    // Stars fade in with the dark.
    if (darkness > 0.35) {
      final starAlpha = ((darkness - 0.35) / 0.65).clamp(0.0, 1.0);
      final starPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.8 * starAlpha);
      for (var i = 0; i < 24; i++) {
        // Fixed pseudo-random star field, so the sky never flickers.
        final x = (i * 97.0) % size.x;
        final y = ((i * 53.0) % 380.0);
        final twinkle = 1.4 + ((i * 31) % 10) / 8.0;
        canvas.drawCircle(Offset(x, y), twinkle / 2, starPaint);
      }
    }

    // Draw simple buildings on sides (placeholders); windows light up as
    // the day dies.
    _drawBuildings(canvas);
  }

  void _drawBuildings(Canvas canvas) {
    final buildingColor = Color.lerp(
        Colors.grey.shade700, const Color(0xFF14182A), darkness);
    final buildingPaint = Paint()
      ..color = buildingColor!
      ..style = PaintingStyle.fill;

    final windowPaint = Paint()
      ..color = Colors.amber
          .withValues(alpha: 0.55 * darkness.clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;

    // Left side buildings
    for (var i = 0; i < 5; i++) {
      canvas.drawRect(
        Rect.fromLTWH(10, i * 180.0, 60, 150),
        buildingPaint,
      );
      _drawWindows(canvas, Rect.fromLTWH(10, i * 180.0, 60, 150), i,
          windowPaint);
    }

    // Right side buildings
    for (var i = 0; i < 5; i++) {
      canvas.drawRect(
        Rect.fromLTWH(size.x - 70, i * 180.0, 60, 150),
        buildingPaint,
      );
      _drawWindows(
          canvas, Rect.fromLTWH(size.x - 70, i * 180.0, 60, 150), i + 5,
          windowPaint);
    }
  }

  void _drawWindows(Canvas canvas, Rect building, int seed,
      Paint windowPaint) {
    for (var wy = building.top + 14;
        wy < building.bottom - 10;
        wy += 22) {
      for (var wx = building.left + 10;
          wx < building.right - 10;
          wx += 18) {
        // A fixed pattern of lit windows per building.
        if ((wx.toInt() * 7 + wy.toInt() * 13 + seed * 29) % 5 < 2) {
          canvas.drawRect(Rect.fromLTWH(wx, wy, 6, 8), windowPaint);
        }
      }
    }
  }
}
