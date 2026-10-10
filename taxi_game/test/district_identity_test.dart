import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/background.dart';
import 'package:taxi_game/game/components/district_palette.dart';
import 'package:taxi_game/game/components/road_segment.dart';
import 'package:taxi_game/game/systems/run_environment.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// District identity (issue #280): each road profile paints its own
/// silhouette, landmark, and palette, all derived from the profile the
/// environment already rolls — so these probes pin pixels and shapes at
/// the golden seed without a new draw in the seeded stream.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Background> loadedBackground(RoadProfile profile) async {
    final background = Background()..profile = profile;
    await background.onLoad();
    return background;
  }

  Future<Uint8List> renderBackground(
      Background background, double darkness) async {
    background.darkness = darkness;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    background.render(canvas);
    final image = await recorder.endRecording().toImage(400, 800);
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
  }

  int red(Uint8List pixels, int x, int y) => pixels[(y * 400 + x) * 4];

  /// The byte the palette colour lays down in one channel (Color's
  /// components are 0..1 doubles since the wide-gamut migration).
  int byteOf(double component) => (component * 255).round();

  group('the skyline, landmark, and palette are the district', () {
    test('silhouettes and landmarks differ per district', () async {
      final standard = await loadedBackground(RoadProfile.standard);
      final narrow = await loadedBackground(RoadProfile.narrow);
      final avenue = await loadedBackground(RoadProfile.avenue);

      // Midtown's ten blocks, Old Town's fourteen rowhouses, the avenue's
      // eight setback towers.
      expect(standard.skylineBounds, hasLength(10));
      expect(narrow.skylineBounds, hasLength(14));
      expect(avenue.skylineBounds, hasLength(8));

      // A different roofline, not a recolour: the first left building's
      // bounds are nothing like each other.
      expect(standard.skylineBounds.first,
          const Rect.fromLTWH(10, 0, 60, 150));
      expect(narrow.skylineBounds.first.top, greaterThan(0),
          reason: 'Old Town opens with a gable under the view top');
      expect(avenue.skylineBounds.first,
          isNot(standard.skylineBounds.first));

      // One landmark each, in its own place.
      expect(standard.landmarkBounds.single,
          const Rect.fromLTWH(22, 318, 38, 42),
          reason: 'the water tower stands on the third left block');
      expect(narrow.landmarkBounds.single,
          const Rect.fromLTWH(18, 210, 30, 280),
          reason: 'the clock tower rises above the rowhouses');
      expect(avenue.landmarkBounds.single,
          const Rect.fromLTWH(336, 320, 48, 180),
          reason: 'the monument stands on the avenue');
    });

    test('each district paints its own pixels at a fixed frame', () async {
      final standard =
          await renderBackground(await loadedBackground(RoadProfile.standard), 0);
      final narrow =
          await renderBackground(await loadedBackground(RoadProfile.narrow), 0);
      final avenue =
          await renderBackground(await loadedBackground(RoadProfile.avenue), 0);

      // The whole skyline is a different picture, district to district.
      expect(standard, isNot(equals(narrow)));
      expect(narrow, isNot(equals(avenue)));
      expect(standard, isNot(equals(avenue)));

      // Probes, per district: the roofline and the landmark carry the
      // building and landmark colours the palette names.
      expect(red(standard, 40, 40),
          byteOf(DistrictPalette.of(RoadProfile.standard).building.r),
          reason: 'Midtown block at noon');
      expect(red(standard, 41, 342),
          byteOf(DistrictPalette.of(RoadProfile.standard).landmark.r),
          reason: 'the water tower tank at noon');
      expect(red(narrow, 34, 130),
          byteOf(DistrictPalette.of(RoadProfile.narrow).building.r),
          reason: 'a gable above a rowhouse body');
      expect(red(narrow, 33, 300),
          byteOf(DistrictPalette.of(RoadProfile.narrow).landmark.r),
          reason: 'the clock tower shaft');
      expect(red(avenue, 40, 30),
          byteOf(DistrictPalette.of(RoadProfile.avenue).building.r),
          reason: 'a tower setback at noon');
      expect(red(avenue, 360, 400),
          byteOf(DistrictPalette.of(RoadProfile.avenue).landmark.r),
          reason: 'the monument shaft');
    });
  });

  group('the street wears its district palette', () {
    Future<Uint8List> roadPixels(
        RunEnvironment env, double topDistance) async {
      final segment = RoadSegment(
        position: Vector2(RunEnvironment.roadCenterX, -topDistance),
        length: 800,
        environment: env,
      );
      await segment.onLoad();
      final recorder = ui.PictureRecorder();
      // The box's left edge at pixel x 100 and the chunk's top at row 0 —
      // the same conversion endless_road_alignment_test uses.
      final canvas = ui.Canvas(recorder)..translate(100, 0);
      segment.render(canvas);
      final image = await recorder.endRecording().toImage(400, 800);
      return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
    }

    void expectRgb(Uint8List pixels, double worldX, double worldY, Color color,
        String what) {
      final o = (worldY.round() * 400 + worldX.round()) * 4;
      expect(pixels[o], byteOf(color.r), reason: '$what red');
      expect(pixels[o + 1], byteOf(color.g), reason: '$what green');
      expect(pixels[o + 2], byteOf(color.b), reason: '$what blue');
    }

    test('surface, kerb, and junction differ per district at a fixed seed',
        () async {
      final env = RunEnvironment(seed: 0xC0FFEE);
      // Settled chunks, clear of tapers: seed 0xC0FFEE's pinned segment
      // sequence puts standard at 9, narrow at 4, avenue at 10
      // (golden_seeds_test).
      const standardTop = 39200.0; // segment 9: 36,000-40,000
      const narrowTop = 17600.0; // segment 4: 16,000-20,000
      const avenueTop = 42400.0; // segment 10: 40,000-44,000
      const junctionTop = 45600.0; // segment 11: narrow, junction at 45,000

      // Exact colours need dry stretches; the probe distances below are
      // dry on this seed (the golden weather sequence).
      for (final d in const [39000.0, 17400.0, 42200.0, 45000.0]) {
        expect(env.rainIntensityAt(d), 0, reason: 'dry at $d');
      }

      final standard = await roadPixels(env, standardTop);
      final narrow = await roadPixels(env, narrowTop);
      final avenue = await roadPixels(env, avenueTop);
      final junction = await roadPixels(env, junctionTop);

      // Probe a quarter lane in from each road's left kerb, clear of lane
      // boundaries and the centre dash, and the kerb 15 px outside it.
      void probe(Uint8List pixels, double top, RoadProfile profile) {
        final road = env.roadAt(top - 200);
        expect(road.profile, profile, reason: 'probe road at $top');
        final palette = DistrictPalette.of(profile);
        expectRgb(pixels, road.leftX + road.width * 0.25, 200, palette.surface,
            '${profile.districtName} surface');
        expectRgb(pixels, road.leftX - 15, 200, palette.sidewalk,
            '${profile.districtName} kerb');
      }

      probe(standard, standardTop, RoadProfile.standard);
      probe(narrow, narrowTop, RoadProfile.narrow);
      probe(avenue, avenueTop, RoadProfile.avenue);

      // The classic street is byte-for-byte the pre-#280 one.
      expectRgb(standard, 150, 200, const Color(0xFF404040), 'asphalt');
      expectRgb(standard, 85, 200, const Color(0xFFBDBDBD), 'kerb');

      // The junction wears the district it stands in: 45,000 sits in
      // narrow segment 11, whose cross-street asphalt is warm.
      expectRgb(junction, 150, 600,
          DistrictPalette.of(RoadProfile.narrow).intersection,
          'old-town junction');
    });
  });

  group('the sky follows the taxi into each district', () {
    test('an endless run sets the background district from the road', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final gameState = GameStateService(storage);
      await gameState.loadSaveData();

      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: 0xC0FFEE,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());
      game.onGameResize(Vector2(400, 800));
      await game.onLoad();
      // ignore: invalid_use_of_internal_member
      game.mount();
      await game.ready();

      final background =
          game.camera.backdrop.children.whereType<Background>().first;

      // The calm open is Midtown.
      game.update(1 / 60);
      expect(background.profile, RoadProfile.standard);
      expect(background.profile.districtName, 'Midtown');

      // Drive into Old Town — seed 0xC0FFEE's segment 4.
      game.player.position = Vector2(200, -17400);
      game.update(1 / 60);
      expect(background.profile, RoadProfile.narrow);
      expect(background.profile.districtName, 'Old Town');

      // And onto Grand Avenue — segment 10.
      game.player.position = Vector2(200, -42200);
      game.update(1 / 60);
      expect(background.profile, RoadProfile.avenue);
      expect(background.profile.districtName, 'Grand Avenue');
    });
  });
}
