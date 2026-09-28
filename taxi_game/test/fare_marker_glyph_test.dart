import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/components/fare_glyph.dart';
import 'package:taxi_game/game/components/pickup_zone.dart';
import 'package:taxi_game/models/fare_type.dart';
import 'package:taxi_game/models/passenger_data.dart';

/// The fare-kind markers must sort in greyscale (issue #35).
///
/// The four kinds used to be told apart by hue alone — green, amber,
/// purple, orange — and ~8% of male players cannot reliably separate
/// those. Every kind now owns a distinct glyph on its markers: a ring for
/// the standard ride, a crown in a ring for the VIP, a double chevron up
/// for the long-haul, crossed arrows for the awkward far-side crossing.
/// Colour stays as secondary emphasis; the shape is what carries the kind.
///
/// The acceptance bar is **greyscale similarity**: after collapsing every
/// render to luma, each pair of kinds must still disagree over a
/// substantial area. The probes below render each glyph on identical grey
/// marker discs — the same weight the pickup (solid over a dark rim) and
/// the dropoff (stroked) draw with — so any difference between two
/// renders is glyph geometry alone, with no colour information left to
/// lean on. A final probe renders the real [PickupZone] with its true
/// kind colours and compares in luma, which is literally what an
/// achromatopic player sees.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the pure glyph geometry', () {
    test('every fare kind owns its own glyph', () {
      expect(glyphForFare(FareType.standard), FareGlyph.circle);
      expect(glyphForFare(FareType.vip), FareGlyph.crownRing);
      expect(glyphForFare(FareType.longHaul), FareGlyph.chevronsUp);
      expect(glyphForFare(FareType.awkward), FareGlyph.crossedArrows);
      expect(
        {for (final type in FareType.values) glyphForFare(type)},
        hasLength(FareType.values.length),
        reason: 'no two kinds may share a glyph',
      );
    });

    /// Occupancy of [type]'s glyph on a coarse grid over [-16, 16]² — a
    /// low-resolution silhouette that ignores stroke order and colours.
    Set<int> silhouette(FareType type) {
      final path = fareGlyphPath(type);
      final cells = <int>{};
      for (var i = 0; i <= 16; i++) {
        for (var j = 0; j <= 16; j++) {
          final point = Offset(-16.0 + 2 * i, -16.0 + 2 * j);
          if (path.contains(point)) cells.add(i * 17 + j);
        }
      }
      return cells;
    }

    test('the four glyphs are four different silhouettes', () {
      final shapes = {for (final type in FareType.values) type: silhouette(type)};

      for (final type in FareType.values) {
        expect(shapes[type]!.length, greaterThan(20),
            reason: '${type.name} draws an actual body');
      }
      for (final a in FareType.values) {
        for (final b in FareType.values) {
          if (a.index >= b.index) continue;
          final disagreement = shapes[a]!.difference(shapes[b]!).length +
              shapes[b]!.difference(shapes[a]!).length;
          expect(disagreement, greaterThan(24),
              reason: '${a.name} and ${b.name} must not share a silhouette');
        }
      }
    });

    test('the standard ring is hollow; the VIP crown sits inside its ring', () {
      final standard = fareGlyphPath(FareType.standard);
      expect(standard.contains(Offset.zero), isFalse,
          reason: 'a ring reads as a ring only while its centre is empty');

      final vip = fareGlyphPath(FareType.vip);
      expect(vip.contains(Offset.zero), isTrue,
          reason: 'the crown fills the framing ring, setting the VIP apart '
              'from the bare standard ring');
    });
  });

  group('rendered in greyscale', () {
    /// Luma (Rec. 601-ish weights) of one RGBA pixel — the whole canvas
    /// flattened to what a colour-blind player sees.
    double luma(Uint8List pixels, int index) {
      final o = index * 4;
      return 0.2126 * pixels[o] + 0.7152 * pixels[o + 1] + 0.0722 * pixels[o + 2];
    }

    /// How many pixels two greyscale renders disagree on by more than
    /// [gap] — a threshold wide enough to survive antialiasing.
    int differingPixels(Uint8List a, Uint8List b, {double gap = 40}) {
      expect(a.length, b.length);
      var count = 0;
      for (var i = 0; i < a.length ~/ 4; i++) {
        if ((luma(a, i) - luma(b, i)).abs() > gap) count++;
      }
      return count;
    }

    /// Renders [type]'s glyph centred on a 96x96 marker disc painted in
    /// flat greys — identical for every kind — using the same paint
    /// weights the street markers use: [solid] is the pickup's filled
    /// glyph over its dark rim, `!solid` the dropoff's stroked one.
    Future<Uint8List> renderGlyph(FareType type, {required bool solid}) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawColor(const Color(0xFF404040), BlendMode.srcOver);
      canvas.drawCircle(
          const Offset(48, 48), 30, Paint()..color = const Color(0xFF6E6E6E));
      canvas.drawCircle(
        const Offset(48, 48),
        30,
        Paint()
          ..color = const Color(0xFF9C9C9C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.translate(48, 48);
      paintFareGlyph(
        canvas,
        type,
        ink: solid
            ? (Paint()
              ..color = Colors.white
              ..style = PaintingStyle.fill)
            : (Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round),
        rim: solid
            ? (Paint()
              ..color = Colors.black.withValues(alpha: 0.85)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..strokeJoin = StrokeJoin.round)
            : null,
      );
      return await _rawRgba(recorder, 96, 96);
    }

    Future<void> expectPairwiseDistinct(
      Map<FareType, Uint8List> renders,
      int floor,
      String weight,
    ) async {
      for (final a in FareType.values) {
        for (final b in FareType.values) {
          if (a.index >= b.index) continue;
          // Floors sit at roughly half the observed minimum disagreement
          // (375 px pickup / 327 px dropoff / 511 px real markers), so a
          // glyph that collapses toward another fails loudly while
          // antialiasing noise cannot.
          expect(differingPixels(renders[a]!, renders[b]!), greaterThan(floor),
              reason: '${a.name} and ${b.name} must sort in greyscale '
                  '($weight weight)');
        }
      }
    }

    test('pickup-weight glyphs disagree pairwise once hue is gone',
        () async {
      final renders = <FareType, Uint8List>{};
      for (final type in FareType.values) {
        renders[type] = await renderGlyph(type, solid: true);
      }
      await expectPairwiseDistinct(renders, 150, 'pickup');
    });

    test('dropoff-weight glyphs disagree pairwise too', () async {
      final renders = <FareType, Uint8List>{};
      for (final type in FareType.values) {
        renders[type] = await renderGlyph(type, solid: false);
      }
      await expectPairwiseDistinct(renders, 150, 'dropoff');
    });

    test('the real pickup markers sort in greyscale', () async {
      final renders = <FareType, Uint8List>{};
      for (final type in FareType.values) {
        final zone = PickupZone(
          position: Vector2.zero(),
          passenger: PassengerData(
            id: 'probe-${type.name}',
            pickupLocation: Vector2.zero(),
            dropoffLocation: Vector2.zero(),
            reward: 10,
            fareType: type,
          ),
          onPickup: () {},
        );
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        // The zone centres itself on its size, so translate the canvas to
        // the image centre; the pulsing body sits at its base radius
        // before any update tick, keeping the probe deterministic.
        canvas.translate(64, 64);
        zone.render(canvas);
        renders[type] = await _rawRgba(recorder, 128, 128);
      }

      // With the true kind colours in, luma is exactly what an
      // achromatopic player gets: every pair must still disagree over a
      // real area, glyph or disc.
      await expectPairwiseDistinct(renders, 200, 'pickup marker');
    });
  });
}

Future<Uint8List> _rawRgba(
  ui.PictureRecorder recorder,
  int width,
  int height,
) async {
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!.buffer.asUint8List();
}
