import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/data/vehicle_catalog.dart';
import 'package:taxi_game/game/components/player_vehicle.dart';
import 'package:taxi_game/game/systems/collision_rules.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/game/vehicle_sprites.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// One handling axis: how to read it off the stats, and which direction is
/// better. Body size reads smaller-is-better; everything else reads
/// bigger-is-better.
class _Axis {
  final String name;
  final double Function(VehicleStats) of;
  final bool higherIsBetter;

  const _Axis(this.name, this.of, {required this.higherIsBetter});

  /// True when [a] beats [b] on this axis by a strict margin.
  bool aBeatsB(VehicleStats a, VehicleStats b) =>
      higherIsBetter ? of(a) > of(b) : of(a) < of(b);
}

final List<_Axis> _axes = [
  _Axis('top speed', (s) => s.topSpeed, higherIsBetter: true),
  _Axis('acceleration', (s) => s.acceleration, higherIsBetter: true),
  _Axis('steering', (s) => s.steeringSpeed, higherIsBetter: true),
  _Axis('body size', (s) => s.bodyArea, higherIsBetter: false),
];

VehicleStats statsOf(String id) => VehicleCatalog.byId(id)!.stats;

/// Mounts [game] headlessly (the pattern flame_test uses) so component
/// `onLoad` hooks run, then returns it.
Future<TaxiGame> mountGame(TaxiGame game) async {
  game.onGameResize(Vector2(400, 800));
  await game.onLoad();
  await game.ready();
  return game;
}

