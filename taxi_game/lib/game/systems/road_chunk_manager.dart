import 'package:flame/components.dart';

import '../components/road_obstacle.dart';
import '../components/road_segment.dart';
import '../taxi_game.dart';
import 'run_environment.dart';

/// Keeps the road in recycled chunks around the camera (issue #11).
///
/// The road is no longer one finite [RoadSegment] sized to the level's
/// route. Chunks of [chunkLength] px are added ahead of the camera before
/// they scroll into view and culled once they fall far enough behind it, so
/// a run can continue indefinitely at a constant handful of live chunks.
///
/// Chunk placement is pure index math — chunk *i* covers
/// y ∈ [[chunkTopY], [chunkTopY] + [chunkLength]] — so coverage is exactly
/// reproducible for a given camera path.
///
/// With an [environment] (issue #24) each chunk renders the road geometry
/// that exists over its stretch, and carries that stretch's construction
/// cones as children — so culling a chunk culls its cones for free.
class RoadChunkManager extends Component with HasGameReference<TaxiGame> {
  RoadChunkManager({
    this.aheadMargin = 900,
    this.behindMargin = 600,
    this.environment,
  });

  /// Length of one road chunk, in px.
  static const double chunkLength = 800.0;

  /// How far beyond the view top chunks are kept ready.
  final double aheadMargin;

  /// How far beyond the view bottom chunks are kept before culling.
  final double behindMargin;

  /// The run's living world. Null renders the fixed level road.
  final RunEnvironment? environment;

  /// Spacing of cones along a work zone's closure line, in px.
  static const double coneSpacing = 90.0;

  final Map<int, RoadSegment> _chunks = {};

  /// Top (largest-y) edge of chunk [index]. Chunk 0 covers [-800, 0];
  /// negative indices cover the road behind the run's start.
  static double chunkTopY(int index) => -(index + 1) * chunkLength;

  /// The chunk containing world y [y]. Values on a boundary resolve to the
  /// chunk above; coverage is unaffected.
  static int chunkIndexForY(double y) => (-y / chunkLength).ceil() - 1;

  int get chunkCount => _chunks.length;

  /// Indices of every live chunk (unordered).
  Iterable<int> get chunkIndices => _chunks.keys;

  bool hasChunk(int index) => _chunks.containsKey(index);

  @override
  void update(double dt) {
    super.update(dt);
    sync();
  }

  /// Adds missing chunks in range and culls out-of-range ones.
  void sync() {
    final centerY = game.camera.viewfinder.position.y;
    final halfView = game.camera.viewport.size.y / 2;

    final topIndex = chunkIndexForY(centerY - halfView - aheadMargin);
    final bottomIndex = chunkIndexForY(centerY + halfView + behindMargin);

    for (var i = bottomIndex; i <= topIndex; i++) {
      if (_chunks.containsKey(i)) continue;
      final chunk = RoadSegment(
        position: Vector2(TaxiGame.roadCenterX, chunkTopY(i)),
        length: chunkLength,
        environment: environment,
      );
      if (environment != null) _placeCones(chunk, i);
      _chunks[i] = chunk;
      game.world.add(chunk);
    }

    _chunks.removeWhere((index, chunk) {
      if (index >= bottomIndex && index <= topIndex) return false;
      chunk.removeFromParent();
      return true;
    });
  }

  /// Adds the cone line of every work zone overlapping chunk [index] to
  /// the chunk as children. Cone x follows the road geometry at each
  /// cone's own y, so a line across a taper still tracks the kerb.
  void _placeCones(RoadSegment chunk, int index) {
    final env = environment!;
    final topY = chunkTopY(index);
    final fromDistance = -(topY + chunkLength);
    final toDistance = -topY;

    for (final zone in env.constructionInRange(fromDistance, toDistance)) {
      final start = zone.startDistance.clamp(fromDistance, toDistance);
      final end = zone.endDistance.clamp(fromDistance, toDistance);
      for (var d = start; d <= end; d += coneSpacing) {
        final worldY = -d;
        final road = env.roadAt(d);
        // The line itself sits on the boundary; [zone.closedRight] only
        // decides which lanes the spawner keeps clear beyond it.
        final coneX = road.leftX + zone.boundaryFraction * road.width;
        // The chunk's local space has its origin at the road box's
        // top-left — the anchor (top-centre at roadCenterX) shifted left
        // by half the 200 px box — which is exactly where the classic
        // road render starts drawing.
        chunk.add(RoadObstacle(
          position: Vector2(
            coneX - (TaxiGame.roadCenterX - 100),
            worldY - topY,
          ),
        ));
      }
    }
  }
}
