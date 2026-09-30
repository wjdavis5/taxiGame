import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/data/vehicle_catalog.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/vehicle_sprites.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// Mounts [game] headlessly (the pattern flame_test uses) so component
/// `onLoad` hooks run, then returns it.
Future<TaxiGame> mountGame(TaxiGame game) async {
  game.onGameResize(Vector2(400, 800));
  await game.onLoad();
  await game.ready();
  return game;
}

/// Vehicles load their sprite asynchronously inside [onLoad] and only then
/// queue the sprite child, so keep settling the tree until the child shows up.
Future<void> settleSprite(PositionComponent vehicle, TaxiGame game) async {
  for (var i = 0; i < 500; i++) {
    await game.ready();
    if (vehicle.children.whereType<SpriteComponent>().isNotEmpty) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('vehicle never materialized its sprite child');
}

SpriteComponent spriteOf(PositionComponent vehicle) =>
    vehicle.children.whereType<SpriteComponent>().single;

RectangleHitbox hitboxOf(PositionComponent vehicle) =>
    vehicle.children.whereType<RectangleHitbox>().single;

/// Decodes [image] to straight RGBA bytes — one r, g, b, a quad per pixel.
Future<Uint8List> rgbaOf(ui.Image image) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) fail('could not read pixels back from a sprite');
  return bytes.buffer.asUint8List();
}

/// Histogram of the sprite's fully-opaque pixels, keyed r<<16 | g<<8 | b.
/// The shipped art is flat-shaded (a handful of exact palette steps), so
/// exact-match counting is enough. Partial-alpha edge pixels are skipped:
/// anti-aliased fringes differ between premultiplied and straight encodings
/// and would blur the steps.
Map<int, int> opaqueHistogram(Uint8List rgba) {
  final counts = <int, int>{};
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] != 0xFF) continue;
    final key = rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2];
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

/// The most frequent opaque colour — on these sprites the brightest body
/// step is the biggest single area, so the mode *is* the body colour.
int dominantBodyColour(Uint8List rgba) {
  final counts = opaqueHistogram(rgba);
  return counts.entries
      .reduce((a, b) => a.value >= b.value ? a : b)
      .key;
}

/// Perceptual luminance of a packed r<<16 | g<<8 | b colour.
double luminanceOf(int packed) =>
    0.2126 * ((packed >> 16) & 0xFF) +
    0.7152 * ((packed >> 8) & 0xFF) +
    0.0722 * (packed & 0xFF);

