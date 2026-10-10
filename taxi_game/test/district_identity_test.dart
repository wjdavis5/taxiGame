import 'dart:convert';
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
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// District identity (issue #280): each road profile paints its own
/// silhouette, landmark, and palette, all derived from the profile the
/// environment already rolls — so these probes pin pixels and shapes at
/// the golden seed without a new draw in the seeded stream.
///
/// The palette probes assert literal byte values, never a re-read of the
/// [DistrictPalette] lookup the renderer itself uses: a palette that
/// collapses into another district or two districts that swap must fail
/// here (review of PR #300).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// One pixel's RGB, against literal bytes.
  void expectPixel(
      Uint8List pixels, int x, int y, (int, int, int) rgb, String what) {
    final o = (y * 400 + x) * 4;
    expect(pixels[o], rgb.$1, reason: '$what red');
    expect(pixels[o + 1], rgb.$2, reason: '$what green');
    expect(pixels[o + 2], rgb.$3, reason: '$what blue');
  }

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

  group('the skyline, landmark, and palette are the district', () {
    test('the palettes are pinned literally and differ on every axis', () {
      // Literal values, not a re-read of the lookup the renderer uses.
      expect(DistrictPalette.of(RoadProfile.standard).surface,
          const Color(0xFF404040));
      expect(DistrictPalette.of(RoadProfile.narrow).surface,
          const Color(0xFF4A3E34));
      expect(DistrictPalette.of(RoadProfile.avenue).surface,
          const Color(0xFF3C4650));
      expect(DistrictPalette.of(RoadProfile.narrow).sidewalk,
          const Color(0xFFC4AE8E));
      expect(DistrictPalette.of(RoadProfile.avenue).sidewalk,
          const Color(0xFFC6CBD3));
      expect(DistrictPalette.of(RoadProfile.narrow).intersection,
          const Color(0xFF544639));
      expect(DistrictPalette.of(RoadProfile.avenue).intersection,
          const Color(0xFF46505A));
      expect(DistrictPalette.of(RoadProfile.narrow).building,
          const Color(0xFF8A5A44));
      expect(DistrictPalette.of(RoadProfile.avenue).building,
          const Color(0xFF8E97A3));
      expect(DistrictPalette.of(RoadProfile.narrow).landmark,
          const Color(0xFFB9A38C));
      expect(DistrictPalette.of(RoadProfile.avenue).landmark,
          const Color(0xFF6E7683));
      expect(DistrictPalette.of(RoadProfile.narrow).marking,
          const Color(0xFFE8D9A8));
      expect(DistrictPalette.of(RoadProfile.avenue).marking,
          const Color(0xFFF4F7FF));

      // Every axis is three distinct values, so a collapse into one
      // palette cannot pass unnoticed.
      final palettes = {
        for (final p in RoadProfile.values) p: DistrictPalette.of(p),
      };
      final axes = <String, List<Color>>{
        'surface': [for (final p in RoadProfile.values) palettes[p]!.surface],
        'sidewalk': [for (final p in RoadProfile.values) palettes[p]!.sidewalk],
        'marking': [for (final p in RoadProfile.values) palettes[p]!.marking],
        'intersection': [
          for (final p in RoadProfile.values) palettes[p]!.intersection,
        ],
        'building': [for (final p in RoadProfile.values) palettes[p]!.building],
        'landmark': [for (final p in RoadProfile.values) palettes[p]!.landmark],
      };
      for (final axis in axes.entries) {
        expect(axis.value.toSet(), hasLength(RoadProfile.values.length),
            reason: '${axis.key} must be a different colour per district');
      }
    });

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

      // Literal byte probes: the roofline and the landmark carry the
      // building and landmark colours the palette pins above.
      expectPixel(standard, 40, 40, (0x61, 0x61, 0x61), 'Midtown block');
      expectPixel(
          standard, 41, 342, (0x4E, 0x52, 0x59), 'the water tower tank');
      expectPixel(narrow, 34, 130, (0x8A, 0x5A, 0x44),
          'a gable above a rowhouse body');
      expectPixel(narrow, 33, 300, (0xB9, 0xA3, 0x8C), 'the clock tower shaft');
      expectPixel(avenue, 40, 30, (0x8E, 0x97, 0xA3), 'a tower setback');
      expectPixel(
          avenue, 360, 400, (0x6E, 0x76, 0x83), 'the monument shaft');
    });

    test('a mounted background rebuilds its skyline when the district changes',
        () async {
      // The live path (a run driving across a district line): the profile
      // is set before [Background.onLoad] nowhere here — it changes on an
      // already-mounted component, so only a render can rebuild.
      final background = Background();
      await background.onLoad();
      final midtown = await renderBackground(background, 0);
      expect(background.skylineBounds, hasLength(10),
          reason: 'Midtown until the road says otherwise');

      background.profile = RoadProfile.narrow;
      final oldTown = await renderBackground(background, 0);
      expect(background.skylineBounds, hasLength(14),
          reason: 'the switch rebuilds the skyline, not just the paint');
      expect(oldTown, isNot(equals(midtown)));
      expectPixel(oldTown, 34, 130, (0x8A, 0x5A, 0x44),
          'the Old Town gable after the switch');

      background.profile = RoadProfile.avenue;
      final avenue = await renderBackground(background, 0);
      expect(background.skylineBounds, hasLength(8));
      expect(avenue, isNot(equals(oldTown)));
      expectPixel(avenue, 360, 400, (0x6E, 0x76, 0x83),
          'the monument after the switch');
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

    test('surface, kerb, and junction are pinned literally per district',
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
      // The expected bytes are literals: a palette collapse or a swap
      // between districts must fail here, not move with the renderer.
      void probe(Uint8List pixels, double top, RoadProfile profile,
          (int, int, int) surface, (int, int, int) kerb) {
        final road = env.roadAt(top - 200);
        expect(road.profile, profile, reason: 'probe road at $top');
        expectPixel(pixels, (road.leftX + road.width * 0.25).round(), 200,
            surface, '${profile.districtName} surface');
        expectPixel(pixels, (road.leftX - 15).round(), 200, kerb,
            '${profile.districtName} kerb');
      }

      probe(standard, standardTop, RoadProfile.standard, (0x40, 0x40, 0x40),
          (0xBD, 0xBD, 0xBD));
      probe(narrow, narrowTop, RoadProfile.narrow, (0x4A, 0x3E, 0x34),
          (0xC4, 0xAE, 0x8E));
      probe(avenue, avenueTop, RoadProfile.avenue, (0x3C, 0x46, 0x50),
          (0xC6, 0xCB, 0xD3));

      // The junction wears the district it stands in: 45,000 sits in
      // narrow segment 11, whose cross-street asphalt is warm.
      expectPixel(junction, 150, 600, (0x54, 0x46, 0x39),
          'old-town junction');
    });

    test('a chunk crossing a district line paints both bands', () async {
      // The standard→narrow line at 16,000 (golden segment 4). Chunk 20
      // covers [15,600, 16,400) and straddles it: its recorded picture
      // carries two districts, so the band overpaint runs for real.
      final env = RunEnvironment(seed: 0xC0FFEE);
      const top = 16400.0;
      expect(env.roadAt(15960).profile, RoadProfile.standard);
      expect(env.roadAt(16000).profile, RoadProfile.narrow);
      expect(env.rainIntensityAt(top - 400), 0, reason: 'a dry stretch');

      final pixels = await roadPixels(env, top);

      // Below the line: Midtown's classic asphalt and kerb.
      final midtown = env.roadAt(15700);
      expectPixel(pixels, (midtown.leftX + midtown.width * 0.25).round(), 700,
          (0x40, 0x40, 0x40), 'Midtown surface below the line');
      expectPixel(pixels, (midtown.leftX - 15).round(), 700, (0xBD, 0xBD, 0xBD),
          'Midtown kerb below the line');

      // Above the line, in the same chunk: Old Town's warm asphalt and
      // sandstone.
      final oldTown = env.roadAt(16200);
      expectPixel(pixels, (oldTown.leftX + oldTown.width * 0.25).round(), 200,
          (0x4A, 0x3E, 0x34), 'Old Town surface above the line');
      expectPixel(pixels, (oldTown.leftX - 15).round(), 200, (0xC4, 0xAE, 0x8E),
          'Old Town kerb above the line');
    });
  });

  group('the sky follows the taxi into each district', () {
    Future<TaxiGame> mountGame(TaxiGame game) async {
      game.onGameResize(Vector2(400, 800));
      await game.onLoad();
      // ignore: invalid_use_of_internal_member
      game.mount();
      await game.ready();
      return game;
    }

    Future<GameStateService> freshGameState() async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final gameState = GameStateService(storage);
      await gameState.loadSaveData();
      return gameState;
    }

    test('an endless run sets the background district from the road', () async {
      final gameState = await freshGameState();
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: 0xC0FFEE,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());
      await mountGame(game);

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

    test('a level run keeps the classic Midtown sky', () async {
      // Level mode has no living road; the background must rest at the
      // standard district (taxi_game.dart's level resets), not carry the
      // last endless run's skyline onto the fixed street.
      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey:
            jsonEncode((SaveData.createDefault()..currentLevel = 1).toJson()),
      });
      final storage = StorageService();
      await storage.init();
      final gameState = GameStateService(storage);
      await gameState.loadSaveData();

      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      )
        ..overlays.addEntry('levelComplete', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());
      await mountGame(game);

      final background =
          game.camera.backdrop.children.whereType<Background>().first;
      game.update(1 / 60);
      expect(background.profile, RoadProfile.standard);
      expect(background.profile.districtName, 'Midtown');
    });
  });
}
