import 'package:flame/components.dart';

import '../taxi_game.dart';

/// Keeps a short-lived world-space one-shot in the live world frame across
/// a fold (issue #217).
///
/// The fold moves every mounted world child by its delta, but a one-shot
/// added in the frame that crossed the boundary is still in Flame's
/// lifecycle queue when the fold runs: its position is not in the tree
/// yet, so the walk misses it and it mounts one period (100,800 px) below
/// the live frame, off screen for its whole life. The anchor captured at
/// load plus the re-placement at mount close that window the way
/// [TrafficSpawner.shiftWorld] covers an unmounted vehicle's position:
/// the event's true distance is frame-independent, and mounting re-derives
/// the world y from whatever shift is live then.
mixin WorldOneShot on PositionComponent {
  /// The event's true distance, captured while the frame its constructor
  /// position names is still the live one.
  double _trueY = 0;
  bool _anchored = false;

  @override
  void onLoad() {
    super.onLoad();
    final game = findGame();
    if (game is! TaxiGame) return;
    // The constructor position is in the frame the live shift names right
    // now, so the difference is the event's true distance.
    _trueY = position.y - game.worldShift;
    _anchored = true;
  }

  @override
  void onMount() {
    super.onMount();
    if (!_anchored) return;
    final game = findGame();
    if (game is! TaxiGame) return;
    // A fold may have run between load and mount (issue #217): mounting is
    // the first moment the one-shot is in the tree the fold walks, so it
    // re-enters the frame here — before its first render.
    position.y = _trueY + game.worldShift;
  }
}
