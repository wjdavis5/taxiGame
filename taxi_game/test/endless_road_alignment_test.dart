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

  // Issue #82: the junction band was the one horizontal draw the #33
  // origin fix never reached — `Rect.fromLTRB(-centerX, …, centerX, …)`
  // wrote centre-line coordinates as box-local, so every cross street's
  // asphalt landed at world −100..300 instead of spanning the 400 px
  // view, 100 px left of the junction the world knows, and the street's
  // right kerb, sidewalk, and edge ran straight through the
  // intersection's right half. The below-band crossing compounded it:
  // its stack grows upward from a base only 10 px under the band, so its
  // second and third bars climbed back over the asphalt. These probes
  // pin the band to the full fixed-resolution view and the whole stack
  // below it, at the first junction (seed 7: dry, standard width — kerbs
  // at world x 100/300).
  test('junction bands span the view, not 100 px left of it (issue #82)',
      () async {
    final env = RunEnvironment(seed: 7);
    // Exact-colour probes need the stretch dry; 8827 is where the
    // relocated below-band bars paint (their white blends over asphalt).
    expect(env.rainIntensityAt(9000), 0, reason: 'a dry junction stretch');
    expect(env.rainIntensityAt(8827), 0, reason: 'and below it');

    // Top edge pinned at true distance 9300: the band (8840..9160) and
    // both crosswalk stacks land in frame with margin.
    const topDistance = 9300.0;
    final segment = RoadSegment(
      position: Vector2(RunEnvironment.roadCenterX, -topDistance),
      length: 800,
      environment: env,
    );
    await segment.onLoad();

    // Render with the box's left edge at pixel x 100 and the chunk's top
    // edge at pixel row 0 — the same left-edge conversion the world
    // transform applies, with the chunk's deep negative world y brought
    // into frame (a uniform shift changes no relative geometry). Pixel y
    // is world y + 9300; world x maps to pixel x directly.
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.translate(100, 0);
    segment.render(canvas);
    final image = await recorder.endRecording().toImage(400, 700);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = bytes!.buffer.asUint8List();

    void expectWorldRgb(double worldX, double worldY, int r, int g, int b,
        String what) {
      final o = ((worldY + 9300).round() * 400 + worldX.round()) * 4;
      expect(data[o], closeTo(r, 3), reason: what);
      expect(data[o + 1], closeTo(g, 3), reason: what);
      expect(data[o + 2], closeTo(b, 3), reason: what);
    }

    // Asphalt across the view's whole width, at the band's mid-height.
    // Both pixels were bare canvas with the 100-px-left band (it stopped
    // at world x 300, short of the right sidewalk never mind the edge).
    expectWorldRgb(350, -9000, 0x4A, 0x4A, 0x4A,
        'the cross street reaches the view\'s right quarter');
    expectWorldRgb(
        395, -9000, 0x4A, 0x4A, 0x4A, 'and its right margin');
    // Across the right kerb: the white edge line used to run straight
    // through the junction; now the band buries it.
    expectWorldRgb(
        300, -8980, 0x4A, 0x4A, 0x4A, 'the band covers the right kerb');
    // Where the below-band crossing's second and third bars climbed back
    // over the asphalt, only asphalt remains.
    expectWorldRgb(200, -8841, 0x4A, 0x4A, 0x4A,
        'the old second bar\'s row is band asphalt');
    expectWorldRgb(200, -8849, 0x4A, 0x4A, 0x4A,
        'the old third bar\'s row is band asphalt');
    // The relocated stack still paints, below the band: 0.85 white over
    // dry asphalt ≈ 226. Probed off the centre line (x = 200 is exactly
    // where the standard road's dash runs) and inside the bars' span.
    expectWorldRgb(260, -8827, 226, 226, 226,
        'the top relocated bar paints below the band');
    expectWorldRgb(260, -8805, 226, 226, 226,
        'and the bottom relocated bar');
  });
}
