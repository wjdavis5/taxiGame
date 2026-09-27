import 'package:flame/components.dart';

import '../components/road_obstacle.dart';
import '../components/road_segment.dart';
import '../taxi_game.dart';
import 'run_environment.dart';
import 'world_origin.dart';

/// Keeps the road in recycled chunks around the camera (issue #11).
///
/// The road is no longer one finite [RoadSegment] sized to the level's
/// route. Chunks of [chunkLength] px are added ahead of the camera before
/// they scroll into view and culled once they fall far enough behind it, so
/// a run can continue indefinitely at a constant handful of live chunks.
///
/// Chunk placement is pure index math over *true distance*: chunk *i*
/// covers run distances [i · [chunkLength], (i + 1) · [chunkLength]), and
/// sits at the world y [WorldOrigin.worldYForDistance] maps its top edge
/// to — so coverage is exactly reproducible for a given camera path, and
/// the world's folds (issue #30) never change which chunk holds which
/// stretch of road.
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

  /// The world this run's chunks belong to, captured on mount (issue #32).
  ///
  /// [TaxiGame] retires a whole world when a shift ends and a fresh one
  /// begins, and the retirement is queued like every Flame tree change:
  /// this manager can still get one update — its last — while the fresh
  /// run's world is already [TaxiGame.world]. Syncing through the live
  /// getter then would drop a recycled chunk straight into the new run's
  /// world, where nobody tracks or culls it. Chunks always go to the
  /// world this manager was mounted into; a retired manager's output
  /// dies with its own world.
  World? _runWorld;

  @override
  void onMount() {
    super.onMount();
    _runWorld = game.world;
  }

  /// Top (largest-y) edge of chunk [index] before any world fold (issue
  /// #30): chunk 0 covers [-800, 0]; negative indices cover the road
  /// behind the run's start. Kept for the first-frame view of the road —
  /// live placement always goes through [WorldOrigin.worldYForDistance].
  static double chunkTopY(int index) => -(index + 1) * chunkLength;

  /// The chunk containing world y [y] in the first frame band (no fold
  /// yet). Values on a boundary resolve to the chunk above; coverage is
  /// unaffected.
  static int chunkIndexForY(double y) => (-y / chunkLength).ceil() - 1;

  /// The chunk whose distance band contains true [distance]: chunk *i*
  /// holds [i · [chunkLength], (i + 1) · [chunkLength]). Values on a
  /// boundary resolve to the higher chunk; coverage is unaffected.
  static int chunkIndexForDistance(double distance) =>
      (distance / chunkLength).floor();

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
    final shift = game.worldShift;

    // The view's (margined) distance band, then the chunks holding it.
    final topIndex = chunkIndexForDistance(
        shift - (centerY - halfView - aheadMargin));
    final bottomIndex = chunkIndexForDistance(
        shift - (centerY + halfView + behindMargin));

    for (var i = bottomIndex; i <= topIndex; i++) {
      if (_chunks.containsKey(i)) continue;
      final chunk = RoadSegment(
        // Chunk i's top edge is true distance (i + 1) · chunkLength;
        // [WorldOrigin] maps it into the frame the camera is in.
        position: Vector2(TaxiGame.roadCenterX,
            WorldOrigin.worldYForDistance((i + 1) * chunkLength)),
        length: chunkLength,
        environment: environment,
        topDistance: (i + 1) * chunkLength,
      );
      if (environment != null) _placeCones(chunk, i);
      _chunks[i] = chunk;
      _runWorld!.add(chunk);
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
    final fromDistance = index * chunkLength;
    final toDistance = (index + 1) * chunkLength;

    for (final zone in env.constructionInRange(fromDistance, toDistance)) {
      final start = zone.startDistance.clamp(fromDistance, toDistance);
      final end = zone.endDistance.clamp(fromDistance, toDistance);
      for (var d = start; d <= end; d += coneSpacing) {
        final worldY = WorldOrigin.worldYForDistance(d);
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
            worldY - chunk.position.y,
          ),
        ));
      }
    }
  }
}
