import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../systems/run_environment.dart';
import '../systems/world_origin.dart';

/// Road segment component that renders the road.
///
/// In level mode (no [environment]) this is the classic fixed street: 200
/// px wide, two lanes, one dashed centre line. In an endless run the
/// segment is one recycled chunk (issue #11) of the *living* road
/// (issue #24): it samples the run's [RunEnvironment] along its length and
/// draws the width the road really has there — tapers, lane counts, cross
/// streets, and the wet sheen of passing rain.
class RoadSegment extends PositionComponent {
  final double length;
  final int lanes;

  /// The run's living world. Null renders the fixed level road.
  final RunEnvironment? environment;

  /// True distance into the run at this chunk's top edge (local y 0),
  /// pinned at construction. World y folds back toward the origin as the
  /// run deepens (issue #30), so sampling by raw `-position.y` would lose
  /// a whole [WorldOrigin.period] at every fold; the pinned distance
  /// cannot drift. Null in level mode, where the road is finite and the
  /// classic reading still holds.
  final double? _topDistance;

  /// The true distance at local y 0: the pinned value for an endless
  /// chunk, the classic world reading for a level's single segment.
  double get distanceAtTop => _topDistance ?? -position.y;

  /// How far apart (px) the geometry is sampled down the chunk. Small
  /// enough that tapers render smoothly, large enough that three live
  /// chunks stay cheap.
  static const double _rowStep = 40.0;

