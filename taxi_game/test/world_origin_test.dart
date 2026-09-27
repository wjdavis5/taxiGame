import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/road_chunk_manager.dart';
import 'package:taxi_game/game/systems/run_environment.dart';
import 'package:taxi_game/game/systems/world_origin.dart';

/// The world fold (issue #30): world y is a pure function of true
/// distance, so a run's coordinates never grow past one period and the
/// canvas's single-precision transforms never degrade the road. These pin
/// the mapping itself; the live behaviour is covered in endless_run_test.
void main() {
  group('WorldOrigin — the mapping', () {
    test('is the identity across the first period, like every pre-fold '
        'run', () {
      for (var d = 0.0; d < WorldOrigin.period; d += 997.0) {
        expect(WorldOrigin.worldYForDistance(d), -d, reason: 'at $d');
        expect(WorldOrigin.shiftForDistance(d), 0.0, reason: 'at $d');
      }
    });

    test('always lands in (-period, 0], however deep the run', () {
      for (var d = 0.0; d <= 5000000; d += 13001.0) {
        final y = WorldOrigin.worldYForDistance(d);
        expect(y, lessThanOrEqualTo(0.0), reason: 'at $d');
        expect(y, greaterThan(-WorldOrigin.period), reason: 'at $d');
      }
    });

    test('round-trips through the live frame at every distance', () {
      for (var d = 0.0; d <= 5000000; d += 13001.0) {
        final y = WorldOrigin.worldYForDistance(d);
        final back = WorldOrigin.distanceForWorldY(
            y, WorldOrigin.shiftForDistance(d));
        expect(back, closeTo(d, 1e-9), reason: 'at $d');
      }
    });

    test('folds exactly at each boundary and holds the frame between '
        'boundaries', () {
      // Just before the first boundary the world is still in frame 0.
      expect(
          WorldOrigin.shiftForDistance(WorldOrigin.period - 0.5), 0.0);
      // At the boundary the fold is applied, and the road continues
      // smoothly from the top of the frame.
      expect(WorldOrigin.shiftForDistance(WorldOrigin.period),
          WorldOrigin.period);
      expect(WorldOrigin.worldYForDistance(WorldOrigin.period), 0.0);
      expect(
        WorldOrigin.worldYForDistance(WorldOrigin.period + 1.0),
        -1.0,
        reason: 'the road resumes at the top of the new frame',
      );
      // And again, one period later.
      expect(WorldOrigin.shiftForDistance(2 * WorldOrigin.period + 5.0),
          2 * WorldOrigin.period);
      expect(WorldOrigin.worldYForDistance(2 * WorldOrigin.period + 5.0),
          -5.0);
    });
  });

  group('WorldOrigin — the period invariants', () {
    test('is a whole number of road chunks, so no chunk spans a fold', () {
      expect(WorldOrigin.period % RoadChunkManager.chunkLength, 0.0);
    });

    test('is a whole number of fare slots, so every ride shares one '
        'frame', () {
      expect(WorldOrigin.period % EndlessCourse.slotLength, 0.0);
    });

    test('sits clear of every intersection band, so no junction spans a '
        'fold', () {
      const halfBand = RunEnvironment.intersectionHalfBand;
      // How far the nearest cross street sits from a fold boundary: the
      // boundary is period mod spacing into the spacing's gap.
      const offset =
          WorldOrigin.period % RunEnvironment.intersectionSpacing;
      final clearance =
          math.min(offset, RunEnvironment.intersectionSpacing - offset) -
              halfBand;
      expect(clearance, greaterThan(200.0),
          reason: 'a junction must never straddle a fold');
    });
  });
}
