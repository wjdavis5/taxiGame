import 'dart:math' as math;
import 'dart:ui';

import '../../models/fare_type.dart';

/// The glyph a fare kind wears on its street markers (issue #35).
///
/// The markers used to distinguish the four kinds by hue alone — which
/// ~8% of male players cannot reliably separate — so every kind now also
/// owns a distinct *shape*, legible in greyscale:
///
/// - [FareType.standard] — a ring: the plain, everyday mark.
/// - [FareType.vip]      — a crown inside a ring (the crown the marker
///                         always wore, now framed so the ring reads as
///                         something extra).
/// - [FareType.longHaul] — a double chevron, pointing up the road.
/// - [FareType.awkward]  — crossed arrows: the far-side crossing.
///
/// Colour stays as the secondary emphasis; the glyph is what sorts the
/// kinds when colour cannot. Pure geometry — no assets, no Flame state —
/// so [fareGlyphPath] is unit-testable and rendered pixels can be probed
/// directly, the way `endless_road_alignment_test` probes the road.
enum FareGlyph { circle, crownRing, chevronsUp, crossedArrows }

/// The glyph that marks [type] on the street (issue #35).
FareGlyph glyphForFare(FareType type) => switch (type) {
      FareType.standard => FareGlyph.circle,
      FareType.vip => FareGlyph.crownRing,
      FareType.longHaul => FareGlyph.chevronsUp,
      FareType.awkward => FareGlyph.crossedArrows,
    };

/// Nominal glyph size: the path fits inside a circle of this radius, well
/// inside a marker's pulsing body (radius 25-35).
const double fareGlyphRadius = 14;

/// Builds [type]'s glyph as one [Path] centred on the canvas origin,
/// scaled to fit [radius].
///
/// Pure: the same call always returns the same shape, so the pickup and
/// dropoff markers cannot drift apart and tests can compare silhouettes
/// without rendering anything.
Path fareGlyphPath(FareType type, {double radius = fareGlyphRadius}) {
  final s = radius / fareGlyphRadius;
  final path = Path();
  switch (glyphForFare(type)) {
    case FareGlyph.circle:
      // A hollow ring — even-odd fill punches the hole.
      path
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: 13 * s))
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: 7.5 * s));
    case FareGlyph.crownRing:
      // The crown inside a framing ring; the crown stays strictly inside
      // the ring's hole so the even-odd fill reads ring, gap, crown.
      path
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: 13.5 * s))
        ..addOval(Rect.fromCircle(center: Offset.zero, radius: 10 * s))
        ..addPath(_crownPath(s), Offset.zero);
    case FareGlyph.chevronsUp:
      // Two stacked chevrons pointing up the road.
      path
        ..fillType = PathFillType.nonZero
        ..addPath(_chevronBand(-10 * s, s), Offset.zero)
        ..addPath(_chevronBand(-1 * s, s), Offset.zero);
    case FareGlyph.crossedArrows:
      // Two double-headed arrows crossing over the four-lane street.
      path
        ..fillType = PathFillType.nonZero
        ..addPath(_doubleArrow(-math.pi / 4, s), Offset.zero)
        ..addPath(_doubleArrow(-3 * math.pi / 4, s), Offset.zero);
  }
  return path;
}

/// Paints [type]'s glyph centred on the canvas origin.
///
/// [ink] fills or strokes the shape; the optional [rim] draws first, so a
/// solid glyph can carry a contrasting edge and hold against any marker
/// fill once colour is gone. The pickup paints the solid weight, the
/// dropoff the stroked one — same path, lower weight (issue #35).
void paintFareGlyph(
  Canvas canvas,
  FareType type, {
  double radius = fareGlyphRadius,
  required Paint ink,
  Paint? rim,
}) {
  final path = fareGlyphPath(type, radius: radius);
  if (rim != null) canvas.drawPath(path, rim);
  canvas.drawPath(path, ink);
}

/// The VIP's crown — the marker's original crown icon, scaled and
/// re-centred on the origin so it sits inside the framing ring.
Path _crownPath(double s) {
  const points = [
    Offset(-8, -9),
    Offset(-8, -19),
    Offset(-4, -14),
    Offset(0, -21),
    Offset(4, -14),
    Offset(8, -19),
    Offset(8, -9),
  ];
  final path = Path();
  var first = true;
  for (final p in points) {
    // Scale 0.8 keeps the crown inside the ring's hole; +12 re-centres
    // the crown's bounding box on the origin.
    final o = Offset(p.dx * 0.8 * s, p.dy * 0.8 * s + 12 * s);
    if (first) {
      path.moveTo(o.dx, o.dy);
      first = false;
    } else {
      path.lineTo(o.dx, o.dy);
    }
  }
  return path..close();
}

/// One up-pointing chevron band whose outer apex sits at [apexY].
Path _chevronBand(double apexY, double s) {
  return Path()
    ..moveTo(-11 * s, apexY + 7 * s)
    ..lineTo(0, apexY)
    ..lineTo(11 * s, apexY + 7 * s)
    ..lineTo(11 * s, apexY + 11 * s)
    ..lineTo(0, apexY + 4 * s)
    ..lineTo(-11 * s, apexY + 11 * s)
    ..close();
}

/// A double-headed arrow along [angle] (its tips reach [radius] from the
/// origin); two of these, a quarter turn apart, cross into an X.
Path _doubleArrow(double angle, double s) {
  const points = [
    Offset(-14, 0), // tail tip
    Offset(-7.5, -5.5), // tail barb
    Offset(-7.5, -2.2), // shaft top at tail
    Offset(7.5, -2.2), // shaft top at head
    Offset(7.5, -5.5), // head barb
    Offset(14, 0), // head tip
    Offset(7.5, 5.5), // head barb
    Offset(7.5, 2.2), // shaft bottom at head
    Offset(-7.5, 2.2), // shaft bottom at tail
    Offset(-7.5, 5.5), // tail barb
  ];
  final cos = math.cos(angle);
  final sin = math.sin(angle);

  Offset rotate(Offset p) =>
      Offset(p.dx * cos - p.dy * sin, p.dx * sin + p.dy * cos) * s;

  final path = Path()..moveTo(rotate(points.first).dx, rotate(points.first).dy);
  for (final p in points.skip(1)) {
    final o = rotate(p);
    path.lineTo(o.dx, o.dy);
  }
  return path..close();
}
