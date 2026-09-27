import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/components/road_segment.dart';
import 'package:taxi_game/game/systems/run_environment.dart';

/// The endless road must render where the game logic says it is (issue
/// #33).
///
/// The component is anchored top-centre at x = roadCenterX over a 200 px
/// box, so its local origin is the box's top-LEFT corner (world x 100) —
/// not the centre line. The living-street renderer computed each row's
/// local x as `road.leftX - roadCenterX`, drawing the whole street exactly
/// half a road-width left of where the taxi, the fare zones, and the
/// road clamp live: the TestFlight screenshot showed asphalt spanning
/// world x 0..200 with the kerb seam at 200 while the taxi drove on what
/// the clamp calls the road. These probes pin asphalt, kerbs, and
/// sidewalks to the coordinates [RunEnvironment.roadAt] actually returns.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('endless road rows and crosswalks render at their true world x', () async {
    final env = RunEnvironment(seed: 7);
    const probeLy = 20.0;
    // No junction and no rain at this distance: the probes below assert
    // exact dry-weather colours, and the seed must give us that calm.
    const distance = 40.0 - probeLy;
    expect(env.rainIntensityAt(distance), 0,
        reason: 'pick a seed whose opening stretch is dry');
    final road = env.roadAt(distance);

    final segment = RoadSegment(
      position: Vector2(RunEnvironment.roadCenterX, -40),
      length: 800,
      environment: env,
    );
    await segment.onLoad();

    // The segment sits in the world with its local origin at
    // (roadCenterX - 100, -40); render it there. World x maps to pixel x
    // directly, world y -40 maps to pixel y 40.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(100, 40);
    segment.render(canvas);
    final image = await recorder.endRecording().toImage(400, 480);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = bytes!.buffer.asUint8List();

    // World coordinates, straight onto the raw RGBA bytes.
    void expectWorldRgb(double worldX, double worldY, int r, int g, int b,
        String what) {
      final o = ((worldY + 80).round() * 400 + worldX.round()) * 4;
      expect(data[o], closeTo(r, 3), reason: what);
      expect(data[o + 1], closeTo(g, 3), reason: what);
      expect(data[o + 2], closeTo(b, 3), reason: what);
    }

    // Asphalt a quarter lane in from the left kerb — clear of lane
    // boundaries and the centre line's dashes.
    expectWorldRgb(road.leftX + road.width * 0.25, -20, 0x40, 0x40, 0x40,
        'asphalt renders inside the road the logic clamps to');
    // Sidewalk strips just outside both kerbs (the dry colour).
    expectWorldRgb(road.leftX - 15, -20, 0xBD, 0xBD, 0xBD,
        'left sidewalk renders just outside the left kerb');
    expectWorldRgb(road.leftX + road.width + 15, -20, 0xBD, 0xBD, 0xBD,
        'right sidewalk renders just outside the right kerb');
    // The regression probe: with the old `road.leftX - roadCenterX` math
    // this pixel was asphalt (the street drew half a width left). Clear
    // of the correct sidewalk, it must be bare canvas.
    expectWorldRgb(
        road.leftX - 90 < 5 ? 5 : road.leftX - 90, -20, 0, 0, 0,
        'no asphalt may render left of the street the logic knows');
  });
}
