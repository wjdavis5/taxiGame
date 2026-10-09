import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/endless_fare_controller.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The endless fare controller must not rebuild the pending fare every
/// frame for its horizon test (issue #253). A counting course pins the
/// call count: the first update spawns the first fare and caches the
/// next, and a parked cab leaves that cache untouched for as long as the
/// index and the world frame stand still.
class _CountingCourse extends EndlessCourse {
  _CountingCourse({required super.seed, super.environment});

  int fareCalls = 0;

  @override
  EndlessFare fare(int index, {double? worldShift}) {
    fareCalls++;
    return super.fare(index, worldShift: worldShift);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> drain() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.value();
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('the pending fare is built once, not every frame (#253)', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    final gameState = GameStateService(storage);
    await gameState.loadSaveData();

    final game = TaxiGame(
      levelLoader: LevelLoaderService(),
      gameState: gameState,
      endlessSeed: 7,
    );
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // Internal on purpose: exactly the call GameWidget makes once the game
    // has loaded, so mid-update adds queue like production.
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    await drain();

    // Swap in the counting course behind a fresh controller, wired to the
    // same environment (the original controller is retired first so only
    // the counted one drives the street).
    game.fareController!.removeFromParent();
    await drain();
    final course = _CountingCourse(seed: 7, environment: game.environment);
    final controller = EndlessFareController(
      course: course,
      onPickup: (_) {},
      onDropoff: (_) {},
    );
    game.fareController = controller;
    game.world.add(controller);
    await drain();

    // A parked cab: the first update spawns index 0 and caches index 1
    // beyond the horizon (1200 px ahead).
    for (var i = 0; i < 5; i++) {
      game.update(1 / 60);
      await drain();
    }
    final settled = course.fareCalls;
    expect(settled, greaterThan(0), reason: 'the first fare must be built');

    // One second of standing still must not touch the course again.
    for (var i = 0; i < 60; i++) {
      game.update(1 / 60);
      await drain();
    }
    expect(course.fareCalls, settled,
        reason: 'the pending fare is reused until it is spawned or the world '
            'folds');
  });
}
