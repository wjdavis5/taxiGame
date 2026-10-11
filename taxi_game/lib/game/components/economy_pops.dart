import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../systems/fare_chain.dart';
import '../taxi_game.dart';
import 'world_one_shot.dart';

/// The economy's world-space feedback pops (issues #270, #273): the fare
/// settlement at every dropoff, the chain break when a countdown runs
/// out, and the push bonus when the player rides on. Each names its
/// event in its own colour so the three can never be read for one
/// another; all three rise and fade on the [CloseCallPop] beat.

/// What one dropoff paid and what it left at risk (issue #270). The
/// settlement's whole story, where the player is looking when it lands.
class FareSettlementPop extends TextComponent with WorldOneShot {
  FareSettlementPop({
    required Vector2 position,
    required FareSettlement settlement,
  }) : super(
          text: '${headline(settlement)}\n${detail(settlement)}',
          anchor: Anchor.center,
          position: position.clone(),
          textRenderer: TextPaint(style: _styleFor(settlement)),
        ) {
    // The kerb is at the road's edge, so an unclamped pop runs half off
    // the phone — the same clamp [CloseCallPop] applies (issue #269).
    final half = width / 2;
    x = x.clamp(
      math.min(edgeMargin + half, TaxiGame.roadCenterX),
      math.max(2 * TaxiGame.roadCenterX - edgeMargin - half,
          TaxiGame.roadCenterX),
    );
  }

  /// How long the settlement stays up on the HUD after the dropoff.
  static const double hudHoldSeconds = 4.0;

  static const double edgeMargin = 8.0;
  static const double lifetime = 1.1;
  static const double riseSpeed = 46.0;

  /// The verdict line: the one word the player needs.
  static String headline(FareSettlement settlement) =>
      settlement.isLate ? 'LATE' : 'ON TIME';

  /// The numbers behind the verdict: value x multiplier, any chain bonus
  /// the fare kind paid, the score it awarded, and the at-risk total.
  static String detail(FareSettlement settlement) {
    final bonus = settlement.chainStepBonus > 0
        ? ' +${settlement.chainStepBonus} CHAIN'
        : '';
    return '${settlement.fareValue} \u00d7${settlement.multiplier}$bonus\n'
        '+${settlement.scoreAwarded} \u00b7 AT RISK ${settlement.scoreTotal}';
  }

  /// The HUD line, one line so it scales down instead of wrapping on the
  /// smallest phone: the same words the world pop plays, flattened.
  static String hudLine(FareSettlement settlement) {
    final bonus = settlement.chainStepBonus > 0
        ? ' +${settlement.chainStepBonus} CHAIN'
        : '';
    return '${headline(settlement)}  ${settlement.fareValue} '
        '\u00d7${settlement.multiplier}$bonus  \u00b7  '
        '+${settlement.scoreAwarded} \u00b7 AT RISK ${settlement.scoreTotal}';
  }

  static Color colorFor(FareSettlement settlement) => settlement.isLate
      ? const Color(0xFFFF7043)
      : const Color(0xFFFFD54F);

  static TextStyle _styleFor(FareSettlement settlement) => TextStyle(
        color: colorFor(settlement),
        fontSize: 15,
        fontWeight: FontWeight.w900,
      );

  double _age = 0;

  @override
  void update(double dt) {
    super.update(dt);

    _age += dt;
    final t = (_age / lifetime).clamp(0.0, 1.0);
    y -= riseSpeed * dt;
    final s = 1.0 - 0.35 * t;
    scale.setValues(s, s);
    if (_age >= lifetime) removeFromParent();
  }
}

/// A countdown ran out and took the chain with it (issue #273). Names the
/// multiplier that was just lost, in the failure palette's red — the
/// silent reset now has a moment of its own.
class ChainBreakPop extends TextComponent with WorldOneShot {
  ChainBreakPop({
    required Vector2 position,
    required int lostMultiplier,
  }) : super(
          text: 'CHAIN BROKEN\n\u00d7$lostMultiplier LOST',
          anchor: Anchor.center,
          position: position.clone(),
          textRenderer: TextPaint(
            style: const TextStyle(
              color: Color(0xFFFF5252),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        );

  static const double lifetime = 1.1;
  static const double riseSpeed = 46.0;

  double _age = 0;

  @override
  void update(double dt) {
    super.update(dt);

    _age += dt;
    final t = (_age / lifetime).clamp(0.0, 1.0);
    y -= riseSpeed * dt;
    final s = 1.0 - 0.35 * t;
    scale.setValues(s, s);
    if (_age >= lifetime) removeFromParent();
  }
}

/// The push bonus landed (issue #273): riding on stepped the multiplier,
/// and the pop names the step it just bought, in the bank prompt's amber.
class PushPop extends TextComponent with WorldOneShot {
  PushPop({
    required Vector2 position,
    required int multiplier,
  }) : super(
          text: 'PUSH ON \u00d7$multiplier',
          anchor: Anchor.center,
          position: position.clone(),
          textRenderer: TextPaint(
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        );

  static const double lifetime = 0.9;
  static const double riseSpeed = 46.0;

  double _age = 0;

  @override
  void update(double dt) {
    super.update(dt);

    _age += dt;
    final t = (_age / lifetime).clamp(0.0, 1.0);
    y -= riseSpeed * dt;
    final s = 1.0 - 0.35 * t;
    scale.setValues(s, s);
    if (_age >= lifetime) removeFromParent();
  }
}
