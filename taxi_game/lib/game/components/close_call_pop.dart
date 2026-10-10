import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'world_one_shot.dart';

/// Floating world-space award for one close call (issue #23). Names the
/// points where the pass happened — a near-miss the player does not
/// notice scores nothing psychologically, so the award rises out of the
/// gap the taxi just threaded. Rises and shrinks, then removes itself —
/// the same beat the scrape marker plays, in the close-call palette's
/// cyan so the two touch-adjacent events never read alike.
///
/// The first award of a run also carries the lesson (issue #269): the
/// pass paid because it was close (proximity) and fast (speed), and the
/// points joined the run score the chain holds at risk until it is
/// banked. Later awards in the same run keep the plain line — the
/// lesson has already been said.
class CloseCallPop extends TextComponent with WorldOneShot {
  CloseCallPop({
    required Vector2 position,
    required int points,
    bool firstAward = false,
  }) : super(
          text: firstAward ? _firstAwardText(points) : 'CLOSE CALL +$points',
          anchor: Anchor.center,
          position: position.clone(),
          textRenderer: TextPaint(
            style: const TextStyle(
              color: Color(0xFF4DD0E1),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        );

  /// The rule the first award states (issue #269): both halves of the
  /// qualifying pass — speed and proximity — feed the at-risk chain.
  static const String firstAwardLesson =
      'SPEED + PROXIMITY FEED THE AT-RISK CHAIN';

  static String _firstAwardText(int points) =>
      'CLOSE CALL +$points\n$firstAwardLesson';

  static const double lifetime = 0.8;
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
