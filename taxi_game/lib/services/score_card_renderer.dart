import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../game/systems/score_card.dart';

/// Renders a [ScoreCardData] into the PNG the share sheet hands out
/// (issue #22).
///
/// Drawn straight onto a [ui.Canvas] — no widget tree, no RepaintBoundary
/// to harvest from the live summary panel — so the card renders anywhere
/// the game runs, deterministically, with nothing but the framework.
/// Everything stays local: pixels in, PNG bytes out; the bytes leave the
/// device only when the player picks a destination in the share sheet.
class ScoreCardRenderer {
  /// The card's raster size, in px. A fixed 5:7 card at a size that reads
  /// crisply when a chat app downsamples it; independent of the device's
  /// screen so the shared image is the same everywhere.
  static const int cardWidth = 1000;
  static const int cardHeight = 1400;

  static const ui.Color _background = ui.Color(0xFF16232E);
  static const ui.Color _accent = ui.Color(0xFFFFC93C);
  static const ui.Color _ink = ui.Color(0xFFFFFFFF);
  static const ui.Color _muted = ui.Color(0xFF9FB2BF);

  /// Renders [card] and PNG-encodes it.
  Future<Uint8List> renderPng(ScoreCardData card) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    _paint(canvas, card);
    final picture = recorder.endRecording();
    final image = await picture.toImage(cardWidth, cardHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Encoding the score card PNG produced no bytes.');
    }
    return byteData.buffer.asUint8List();
  }

  void _paint(ui.Canvas canvas, ScoreCardData card) {
    // Rounded corners over transparency: the card floats in the share
    // sheet instead of reading as a full-bleed screenshot.
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(0, 0, 1000, 1400),
        const ui.Radius.circular(56),
      ),
      ui.Paint()..color = _background,
    );

    // Brand.
    _drawCentered(
      canvas,
      'CAB HUSTLE',
      at: const ui.Offset(cardWidth / 2, 96),
      size: 52,
      color: _accent,
      weight: ui.FontWeight.w900,
      letterSpacing: 10,
    );

    // What the run was.
    _drawCentered(
      canvas,
      card.title,
      at: const ui.Offset(cardWidth / 2, 236),
      size: 46,
      color: _muted,
      weight: ui.FontWeight.w700,
      letterSpacing: 8,
    );

    // The shareable rank ('TRAFFIC MENACE') — the line a group chat
    // reads first, in the brand accent so it outranks the title above
    // it and trails the score below.
    _drawCentered(
      canvas,
      card.rankTitle,
      at: const ui.Offset(cardWidth / 2, 330),
      size: 40,
      color: _accent,
      weight: ui.FontWeight.w900,
      letterSpacing: 6,
    );

    // The number being shared.
    _drawCentered(
      canvas,
      '${card.score}',
      at: const ui.Offset(cardWidth / 2, 420),
      size: 220,
      color: _ink,
      weight: ui.FontWeight.w900,
    );
    _drawCentered(
      canvas,
      'FINAL SCORE',
      at: const ui.Offset(cardWidth / 2, 590),
      size: 34,
      color: _muted,
      weight: ui.FontWeight.w600,
      letterSpacing: 6,
    );

    if (card.isPersonalBest) {
      _drawBadge(canvas, 'NEW PERSONAL BEST', at: const ui.Offset(cardWidth / 2, 668));
    }

    canvas.drawLine(
      const ui.Offset(140, 760),
      const ui.Offset(860, 760),
      ui.Paint()
        ..color = _accent
        ..strokeWidth = 3,
    );

    // The issue's row list: chain, distance, date, seed.
    var y = 872.0;
    y = _drawRow(canvas, 'Best chain', card.chainLabel, y);
    y = _drawRow(canvas, 'Distance', card.distanceLabel, y);
    y = _drawRow(canvas, 'Date', card.dateKey, y);
    _drawRow(canvas, card.isDailyShift ? 'Day seed' : 'Seed', card.seedLabel, y);

    _drawCentered(
      canvas,
      card.footer,
      // cardWidth/2, cardHeight - 96.
      at: const ui.Offset(500, 1304),
      size: 32,
      color: _muted,
      weight: ui.FontWeight.w600,
      letterSpacing: 4,
    );
  }

  void _drawCentered(
    ui.Canvas canvas,
    String text, {
    required ui.Offset at,
    required double size,
    required ui.Color color,
    ui.FontWeight weight = ui.FontWeight.w400,
    double letterSpacing = 0,
  }) {
    final painter = _painterFor(
      text,
      size: size,
      color: color,
      weight: weight,
      letterSpacing: letterSpacing,
    );
    painter.layout(maxWidth: cardWidth - 160);
    painter.paint(canvas, at - ui.Offset(painter.width / 2, painter.height / 2));
  }

  /// One stat row: label left, value right, [y] is the row's centre.
  /// Returns the next row's centre.
  double _drawRow(ui.Canvas canvas, String label, String value, double y) {
    const left = 140.0;
    const right = cardWidth - 140.0;
    const rowHeight = 118.0;

    final labelPainter = _painterFor(
      label,
      size: 40,
      color: _muted,
      weight: ui.FontWeight.w600,
    );
    labelPainter.layout();
    labelPainter.paint(canvas, ui.Offset(left, y - labelPainter.height / 2));

    final valuePainter = _painterFor(
      value,
      size: 52,
      color: _ink,
      weight: ui.FontWeight.w800,
    );
    valuePainter.layout(maxWidth: right - left - labelPainter.width - 24);
    valuePainter.paint(
      canvas,
      ui.Offset(right - valuePainter.width, y - valuePainter.height / 2),
    );
    return y + rowHeight;
  }

  void _drawBadge(ui.Canvas canvas, String text, {required ui.Offset at}) {
    final painter = _painterFor(
      text,
      size: 36,
      color: const ui.Color(0xFF111111),
      weight: ui.FontWeight.w800,
      letterSpacing: 3,
    );
    painter.layout();
    const padH = 34.0;
    const padV = 20.0;
    final rect = ui.Rect.fromCenter(
      center: at,
      width: painter.width + padH * 2,
      height: painter.height + padV * 2,
    );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
          rect, ui.Radius.circular(rect.height / 2)),
      ui.Paint()..color = _accent,
    );
    painter.paint(
      canvas,
      ui.Offset(rect.left + padH, rect.center.dy - painter.height / 2),
    );
  }

  TextPainter _painterFor(
    String text, {
    required double size,
    required ui.Color color,
    required ui.FontWeight weight,
    double letterSpacing = 0,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: weight,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '\u2026',
    );
  }
}
