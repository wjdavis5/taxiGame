import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show TextSpan;
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/score_card.dart';
import 'package:taxi_game/services/score_card_renderer.dart';

/// The score card renderer (issue #22): a settled shift in, real PNG
/// bytes out — the artifact the share sheet hands to other apps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const card = ScoreCardData(
    title: 'DAILY SHIFT',
    score: 1234,
    bestChain: 4,
    distanceLabel: '1.2 km',
    dateKey: '2026-09-26',
    seed: 987654321,
    isDailyShift: true,
    isGhostRace: false,
    isPersonalBest: true,
    rankTitle: 'CERTIFIED HUSTLER',
  );

  /// PNG bytes: 8-byte signature, then the IHDR chunk, whose payload
  /// opens with the big-endian width and height.
  (int, int) pngDimensions(Uint8List bytes) {
    final width = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
    final height = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
    return (width, height);
  }

  test('rendering produces a real PNG at the declared card size', () async {
    final bytes = await ScoreCardRenderer().renderPng(card);

    expect(bytes.length, greaterThan(1000),
        reason: 'a card of real content is never a trivial file');
    // \x89PNG\r\n\x1a\n — every consumer of the share sheet relies on it.
    expect(bytes.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    expect(pngDimensions(bytes),
        (ScoreCardRenderer.cardWidth, ScoreCardRenderer.cardHeight));
  });

  test('a personal-best card renders too — the badge path runs', () async {
    final noBadge = await ScoreCardRenderer().renderPng(
      const ScoreCardData(
        title: 'SHIFT OVER',
        score: 90,
        bestChain: 3,
        distanceLabel: '62 m',
        dateKey: '2026-09-26',
        seed: 9,
        isDailyShift: false,
        isGhostRace: false,
        isPersonalBest: false,
        rankTitle: 'RADIO ROOKIE',
      ),
    );

    expect(noBadge.sublist(0, 8),
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  });

  test('the header keeps the rank\'s ink clear of the digits (issue #160)',
      () async {
    // The rank ("CERTIFIED HUSTLER", accent) used to have no clearance
    // above the 220 px score digits (white): _drawCentered centers each
    // line's box on its y, the digits' box towers over the rank's, and
    // the number painted across the bottom of the rank's letters. This
    // scans the rendered raster's header band and measures ink-to-ink
    // rows — under Ahem every glyph is a full em square (this repo's
    // pessimistic-ink convention, garage_screen_test.dart), so a gap
    // here means a gap under any device font too, whose digits reach
    // only cap height into the em.
    final image = await ScoreCardRenderer().renderImage(card);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final px = data!.buffer.asUint8List();
    const w = ScoreCardRenderer.cardWidth;

    /// A row "has" a colour when any pixel in it is exactly that colour —
    /// glyph interiors are flat ink, so antialiased edges can only shrink
    /// a measured extent, never grow it.
    bool rowHas(int y, int r, int g, int b) {
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        if (px[o] == r && px[o + 1] == g && px[o + 2] == b) return true;
      }
      return false;
    }

    // The band between the brand above (accent, ink ends ~122) and the
    // badge below (accent again — its top edge reaches ~630 at the old
    // centre, ~652 at the new one): inside the band the only accent is
    // the rank, the only white the digits, and the only
    // muted-above-the-rank the title.
    const bandTop = 124, bandBottom = 620;
    var rankTop = -1, rankBottom = -1, digitTop = -1;
    for (var y = bandTop; y < bandBottom; y++) {
      if (rowHas(y, 0xFF, 0xC9, 0x3C)) {
        if (rankTop == -1) rankTop = y;
        rankBottom = y;
      }
      if (digitTop == -1 && rowHas(y, 0xFF, 0xFF, 0xFF)) digitTop = y;
    }
    var titleBottom = -1;
    for (var y = bandTop; y < rankTop; y++) {
      if (rowHas(y, 0x9F, 0xB2, 0xBF)) titleBottom = y;
    }

    expect(rankTop, greaterThan(-1), reason: 'the rank must paint accent ink');
    expect(digitTop, greaterThan(-1),
        reason: 'the score digits must paint white ink');
    expect(titleBottom, greaterThan(-1),
        reason: 'the title must paint muted ink above the rank');

    // 16 px of daylight, the issue's bar: enough that neither line's
    // ascenders nor antialiasing can bridge it.
    expect(digitTop - rankBottom, greaterThanOrEqualTo(16),
        reason: 'the digits must start at least 16 px below the rank\'s '
            'ink — at the old centres the number painted straight over '
            'the rank\'s lower letters');
    expect(rankTop - titleBottom, greaterThanOrEqualTo(16),
        reason: 'the rank must not trade the overlap upward into the '
            'title either');
  });

  test('the fitted footer lays its whole line out — no ellipsis (issue #165)',
      () async {
    // 'ONE COURSE · EVERY PLAYER · TODAY ONLY' is 38 characters; at the
    // old fixed 32 px + 4 px tracking that is 38 × 36 = 1368 px under
    // the tests' Ahem, so the 840 px box (maxLines:1 + ellipsis) cut it
    // to "…TODAY O…". The fix keeps the copy and shrinks the type until
    // the entire line fits the 720 px column the rest of the card keeps
    // to, on one line.
    final painter = ScoreCardRenderer().footerPainterFor(card.footer);

    expect(painter.didExceedMaxLines, isFalse,
        reason: 'the whole footer must fit one line — the ellipsis is a '
            'safety net, not the layout');
    expect(painter.width, lessThanOrEqualTo(720),
        reason: 'the footer must honour the 140–860 column like every '
            'other element on the card');

    final size = (painter.text as TextSpan).style!.fontSize!;
    expect(size, lessThan(32),
        reason: 'the 38-char line cannot fit at the nominal 32 px — the '
            'fit loop must have stepped the type down');

    // Ahem gives every glyph a size-px square plus size/8 tracking, so a
    // line that laid out all 38 characters measures exactly this; one
    // that ellipsized drops characters for the '\u2026' and cannot
    // match it.
    expect(painter.width, closeTo(card.footer.length * size * 9 / 8, 0.5),
        reason: 'every character of the footer must be on the line');
  });

  test('the footer paints inside the column, clear of the last row '
      '(issue #165)', () async {
    // The last stat row (Day seed) centres at 1226; under the tests'
    // Ahem its 52 px white value ink ends at ~1252. Below that band the
    // card paints nothing but the footer, so the muted ink found there
    // is the footer's — and it must sit whole inside the 140–860
    // column, clear of the row above it.
    final image = await ScoreCardRenderer().renderImage(card);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final px = data!.buffer.asUint8List();
    const w = ScoreCardRenderer.cardWidth;

    /// A pixel "is" a colour when it is exactly that colour — glyph
    /// interiors are flat ink, so antialiased edges can only shrink a
    /// measured extent, never grow it.
    bool isColor(int x, int y, int r, int g, int b) {
      final o = (y * w + x) * 4;
      return px[o] == r && px[o + 1] == g && px[o + 2] == b;
    }

    // The Day-seed row's white value ink: the last white on the card
    // (the Date row's value ends ~1134, well above this window).
    var whiteBottom = -1;
    for (var y = 1150; y < 1300; y++) {
      for (var x = 0; x < w; x++) {
        if (isColor(x, y, 0xFF, 0xFF, 0xFF)) whiteBottom = y;
      }
    }
    expect(whiteBottom, greaterThan(-1),
        reason: 'the Day-seed row must paint its white value ink');

    var footerTop = -1, footerBottom = -1, footerLeft = w, footerRight = -1;
    for (var y = whiteBottom + 1; y < ScoreCardRenderer.cardHeight; y++) {
      for (var x = 0; x < w; x++) {
        if (isColor(x, y, 0x9F, 0xB2, 0xBF)) {
          if (footerTop == -1) footerTop = y;
          footerBottom = y;
          if (x < footerLeft) footerLeft = x;
          if (x > footerRight) footerRight = x;
        }
      }
    }

    expect(footerTop, greaterThan(-1),
        reason: 'the footer must paint muted ink below the last stat row');
    // The 140–860 column the divider and the rows keep to: the old 840
    // px box centred the ellipsized line across 80..920, outside these
    // margins entirely.
    expect(footerLeft, greaterThanOrEqualTo(140));
    expect(footerRight, lessThanOrEqualTo(860));
    expect(footerTop - whiteBottom, greaterThanOrEqualTo(16),
        reason: 'the footer must clear the last row\'s value ink — the '
            'centre sits 96 px under the row, near its own 118 px pitch');
    expect(ScoreCardRenderer.cardHeight - footerBottom,
        greaterThanOrEqualTo(16),
        reason: 'the footer must also clear the card\'s bottom edge — '
            'the move down to centre 1322 must not push it off the card');
  });
}