/// Issue #9: cars must have handling differences the player can feel, with
/// genuine trade-offs so the garage is a decision rather than an upgrade
/// treadmill. The catalog invariants pin the design; the physics groups
/// prove two cars drive differently with the art removed entirely.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('catalog trade-offs (issue #9)', () {
    test('every car is strictly beaten on at least one axis by some car',
        () {
      // The "no upgrade treadmill" rule: whatever car you eye, some other
      // car must hold an advantage over it, so the choice is never settled
      // by "this one is just better".
      for (final vehicle in VehicleCatalog.vehicles) {
        final losses = <String>[];
        for (final other in VehicleCatalog.vehicles) {
          if (other.id == vehicle.id) continue;
          for (final axis in _axes) {
            if (axis.aBeatsB(other.stats, vehicle.stats)) {
              losses.add('${other.name} on ${axis.name}');
            }
          }
        }
        expect(
          losses,
          isNotEmpty,
          reason: '${vehicle.name} dominates the fleet — nothing is better '
              'at anything, so choosing it is not a decision',
        );
      }
    });

    test('no car holds the fleet best on every axis', () {
      // The literal issue criterion: no single car may sit at the top of
      // all four metrics at once.
      final crownHolders = _axes
          .map((axis) => VehicleCatalog.vehicles
              .reduce((a, b) => axis.aBeatsB(b.stats, a.stats) ? b : a)
              .id)
          .toSet();
      expect(
        crownHolders.length,
        greaterThan(1),
        reason: 'one car sweeping every crown would make the garage an '
            'upgrade treadmill',
      );
    });

    test('every car faster than the starter gives something up for it', () {
      // "A faster car should be harder to place, not strictly better": the
      // closing-speed exposure of a high top speed is designed in (fast
      // cars cross the 110 px/s crash threshold that slow cars scrape
      // under), and on top of that the stat sheet itself must show a
      // weakness against the starter.
      final starter = statsOf(VehicleSprites.defaultVehicleId);
      for (final vehicle in VehicleCatalog.vehicles) {
        if (vehicle.stats.topSpeed <= starter.topSpeed) continue;
        final paidWith = _axes
            .where((axis) => axis.aBeatsB(starter, vehicle.stats))
            .map((axis) => axis.name)
            .toList();
        expect(
          paidWith,
          isNotEmpty,
          reason: '${vehicle.name} is faster than the starter yet loses to '
              'it nowhere — that speed was free',
        );
      }
    });

    test('the spreads are wide enough to feel without the art', () {
      final speeds = VehicleCatalog.vehicles
          .map((v) => v.stats.topSpeed)
          .toList()
        ..sort();
      expect(speeds.last / speeds.first, greaterThanOrEqualTo(1.2),
          reason: 'slowest vs fastest top speed must be a felt difference');

      final steering = VehicleCatalog.vehicles
          .map((v) => v.stats.steeringSpeed)
          .toList()
        ..sort();
      expect(steering.last / steering.first, greaterThanOrEqualTo(1.25),
          reason: 'laziest vs sharpest steering must be a felt difference');

      final areas =
          VehicleCatalog.vehicles.map((v) => v.stats.bodyArea).toList()
            ..sort();
      expect(areas.last / areas.first, greaterThanOrEqualTo(1.5),
          reason: 'the biggest body must be a genuinely bigger target than '
              'the smallest');
    });

    test('every stat stays in playable bounds', () {
      for (final vehicle in VehicleCatalog.vehicles) {
        final s = vehicle.stats;
        expect(s.topSpeed, greaterThanOrEqualTo(120),
            reason: '${vehicle.id} must not be unplayably slow');
        expect(s.topSpeed, lessThanOrEqualTo(200),
            reason: '${vehicle.id} must stay under the head-on closing '
                'speeds the crash tuning is written against');
        expect(s.acceleration, inInclusiveRange(300, 600), reason: vehicle.id);
        expect(s.steeringSpeed, inInclusiveRange(200, 400), reason: vehicle.id);
        // Bodies must fit the 200 px road with room to pass, and stay in
        // the size class of the traffic the player weaves between.
        expect(s.width, inInclusiveRange(30, 50), reason: vehicle.id);
        expect(s.height, inInclusiveRange(45, 80), reason: vehicle.id);
      }
    });

    test('statsFor resolves every catalog id', () {
      for (final vehicle in VehicleCatalog.vehicles) {
        expect(VehicleCatalog.statsFor(vehicle.id), same(vehicle.stats));
      }
    });

    test('unknown ids fall back to the starter cab handling', () {
      // Mirrors the sprite fallback: an old save naming a removed car must
      // not drive differently from the default taxi.
      final starter = statsOf(VehicleSprites.defaultVehicleId);
      expect(VehicleCatalog.statsFor('sport_taxi'), same(starter));
      expect(VehicleCatalog.statsFor(null), same(starter));
    });
  });

  group('two cars feel different, art aside (issue #9)', () {
    // The movement path is pure with respect to the game instance: update()
    // reads only the resolved stats and the static road constants, so bare
    // components can be stepped deterministically without mounting.
    PlayerVehicle carOf(String id) => PlayerVehicle(
          startPosition: Vector2(TaxiGame.roadCenterX, 0),
          vehicleId: id,
        );

    test('the racer outruns the compact at full throttle', () {
      final racer = carOf('sports_black');
      final compact = carOf('compact_red');

      for (var i = 0; i < 60; i++) {
        racer.startAccelerating();
        compact.startAccelerating();
        racer.update(1 / 60);
        compact.update(1 / 60);
      }

      // Each holds its own top speed, and they are not the same number.
      expect(-racer.velocity.y, closeTo(statsOf('sports_black').topSpeed, 0.5));
      expect(
          -compact.velocity.y, closeTo(statsOf('compact_red').topSpeed, 0.5));
      // A second of flat throttle leaves the racer far up the road.
      expect(compact.position.y - racer.position.y, greaterThan(20));
    });

    test('the minivan launches harder than the executive', () {
      final minivan = carOf('minivan_gray');
      final executive = carOf('luxury_white');

      for (var i = 0; i < 15; i++) {
        minivan.startAccelerating();
        executive.startAccelerating();
        minivan.update(1 / 60);
        executive.update(1 / 60);
      }

      // 0.25 s in, off the line: the minivan's stronger throttle shows
      // before either car is anywhere near its top speed.
      expect(-minivan.velocity.y, closeTo(480 * 0.25, 0.5));
      expect(-executive.velocity.y, closeTo(370 * 0.25, 0.5));
      expect(-minivan.velocity.y, greaterThan(-executive.velocity.y));
    });

    test('the compact steers in harder than the starter cab', () {
      final compact = carOf('compact_red');
      final starter = carOf('taxi_yellow');

      compact.setSteering(1);
      starter.setSteering(1);
      compact.update(1 / 60);
      starter.update(1 / 60);

      // Full lock sets lateral velocity straight from the stats.
      expect(compact.velocity.x, closeTo(345, 0.001));
      expect(starter.velocity.x, closeTo(300, 0.001));

      for (var i = 0; i < 11; i++) {
        compact.update(1 / 60);
        starter.update(1 / 60);
      }

      // 0.2 s of full lock: the compact has covered visibly more road, and
      // neither car has yet met the road-edge clamp.
      expect(compact.position.x - TaxiGame.roadCenterX,
          greaterThan(starter.position.x - TaxiGame.roadCenterX));
      expect(starter.position.x, lessThan(280));
    });

    test('an unknown vehicle id drives like the starter cab', () {
      final mystery = PlayerVehicle(
        startPosition: Vector2(TaxiGame.roadCenterX, 0),
        vehicleId: 'sport_taxi',
      );

      expect(mystery.stats, same(statsOf(VehicleSprites.defaultVehicleId)));
      mystery.startAccelerating();
      mystery.setSteering(1);
      mystery.update(1 / 60);
      expect(-mystery.velocity.y, closeTo(400 / 60, 0.5));
      expect(mystery.velocity.x, closeTo(300, 0.001));
    });
  });

  group('garage choice reaches the road (issue #9)', () {
    late GameStateService gameState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      gameState = GameStateService(storage);
      await gameState.loadSaveData();
      gameState.unlockVehicle('minivan_gray', 0);
      gameState.selectVehicle('minivan_gray');
    });

    test('vehicleSize is one shared vector, not a per-read allocation '
        '(issue #257)', () {
      final car = PlayerVehicle(
        startPosition: Vector2(TaxiGame.roadCenterX, 0),
        vehicleId: 'minivan_gray',
      );
      expect(identical(car.vehicleSize, car.vehicleSize), isTrue,
          reason: 'every read must share the one cached body vector');
      expect(car.vehicleSize, Vector2(48, 72));
    });

    test('the equipped car is the car whose stats are driven', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));

      expect(gameState.selectedVehicle, 'minivan_gray');
      expect(game.player.vehicleId, 'minivan_gray');
      expect(game.player.stats, same(statsOf('minivan_gray')));

      // Full lock sets the minivan's own lateral speed, not the taxi's.
      game.player.setSteering(1);
      game.update(1 / 60);
      expect(game.player.velocity.x, closeTo(255, 0.001));

      // And its bigger body lands in collision space: the hitbox derives
      // from the logical body (never the sprite), so the size stat is a
      // real target the player feels, not just a number on the card.
      expect(game.player.vehicleSize, Vector2(48, 72));
      final hitbox =
          game.player.children.whereType<RectangleHitbox>().single;
      expect(hitbox.size, Vector2(48, 72) * CollisionRules.playerHitboxScale);
      // At hitbox scale the minivan is over 8 px wider than the compact —
      // the difference between threading a gap and clipping one.
      expect(hitbox.size.x, greaterThan(34 * CollisionRules.playerHitboxScale + 8));
    });
  });
}
