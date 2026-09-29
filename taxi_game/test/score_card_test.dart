import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/run_summary.dart';
import 'package:taxi_game/game/systems/score_card.dart';

/// The score card's content (issue #22): the numbers a shared card
/// carries — score, chain, distance, date, the day's seed — and the
/// plain-text line that travels beside the image.
void main() {
  const banked = RunSummary(
    outcome: ShiftOutcome.banked,
    score: 1234,
    bestChain: 4,
    faresDelivered: 12,
    distancePx: 12340,
    coinsEarned: 195,
    isPersonalBest: true,
    previousBest: 1100,
  );

  const wrecked = RunSummary(
    outcome: ShiftOutcome.wrecked,
    score: 90,
    bestChain: 3,
    faresDelivered: 5,
    distancePx: 620,
    coinsEarned: 40,
    isPersonalBest: false,
    previousBest: 1100,
  );

  ScoreCardData cardFor(
    RunSummary summary, {
    int seed = 9,
    String dateKey = '2026-09-26',
    bool isDailyShift = false,
    bool isGhostRace = false,
  }) =>
      ScoreCardData.fromRun(
        summary: summary,
        seed: seed,
        dateKey: dateKey,
        isDailyShift: isDailyShift,
        isGhostRace: isGhostRace,
      );

  test('a daily card carries the issue’s five facts', () {
    final card = cardFor(
      banked,
      seed: 987654321,
      dateKey: '2026-09-26',
      isDailyShift: true,
    );

    expect(card.title, 'DAILY SHIFT');
    expect(card.score, 1234);
    expect(card.chainLabel, '\u00d74');
    expect(card.distanceLabel, '1.2 km');
    expect(card.dateKey, '2026-09-26');
    expect(card.seedLabel, '987654321');
  });

  test('the plain-text line carries every fact the image does', () {
    final card = cardFor(
      banked,
      seed: 987654321,
      dateKey: '2026-09-26',
      isDailyShift: true,
    );

    expect(
      card.shareText,
      contains('CAB HUSTLE — DAILY SHIFT: 1234 pts'),
    );
    expect(card.shareText, contains('Best chain \u00d74'));
    expect(card.shareText, contains('1.2 km'));
    expect(card.shareText, contains('2026-09-26'));
    expect(card.shareText, contains('seed 987654321'),
        reason: 'the day’s seed is what makes the shared course findable');
  });

  test('the daily card says what makes the score comparable', () {
    final card = cardFor(banked, isDailyShift: true);

    expect(card.footer, 'ONE COURSE \u00b7 EVERY PLAYER \u00b7 TODAY ONLY');
  });

  test('an ordinary banked shift is titled as one', () {
    final card = cardFor(banked, seed: 42, dateKey: '2026-09-26');

    expect(card.title, 'SHIFT BANKED');
    expect(card.isDailyShift, isFalse);
    expect(card.footer, 'CAB HUSTLE');
    expect(card.shareText, contains('2026-09-26, seed 42'));
  });

  test('a wrecked shift keeps its ending in the title', () {
    final card = cardFor(wrecked);

    expect(card.title, 'SHIFT OVER');
    expect(card.shareText, contains('SHIFT OVER: 90 pts'));
  });

  test('a ghost race is never titled as the scoring daily', () {
    final card = cardFor(
      banked,
      dateKey: '2026-09-26',
      isGhostRace: true,
    );

    expect(card.title, 'GHOST RACE',
        reason: 'the day’s one attempt is spent; a race score must not '
            'present itself as the settled daily');
    expect(card.shareText, contains('ghost race on the 2026-09-26 course'));
  });

  test('the distance label travels from the summary untouched', () {
    // 620 px at 10 px/m = 62 m — the same rounding the panel shows.
    expect(cardFor(wrecked).distanceLabel, '62 m');
  });

  test('a personal best rides along for the badge', () {
    expect(cardFor(banked).isPersonalBest, isTrue);
    expect(cardFor(wrecked).isPersonalBest, isFalse);
  });

  group('the shareable rank title', () {
    test('the score bands name the tier', () {
      expect(
          ScoreCardData.rankTitleFor(
              score: 0, outcome: ShiftOutcome.banked, bestChain: 1),
          'RADIO ROOKIE');
      expect(
          ScoreCardData.rankTitleFor(
              score: 499, outcome: ShiftOutcome.banked, bestChain: 1),
          'RADIO ROOKIE');
      expect(
          ScoreCardData.rankTitleFor(
              score: 500, outcome: ShiftOutcome.banked, bestChain: 1),
          'CERTIFIED HUSTLER');
      expect(
          ScoreCardData.rankTitleFor(
              score: 2000, outcome: ShiftOutcome.banked, bestChain: 2),
          'TRAFFIC MENACE');
      expect(
          ScoreCardData.rankTitleFor(
              score: 5000, outcome: ShiftOutcome.banked, bestChain: 2),
          'GIG-LEGEND');
    });

    test('a wreck at a high chain earns the heartbreak title', () {
      expect(
        ScoreCardData.rankTitleFor(
            score: 90, outcome: ShiftOutcome.wrecked, bestChain: 8),
        'SO CLOSE IT HURTS',
        reason: 'losing an \u00d78 chain is the most shareable thing here',
      );
      // A low-chain wreck is just a bad day: the score band rules it.
      expect(
        ScoreCardData.rankTitleFor(
            score: 90, outcome: ShiftOutcome.wrecked, bestChain: 3),
        'RADIO ROOKIE',
      );
    });

    test('the rank leads the plain-text line and rides the card', () {
      final card = cardFor(banked);

      expect(card.rankTitle, 'CERTIFIED HUSTLER');
      expect(card.shareText, contains('1234 pts \u00b7 CERTIFIED HUSTLER'));
      expect(
        cardFor(wrecked).shareText,
        contains('90 pts \u00b7 RADIO ROOKIE'),
      );
    });
  });
}
