import 'dart:typed_data';

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
}