/// CIE76 colour difference between two packed sRGB colours: sRGB → linear
/// → XYZ (D65) → Lab, then Euclidean distance. ΔE below ~20 reads as the
/// same colour family, which is exactly the collision these guards look
/// for — a traffic vehicle the player could mistake for their own cab.
double deltaE76(int packedA, int packedB) {
  List<double> labOf(int packed) {
    // sRGB transfer curve, then the D65 matrix the Lab white point matches.
    double lin(int channel8) {
      final c = channel8 / 255.0;
      return c <= 0.04045
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    final r = lin((packed >> 16) & 0xFF);
    final g = lin((packed >> 8) & 0xFF);
    final b = lin(packed & 0xFF);
    final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
    final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
    double f(double t) =>
        t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
    return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))];
  }

  final a = labOf(packedA);
  final b = labOf(packedB);
  var sum = 0.0;
  for (var i = 0; i < 3; i++) {
    sum += math.pow(a[i] - b[i], 2).toDouble();
  }
  return math.sqrt(sum);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  group('PlayerVehicle', () {
    test('renders its sprite instead of canvas primitives', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));
      final player = game.player;
      await settleSprite(player, game);

      final spriteComponent = spriteOf(player);
      expect(spriteComponent.sprite, isNotNull);
      // taxi_yellow.png decodes to an 87x131 image — top-down art whose
      // canvas carries the 40x60 logical box's proportions.
      expect(spriteComponent.sprite!.image.width, 87);
      expect(spriteComponent.sprite!.image.height, 131);
      // The art faces up the screen already (issue #47), the direction the
      // taxi drives, so the child renders unrotated.
      expect(spriteComponent.angle, closeTo(0, 1e-9));
    });

    test('hitbox stays tied to the logical box, not the sprite', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));
      final player = game.player;
      await settleSprite(player, game);

      // 75% of the logical box (issue #6 tightened it in the player's
      // favour), still centred.
      expect(hitboxOf(player).size, Vector2(40, 60) * 0.75);
      expect(
        hitboxOf(player).position,
        Vector2(40, 60) * (1 - 0.75) / 2,
      );
      // The sprite art is 87x131 — over twice the 40x60 hitbox footprint's
      // density and only proportioned like it — proving collision geometry
      // follows the logical box, never the art's pixel size.
      expect(spriteOf(player).sprite!.srcSize, Vector2(87, 131));
    });

    test('selectedVehicle drives which sprite renders', () async {
      gameState.unlockVehicle('sedan_blue', 0);
      gameState.selectVehicle('sedan_blue');

      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));
      await settleSprite(game.player, game);

      expect(gameState.selectedVehicle, 'sedan_blue');
      expect(game.player.vehicleId, 'sedan_blue');

      // sedan_blue.png decodes to an 85x131 image — a different sprite
      // than the default taxi (87x131), so what appears on screen changed.
      final rendered = spriteOf(game.player).sprite!;
      expect(rendered.image.width, 85);
      expect(rendered.image.height, 131);
    });

    test('an unknown vehicle id falls back to the default taxi', () async {
      gameState.unlockVehicle('sport_taxi', 0);
      gameState.selectVehicle('sport_taxi');

      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));
      await settleSprite(game.player, game);

      // The id no longer maps to a shipped sprite; rendering must not break.
      final rendered = spriteOf(game.player).sprite!;
      expect(rendered.image.width, 87);
      expect(rendered.image.height, 131);
    });
  });

  group('TrafficVehicle', () {
    test('renders a sprite with the hitbox decoupled from the art', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));

      final bus = TrafficVehicle(
        position: Vector2(260, 0),
        vehicleType: TrafficVehicleType.bus,
        baseSpeed: 100,
        // Drives down the screen: oncoming traffic.
        path: [Vector2(260, 100), Vector2(260, 200)],
      );
      game.world.add(bus);
      await settleSprite(bus, game);

      final spriteComponent = spriteOf(bus);
      expect(spriteComponent.sprite, isNotNull);
      // The top-down art (issue #47) needs no rotation of its own; the
      // vehicle's own π flip below is what faces oncoming traffic down.
      expect(spriteComponent.angle, closeTo(0, 1e-9));
      // Oncoming traffic still faces the player...
      expect(bus.angle, math.pi);
      // ...while the hitbox keeps the logical footprint (80% of 50x100,
      // tightened in the player's favour by issue #6), independent of the
      // sprite art.
      expect(hitboxOf(bus).size, Vector2(50, 100) * 0.80);
    });

    test('same-direction traffic faces up the screen', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));

      final car = TrafficVehicle(
        position: Vector2(260, 0),
        vehicleType: TrafficVehicleType.sedan,
        baseSpeed: 100,
        // Drives up the screen, same direction as the player.
        path: [Vector2(260, -100), Vector2(260, -200)],
      );
      game.world.add(car);
      await settleSprite(car, game);

      expect(car.angle, 0);
      expect(spriteOf(car).sprite, isNotNull);
    });

    test('a spawner-shaped path still flips oncoming traffic to face the '
        'player (issue #72)', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));

      // Exactly what TrafficSpawner._createStraightPath builds: the
      // list starts with the spawn point itself, and the waypoints run
      // off in the travel direction. The first waypoint sits on top of
      // the vehicle, so the initial velocity is zero — and the flip,
      // when it was judged from that velocity, never fired: every
      // spawned oncoming car drove down the road facing up it,
      // tail-first.
      TrafficVehicle spawnerVehicle(Vector2 spawn,
          {required bool oncoming, required double speed}) {
        final step = oncoming ? 500.0 : -3000.0;
        return TrafficVehicle(
          position: Vector2(spawn.x, spawn.y),
          vehicleType: TrafficVehicleType.sedan,
          baseSpeed: speed,
          path: [
            spawn,
            for (var i = 1; i <= 3; i++)
              Vector2(spawn.x, spawn.y + step * i),
          ],
        );
      }

      final oncoming =
          spawnerVehicle(Vector2(150, -500), oncoming: true, speed: 120);
      game.world.add(oncoming);
      await settleSprite(oncoming, game);
      expect(oncoming.angle, math.pi,
          reason: 'an oncoming car faces the player it drives toward, '
              'however its path is shaped');

      final sameDirection =
          spawnerVehicle(Vector2(250, -500), oncoming: false, speed: 60);
      game.world.add(sameDirection);
      await settleSprite(sameDirection, game);
      expect(sameDirection.angle, 0,
          reason: 'the same path shape heading up-screen keeps facing '
              'up-screen');
    });
  });

  group('Shipped sprite art', () {
    // Issue #47 replaced side-view art (wider than tall, drawn lying on
    // its side) with top-down art facing up the screen. These guards keep
    // any future art swap honest: top-down shape, and a canvas that
    // carries the logical box's proportions so the unrotated stretch
    // render stays undistorted.
    test('every sprite is top-down art in its vehicle box proportions',
        () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));

      Future<void> expectTopDown(String path, double boxAspect) async {
        final image = await game.images.load(path);
        expect(image.height, greaterThan(image.width),
            reason: '$path must be taller than wide (top-down art)');
        expect(image.width / image.height, closeTo(boxAspect, 0.01),
            reason: '$path canvas must carry its logical box proportions');
      }

      for (final vehicle in VehicleCatalog.vehicles) {
        await expectTopDown(
          VehicleSprites.playerSpritePath(vehicle.id),
          vehicle.stats.width / vehicle.stats.height,
        );
      }
      for (final type in TrafficVehicleType.values) {
        await expectTopDown(
          VehicleSprites.trafficSpritePath(type),
          type.size.x / type.size.y,
        );
      }
    });
  });

  // Issue #59: the traffic bus shipped wearing the player taxi's exact
  // yellow ramp (ΔE 0), so on the road it read as a second player cab —
  // and its elongated sprite carried a cloned tail outline mid-body. In a
  // game about steering one taxi through traffic, the player's car must be
  // unmistakable, so both defects get their own guard here.
  group('Traffic art distinctness (issue #59)', () {
    test("no traffic sprite's dominant body colour is within ΔE 20 of the "
        'player taxi', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));

      final taxi = dominantBodyColour(await rgbaOf(await game.images.load(
        VehicleSprites.playerSpritePath(VehicleSprites.defaultVehicleId),
      )));

      // Every PNG in the traffic folder, not just the five types
      // TrafficVehicleType maps to — anything dropped there renders on the
      // road beside the player sooner or later.
      final folder = Directory('assets/images/vehicles/traffic');
      final names = folder
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.endsWith('.png'))
          .toList()
        ..sort();
      expect(names, isNotEmpty);

      for (final name in names) {
        final sprite = await game.images.load('vehicles/traffic/$name');
        final distance = deltaE76(taxi, dominantBodyColour(await rgbaOf(sprite)));
        expect(distance, greaterThan(20),
            reason: 'traffic/$name reads as the player taxi (dominant body '
                'colour within ΔE 20 of it)');
      }
    });

    test('bus art keeps a single continuous outline — no cloned tail seam',
        () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));
      final image = await game.images.load(
        VehicleSprites.trafficSpritePath(TrafficVehicleType.bus),
      );
      final rgba = await rgbaOf(image);

      // The body outline step is the darkest colour covering a real share
      // of the body — darker than every body/shade step, unlike glass.
      final counts = opaqueHistogram(rgba);
      final total = counts.values.reduce((a, b) => a + b);
      final outline = counts.entries
          .where((e) => e.value >= total * 0.03)
          .reduce((a, b) => luminanceOf(a.key) <= luminanceOf(b.key) ? a : b)
          .key;

      // Rows where outline pixels outnumber all other opaque pixels form
      // the nose cap at the top and the closed tail outline at the bottom.
      // A third such run — or a tail outline that starts mid-body — is a
      // duplicated band, the seam the old elongation shipped with.
      final runs = <List<int>>[];
      for (var y = 0; y < image.height; y++) {
        var opaque = 0;
        var outlinePixels = 0;
        for (var x = 0; x < image.width; x++) {
          final i = (y * image.width + x) * 4;
          if (rgba[i + 3] != 0xFF) continue;
          opaque++;
          if ((rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2]) == outline) {
            outlinePixels++;
          }
        }
        if (outlinePixels * 2 > opaque) {
          if (runs.isNotEmpty && runs.last[1] == y - 1) {
            runs.last[1] = y;
          } else {
            runs.add([y, y]);
          }
        }
      }

      expect(runs, hasLength(2),
          reason: 'only the nose cap and the tail outline should be '
              'outline-majority; extra runs are cloned-outline seams');
      expect(runs.first[0], lessThan(image.height * 0.1),
          reason: 'the first outline run must be the nose cap');
      expect(runs.last[0], greaterThan(image.height * 0.85),
          reason: 'the tail outline must close the art, not appear '
              'mid-body with body hanging below it');
    });
  });
}
