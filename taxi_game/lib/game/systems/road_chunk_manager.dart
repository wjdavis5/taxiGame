import 'package:flame/components.dart';

import '../components/road_segment.dart';
import '../taxi_game.dart';

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
class RoadChunkManager extends Component with HasGameReference<TaxiGame> {
  RoadChunkManager({
    this.aheadMargin = 900,
    this.behindMargin = 600,
  });

  /// Length of one road chunk, in px.
  static const double chunkLength = 800.0;

  /// How far beyond the view top chunks are kept ready.
  final double aheadMargin;

  /// How far beyond the view bottom chunks are kept before culling.
  final double behindMargin;

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
      );
      _chunks[i] = chunk;
      game.world.add(chunk);
    }

    _chunks.removeWhere((index, chunk) {
      if (index >= bottomIndex && index <= topIndex) return false;
      chunk.removeFromParent();
      return true;
    });
  }
}
