/// Folds the endless run's world coordinates back toward the origin
/// (issue #30 — "after a while the road is just blue").
///
/// A run's world y grows without bound as the taxi drives up-road (y runs
/// negative), and canvas transforms are single-precision: past ~2^24 px of
/// camera translation the geometry's precision degrades — visibly on the
/// software rasteriser by 33 million px, and earlier on GPU backends —
/// until the road stops painting and only the sky backdrop is left. The
/// fix is the classic endless-runner one: periodically move the *whole*
/// world back near the origin, exactly as if the run had restarted, while
/// every system keeps counting the true distance driven.
///
/// The mapping is a pure function of true distance, never of accumulated
/// state: true distance `d` lives at world y
/// `worldYForDistance(d) = shiftForDistance(d) - d`, which is always in
/// (-[period], 0]. When the taxi crosses the next multiple of [period],
/// [TaxiGame] adds [period] to the y of every world component and to the
/// camera — the frame every consumer reads *is* this canonical mapping, so
/// placement code never needs to know how many folds have happened; it
/// converts true distance to world y and back with these two functions.
///
/// [period] is chosen so no stretch of road that renders or scores as one
/// piece ever straddles a fold:
///
///  - it is a multiple of [RoadChunkManager.chunkLength] (800 px — 126
///    chunks), so a road chunk never spans two frames;
///  - it is a multiple of [EndlessCourse.slotLength] (1400 px — 72 slots),
///    so a fare's pickup and dropoff always share a frame and
///    [EndlessFare.rideLength] stays a real ride;
///  - it sits ≥ 1,640 px clear of every intersection band (the nearest
///    cross street to a multiple of [period] is `100800 % 9000 = 1800` px
///    away, and bands are 320 px wide), so a junction never spans two.
///
/// At most |y| ≈ [period] the canvas transform's precision error is under
/// 0.01 px — four orders of magnitude finer than a pixel — so rendering is
/// exact for the life of the run. One fold is ~100,800 px ≈ 10 km ≈ 11
/// minutes of cruise: rare, and invisible when it happens, because every
/// world y moves by the same delta in the same tick.
class WorldOrigin {
  WorldOrigin._();

  /// True road distance one world frame holds, in px. See the class docs
  /// for the divisibility invariants this constant carries.
  static const double period = 100800.0;

  /// How far the world has folded for true [distance]: the total y delta
  /// applied to the world when the taxi passed that distance. Zero for the
  /// first [period] px — the mapping every pre-#30 run knew.
  static double shiftForDistance(double distance) =>
      period * (distance / period).floorToDouble();

  /// The world y true [distance] lives at, in the run's current frame.
  /// Always in (-[period], 0].
  static double worldYForDistance(double distance) =>
      shiftForDistance(distance) - distance;

  /// The true distance a world y reads as, given the world's current
  /// [shift] ([TaxiGame.worldShift]). The inverse of [worldYForDistance]
  /// for distances in the live frame.
  static double distanceForWorldY(double worldY, double shift) =>
      shift - worldY;
}
