import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/components/economy_pops.dart';
import 'package:taxi_game/game/systems/fare_chain.dart';

/// The economy pops' copy (issues #270, #273): the settlement pop, the
/// chain-break pop, and the push pop each say exactly what happened. The
/// strings are the feedback — a silent miscount here is a silent miscount
/// on the street — so every line is pinned literally.
void main() {
  group('FareSettlementPop copy (issue #270)', () {
    const longHaul = FareSettlement(
      outcome: FareOutcome.onTime,
      fareValue: 60,
      multiplier: 2,
      chainStepBonus: 2,
      scoreAwarded: 120,
      scoreTotal: 240,
    );

    const standard = FareSettlement(
      outcome: FareOutcome.onTime,
      fareValue: 50,
      multiplier: 1,
      chainStepBonus: 0,
      scoreAwarded: 50,
      scoreTotal: 50,
    );

    const late = FareSettlement(
      outcome: FareOutcome.late,
      fareValue: 50,
      multiplier: 1,
      chainStepBonus: 0,
      scoreAwarded: 50,
      scoreTotal: 90,
    );

    test('an on-time long-haul names status, value, multiplier, bonus, '
        'award, and the at-risk total', () {
      expect(FareSettlementPop.headline(longHaul), 'ON TIME');
      expect(FareSettlementPop.detail(longHaul),
          '60 \u00d72 +2 CHAIN\n+120 \u00b7 AT RISK 240');
      expect(FareSettlementPop.hudLine(longHaul),
          'ON TIME  60 \u00d72 +2 CHAIN  \u00b7  +120 \u00b7 AT RISK 240');

      final pop =
          FareSettlementPop(position: Vector2.zero(), settlement: longHaul);
      expect(pop.text, 'ON TIME\n60 \u00d72 +2 CHAIN\n+120 \u00b7 AT RISK 240');
      expect(FareSettlementPop.colorFor(longHaul),
          const Color(0xFFFFD54F));
    });

    test('a standard on-time fare prints no chain-bonus segment', () {
      expect(FareSettlementPop.detail(standard),
          '50 \u00d71\n+50 \u00b7 AT RISK 50');
      expect(FareSettlementPop.hudLine(standard),
          'ON TIME  50 \u00d71  \u00b7  +50 \u00b7 AT RISK 50');
    });

    test('a late fare reads LATE at a flat 1x, in the failure colour', () {
      expect(FareSettlementPop.headline(late), 'LATE');
      expect(FareSettlementPop.detail(late),
          '50 \u00d71\n+50 \u00b7 AT RISK 90');
      expect(FareSettlementPop.hudLine(late),
          'LATE  50 \u00d71  \u00b7  +50 \u00b7 AT RISK 90');

      final pop = FareSettlementPop(position: Vector2.zero(), settlement: late);
      expect(pop.text, 'LATE\n50 \u00d71\n+50 \u00b7 AT RISK 90');
      expect(FareSettlementPop.colorFor(late), const Color(0xFFFF7043));
    });
  });

  test('ChainBreakPop names the multiplier the countdown cost (issue #273)',
      () {
    final pop = ChainBreakPop(position: Vector2.zero(), lostMultiplier: 3);

    expect(pop.text, 'CHAIN BROKEN\n\u00d73 LOST');
  });

  test('PushPop names the multiplier the push bought (issue #273)', () {
    final pop = PushPop(position: Vector2.zero(), multiplier: 4);

    expect(pop.text, 'PUSH ON \u00d74');
  });
}