  RoadSegment({
    required Vector2 position,
    required this.length,
    this.lanes = 2,
    this.environment,
    double? topDistance,
  })  : _topDistance = topDistance,
        super(position: position);

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    size = Vector2(200, length);
    anchor = Anchor.topCenter;
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    if (environment != null) {
      _renderEnvironmentRoad(canvas);
    } else {
      _renderFixedRoad(canvas);
    }
  }

  // --- The classic fixed street (level mode) ------------------------------

  void _renderFixedRoad(Canvas canvas) {
    // Draw sidewalks on both sides (where passengers wait)
    final sidewalkPaint = Paint()
      ..color = const Color(0xFFBDBDBD)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(-30, 0, 30, size.y), sidewalkPaint);
    canvas.drawRect(Rect.fromLTWH(size.x, 0, 30, size.y), sidewalkPaint);

    // Draw road surface (dark gray)
    final roadPaint = Paint()
      ..color = const Color(0xFF404040)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      roadPaint,
    );

    // Draw lane markings (white dashed lines)
    final laneMarkingPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Center line
    _drawDashedLine(
      canvas,
      Offset(size.x / 2, 0),
      Offset(size.x / 2, size.y),
      laneMarkingPaint,
      dashLength: 20,
      gapLength: 15,
    );

    // Draw road edges
    final edgePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      const Offset(0, 0),
      Offset(0, size.y),
      edgePaint,
    );

    canvas.drawLine(
      Offset(size.x, 0),
      Offset(size.x, size.y),
      edgePaint,
    );
  }

  // --- The living street (endless mode, issue #24) ------------------------

  void _renderEnvironmentRoad(Canvas canvas) {
    final env = environment!;
    // Chunk-local x of the road's centre line: the chunk's own origin is
    // the centre line's top end.
    const centerX = RunEnvironment.roadCenterX;

    // Sample the geometry down the chunk so tapers follow the road.
    final rows = <_RoadRow>[];
    for (var y = 0.0; y < length; y += _rowStep) {
      rows.add(_rowFor(env, centerX, y));
    }
    rows.add(_rowFor(env, centerX, length));

    _drawSidewalks(canvas, rows, env);
    _drawSurface(canvas, rows, env);
    _drawLaneBoundaries(canvas, rows);
    _drawEdges(canvas, rows);
    _drawIntersections(canvas, env, centerX);
  }

  _RoadRow _rowFor(RunEnvironment env, double centerX, double localY) {
    // Local y runs positive down the chunk from its top edge, so the
    // distance at a row is the pinned top distance minus the run down.
    final distance = distanceAtTop - localY;
    final road = env.roadAt(distance);
    return _RoadRow(
      localY: localY,
      leftLocalX: road.leftX - centerX,
      width: road.width,
      laneCount: road.laneCount,
    );
  }

  void _drawSidewalks(Canvas canvas, List<_RoadRow> rows, RunEnvironment env) {
    final distance = distanceAtTop - length / 2;
    final rain = env.rainIntensityAt(distance);
    var color = const Color(0xFFBDBDBD);
    if (rain > 0) {
      color = Color.lerp(color, const Color(0xFF6E7A86), rain * 0.5)!;
    }
    final sidewalkPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final left = Path()..fillType = PathFillType.nonZero;
    final right = Path()..fillType = PathFillType.nonZero;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final x = row.leftLocalX - 30;
      final top = i == 0;
      if (top) {
        left.moveTo(x, row.localY);
        right.moveTo(row.leftLocalX + row.width, row.localY);
      }
      left.lineTo(x, row.localY);
      right.lineTo(row.leftLocalX + row.width, row.localY);
    }
    for (var i = rows.length - 1; i >= 0; i--) {
      final row = rows[i];
      left.lineTo(row.leftLocalX, row.localY);
      right.lineTo(row.leftLocalX + row.width + 30, row.localY);
    }
    left.close();
    right.close();
    canvas.drawPath(left, sidewalkPaint);
    canvas.drawPath(right, sidewalkPaint);
  }

  void _drawSurface(Canvas canvas, List<_RoadRow> rows, RunEnvironment env) {
    final roadPath = Path();
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (i == 0) roadPath.moveTo(row.leftLocalX, row.localY);
      roadPath.lineTo(row.leftLocalX, row.localY);
    }
    for (var i = rows.length - 1; i >= 0; i--) {
      final row = rows[i];
      roadPath.lineTo(row.leftLocalX + row.width, row.localY);
    }
    roadPath.close();

    final roadPaint = Paint()
      ..color = const Color(0xFF404040)
      ..style = PaintingStyle.fill;
    canvas.drawPath(roadPath, roadPaint);

    // A wet street reads darker and cooler while the rain lasts (issue
    // #24): the same cue that tells the player their grip is gone.
    final mid = distanceAtTop - length / 2;
    final rain = env.rainIntensityAt(mid);
    if (rain > 0) {
      canvas.drawPath(
        roadPath,
        Paint()
          ..color = const Color(0xFF2A3440).withValues(alpha: 0.45 * rain)
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawLaneBoundaries(Canvas canvas, List<_RoadRow> rows) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // One boundary between each pair of adjacent lanes, at k/n across the
    // road. Dashes run with the road: 20 on, 15 off, measured in local y.
    final maxLanes = rows.map((r) => r.laneCount).reduce(math.max);
    for (var lane = 1; lane < maxLanes; lane++) {
      for (var y = 0.0; y < length; y += 35) {
        final dashEnd = math.min(y + 20, length);
        final a = _rowAt(rows, y);
        final b = _rowAt(rows, dashEnd);
        if (a.laneCount <= lane || b.laneCount <= lane) continue;
        canvas.drawLine(
          Offset(a.leftLocalX + a.width * lane / a.laneCount, y),
          Offset(b.leftLocalX + b.width * lane / b.laneCount, dashEnd),
          paint,
        );
      }
    }
  }

  void _drawEdges(Canvas canvas, List<_RoadRow> rows) {
    final edgePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final left = Path();
    final right = Path();
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (i == 0) {
        left.moveTo(row.leftLocalX, row.localY);
        right.moveTo(row.leftLocalX + row.width, row.localY);
      }
      left.lineTo(row.leftLocalX, row.localY);
      right.lineTo(row.leftLocalX + row.width, row.localY);
    }
    canvas.drawPath(left, edgePaint);
    canvas.drawPath(right, edgePaint);
  }

  void _drawIntersections(Canvas canvas, RunEnvironment env,
      double centerX) {
    // The chunk covers true distances [distanceAtTop − length,
    // distanceAtTop] — the pinned reading survives every world fold
    // (issue #30), where raw −position.y would lose a fold per boundary.
    final from = distanceAtTop - length;
    final to = distanceAtTop;
    final asphalt = Paint()
      ..color = const Color(0xFF4A4A4A)
      ..style = PaintingStyle.fill;

    final firstBand = (from / RunEnvironment.intersectionSpacing).floor();
    final lastBand = (to / RunEnvironment.intersectionSpacing).floor();
    for (var k = firstBand; k <= lastBand; k++) {
      final centerDistance = k * RunEnvironment.intersectionSpacing;
      if (centerDistance < RunEnvironment.intersectionSpacing) {
        continue; // the calm open has no junctions
      }
      if (centerDistance < from - RunEnvironment.intersectionHalfBand ||
          centerDistance > to + RunEnvironment.intersectionHalfBand) {
        continue;
      }

      // Cross street: a carriageway band spanning the whole view. Its
      // edges convert from true distance through [WorldOrigin], so the
      // band lands in the chunk's own frame whatever fold it sits past.
      final bandTopLocal = WorldOrigin.worldYForDistance(
              centerDistance + RunEnvironment.intersectionHalfBand) -
          position.y;
      final bandBottomLocal = WorldOrigin.worldYForDistance(
              centerDistance - RunEnvironment.intersectionHalfBand) -
          position.y;
      canvas.drawRect(
        Rect.fromLTRB(-centerX, bandTopLocal, centerX, bandBottomLocal),
        asphalt,
      );

      // Zebra crossings on both approaches, outside the band: a stack of
      // bars spanning the road's width where they meet it.
      final road = env.roadAt(centerDistance);
      _drawCrosswalk(canvas, road, centerX, bandBottomLocal + 10);
      _drawCrosswalk(canvas, road, centerX, bandTopLocal - 10);
    }
  }

  /// A zebra crossing stacked upward from [localY]: three horizontal bars
  /// spanning the road — the way a crossing reads from a driver's
  /// top-down view.
  void _drawCrosswalk(
      Canvas canvas, RoadGeometry road, double centerX, double localY) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    const barHeight = 6.0;
    const barGap = 5.0;
    final leftLocalX = road.leftX - centerX;
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(
        Rect.fromLTWH(
            leftLocalX + 4, localY - i * (barHeight + barGap), road.width - 8,
            barHeight),
        paint,
      );
    }
  }

  _RoadRow _rowAt(List<_RoadRow> rows, double localY) {
    for (var i = 1; i < rows.length; i++) {
      if (rows[i].localY >= localY) return rows[i - 1];
    }
    return rows.last;
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    double dashLength = 10,
    double gapLength = 5,
  }) {
    final distance = (end - start).distance;
    final dashCount = (distance / (dashLength + gapLength)).floor();

    final dx = (end.dx - start.dx) / distance;
    final dy = (end.dy - start.dy) / distance;

    for (var i = 0; i < dashCount; i++) {
      final dashStart = Offset(
        start.dx + dx * i * (dashLength + gapLength),
        start.dy + dy * i * (dashLength + gapLength),
      );

      final dashEnd = Offset(
        dashStart.dx + dx * dashLength,
        dashStart.dy + dy * dashLength,
      );

      canvas.drawLine(dashStart, dashEnd, paint);
    }
  }
}

/// One sampled slice of the chunk's road geometry.
class _RoadRow {
  const _RoadRow({
    required this.localY,
    required this.leftLocalX,
    required this.width,
    required this.laneCount,
  });

  final double localY;
  final double leftLocalX;
  final double width;
  final int laneCount;
}
