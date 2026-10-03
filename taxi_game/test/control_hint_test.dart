import 'dart:convert';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/fake_audio_platform.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';

/// The one-time stick-control hint (issue #37): a first game start on a
/// save that has never dismissed it teaches the invisible relative stick,
/// the first real stick touch dismisses it for good, and a reset re-arms
/// it — the same wipe convention as the run history.
///
/// The HUD polls the game on a repeating timer, so the widget tests pump
/// fixed durations — never pumpAndSettle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The hint pill's key, as [ControlHintOverlay] mounts it.
  final hintFinder = find.byKey(const ValueKey('controlHint'));

  /// A minimal valid save JSON, as an older build of the game wrote it —
  /// optionally carrying the hint flag for the saves that know it.
  Map<String, dynamic> seasonedSave({bool? controlHintDismissed}) => {
        'currentLevel': 4,
        'totalCoins': 30,
        'totalGems': 0,
        'unlockedVehicles': ['taxi_yellow'],
        'selectedVehicle': 'taxi_yellow',
        'achievements': <String, bool>{},
        'settings': Settings.createDefault().toJson(),
        if (controlHintDismissed != null)
          'controlHintDismissed': controlHintDismissed,
      };

  late GameStateService gameState;

  setUp(() async {
    installFakeAudioPlatform();
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  /// Pumps a live [GameScreen] on a fresh save — an endless shift when
  /// [endless], otherwise the tutorial ladder's first rung, whose camera
  /// follows the lead and parks the cab below centre (issue #177's mode).
  /// [tag] keys the screen so a second pump in the same test cannot
  /// reuse the first screen's state (the pumpNextSession convention).
  Future<TaxiGame> pumpGameScreen(WidgetTester tester,
      {bool endless = true, String tag = 'main'}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          Provider<AudioService>.value(value: AudioService()),
          Provider<HapticsService>.value(value: HapticsService()),
          Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        ],
        child: MaterialApp(
          key: ValueKey('app-${endless ? "endless" : "level"}-$tag'),
          home: GameScreen(
            key: ValueKey('screen-${endless ? "endless" : "level"}-$tag'),
            endlessSeed: endless ? 42 : null,
          ),
        ),
      ),
    );
    await tester.pump();

    // Wait for the run to go live for real. A fixed 100 ms real sleep
    // raced the level/asset load on a busy runner — the third test of a
    // back-to-back group lost it — so poll to the condition instead
    // (the audio tests' deadline idiom), interleaving real event-loop
    // time with fake-clock frames: the load runs on real futures, and
    // the game's own machinery ticks on pumps.
    final game = tester
        .widget<GameWidget<TaxiGame>>(find.byType(GameWidget<TaxiGame>))
        .game!;
    var waitedMs = 0;
    while (!(game.isGameActive && game.isPlayerReady) && waitedMs < 5000) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
      waitedMs += 50;
    }
    // The hint polls the game on a 100 ms timer until the cab exists —
    // give it the tick that lands the measured placement.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(game.isGameActive, isTrue,
        reason: 'the run must be live before any input');
    return game;
  }

  /// The cab's tail in screen px on a [surface]-sized screen: centre,
  /// plus the half-body the endless camera leaves below it, plus — in
  /// the ladder's levels — the whole camera lead the level camera parks
  /// the cab down by (issue #177). The fixed-resolution viewport's world
  /// scale, min(w/400, h/800), is the bank panel's idiom.
  double cabTailOnScreen(TaxiGame game, Size surface) {
    final scale = math.min(surface.width / 400, surface.height / 800);
    final lead = game.isEndless ? 0.0 : TaxiGame.levelCameraLead;
    return surface.height / 2 +
        (lead + game.player.stats.height / 2) * scale;
  }

  /// Pumps a follow-up [GameScreen] on [service] — the next session's
  /// first render. The screen is keyed so it cannot reuse the first
  /// session's state: a real next session constructs the screen anew,
  /// and only then is the hint decision made.
  Future<void> pumpNextSession(WidgetTester tester, GameStateService service,
      {int seed = 43}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: service),
          Provider<AudioService>.value(value: AudioService()),
          Provider<HapticsService>.value(value: HapticsService()),
          Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        ],
        child: MaterialApp(
          home: GameScreen(
            key: ValueKey('session-$seed'),
            endlessSeed: seed,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('a fresh save (issue #37)', () {
    testWidgets('the first game start shows the stick-control hint',
        (tester) async {
      await pumpGameScreen(tester);

      expect(hintFinder, findsOneWidget);
      expect(find.textContaining('Touch and hold the lower half'),
          findsOneWidget,
          reason: 'the hint names the invisible control in the stick\'s '
              'own terms');
    });

    testWidgets('the first real stick input dismisses it and drives the taxi',
        (tester) async {
      final game = await pumpGameScreen(tester);
      expect(hintFinder, findsOneWidget);

      // A real stick drag on the lower half: glide up-right past the rim.
      final gesture = await tester.startGesture(const Offset(400, 450));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(72, -144));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));

      expect(hintFinder, findsNothing,
          reason: 'the thumb landed where the hint said it would');
      expect(gameState.controlHintDismissed, isTrue);
      expect(game.player.throttleInput, greaterThan(0.8),
          reason: 'the dismissal came from a real input, not a timer');

      await gesture.up();
    });

    testWidgets('a tap on the hint itself dismisses it', (tester) async {
      await pumpGameScreen(tester);
      expect(hintFinder, findsOneWidget);

      // The hint sits inside the stick's touch region, so a tap on it is
      // a lower-half touch: down, up, no movement.
      final gesture =
          await tester.startGesture(tester.getCenter(hintFinder));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));

      expect(hintFinder, findsNothing);
      expect(gameState.controlHintDismissed, isTrue);
    });

    testWidgets('the dismissal persists — the next session renders no hint',
        (tester) async {
      await pumpGameScreen(tester);

      final gesture = await tester.startGesture(const Offset(400, 450));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, -160));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(hintFinder, findsNothing);

      // Flush the fire-and-forget save so the reload below reads the
      // on-device state a real device would already have.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );

      // Simulate an app restart: a brand-new service stack reading the
      // same on-device store.
      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();
      expect(reloaded.controlHintDismissed, isTrue);

      await pumpNextSession(tester, reloaded);
      expect(hintFinder, findsNothing,
          reason: 'the flag is set before the next session renders');
    });
  });

  group('parked below the cab (issue #177)', () {
    // One body, four screens. Fresh keyed games mount reliably inside a
    // single testWidgets, while the first GameWidget game of a LATER
    // testWidgets in the same run never mounts under the fake clock — a
    // test-environment artifact this file cannot fix (every existing
    // test here pumps its games within its own body) — so all four
    // placements are judged in one drive.
    testWidgets('in every mode, at the smallest phone, and on a '
        'home-indicator phone, the pill clears the cab\'s tail',
        (tester) async {
      // The geometry issue #182 measured: a 420×912 phone, 70 pt of
      // Dynamic Island, 34 pt of home indicator. GameScreen insets the
      // game top-only, so the canvas keeps the bottom inset — and the
      // overlay used to measure inside its own SafeArea, which dropped
      // it: an 808 pt ruler against the 842 pt canvas the cab is
      // rendered into, the pill riding back up onto the cab's tail.
      // The tail below is read off the camera transform — where the cab
      // is actually painted — not the shared cabTailOnScreen formula:
      // that formula is frame arithmetic, and on the default flat test
      // surface (no insets) it agreed with whatever frame the overlay
      // measured, so it could never catch a wrong frame.
      tester.view.physicalSize = const Size(420 * 3, 912 * 3);
      tester.view.devicePixelRatio = 3;
      // A view reports padding in physical pixels, like a real window:
      // 70 pt top, 34 pt bottom, at 3× density.
      tester.view.padding =
          const FakeViewPadding(left: 0, top: 70 * 3, right: 0, bottom: 34 * 3);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

      final homeIndicatorGame =
          await pumpGameScreen(tester, endless: false, tag: 'hi');
      expect(
        tester.getSize(find.byType(GameWidget<TaxiGame>)).height,
        842,
        reason: 'the canvas eats the 70 pt top inset and keeps the 34 pt '
            'bottom one — the exact canvas the issue measured',
      );
      final canvasTop =
          tester.getTopLeft(find.byType(GameWidget<TaxiGame>)).dy;
      final renderedTail = homeIndicatorGame.camera.localToGlobal(
        homeIndicatorGame.player.position +
            Vector2(0, homeIndicatorGame.player.stats.height / 2),
      );
      expect(
        tester.getTopLeft(hintFinder).dy - canvasTop,
        greaterThanOrEqualTo(renderedTail.y + 15.5),
        reason: 'on a home-indicator phone the pill clears the cab\'s '
            'rendered tail by its clearance, measured in the canvas frame '
            'the cab is painted into — not a SafeArea-shortened one '
            '(issue #182; half a pixel of float grace)',
      );

      // Back to the default flat test surface for the drives below.
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();

      // The tutorial ladder: the camera lead parks the cab
      // [TaxiGame.levelCameraLead] below centre, and the fixed alignment
      // placed for a centred cab used to ride up onto the cab's tail on
      // every rung.
      var game = await pumpGameScreen(tester, endless: false, tag: 'a');
      expect(hintFinder, findsOneWidget,
          reason: 'the fresh save teaches the stick on the ladder too');

      var surface =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      var hintTop = tester.getTopLeft(hintFinder).dy;
      expect(hintTop, greaterThan(surface.height / 2),
          reason: 'the whole pill lives in the stick\'s lower half, where '
              'a tap on it is a stick touch');
      expect(
          hintTop,
          greaterThanOrEqualTo(cabTailOnScreen(game, surface) + 15.5),
          reason: 'the level camera parks the cab 100 px below centre — '
              'the hint must clear its tail, not sit on it (half a pixel '
              'of float grace)');

      // The endless framing the old placement was built for — the
      // centred cab — must survive the rewrite.
      game = await pumpGameScreen(tester, tag: 'b');
      surface = tester.view.physicalSize / tester.view.devicePixelRatio;
      hintTop = tester.getTopLeft(hintFinder).dy;
      expect(
          hintTop,
          greaterThanOrEqualTo(cabTailOnScreen(game, surface) + 15.5),
          reason: 'the centred-cab clearance the old alignment got right');

      // 320×568 — the smallest phone: the lane under the cab cannot hold
      // the pill at natural size, so it must scale down rather than
      // climb onto the cab or past the screen edge.
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      game = await pumpGameScreen(tester, endless: false, tag: 'c');
      final rect = tester.getRect(hintFinder);
      expect(
          rect.top,
          greaterThanOrEqualTo(
              cabTailOnScreen(game, const Size(320, 568)) + 15.5),
          reason: 'the cab bound holds at any size');
      expect(rect.bottom, lessThanOrEqualTo(568.5),
          reason: 'the lane cannot hold the pill at natural size on this '
              'phone — it must scale down, not overflow past the screen '
              'edge');
      expect(rect.height, greaterThan(120),
          reason: 'a scaled-down hint, not a smear');
    });
  });

  group('a seasoned save', () {
    testWidgets('a save from before this feature is never shown the hint',
        (tester) async {
      // A pre-issue-#37 save: no hint flag at all — its player has
      // already driven.
      SharedPreferences.setMockInitialValues(
          {StorageService.saveDataKey: jsonEncode(seasonedSave())});
      final storage = StorageService();
      await storage.init();
      gameState = GameStateService(storage);
      await gameState.loadSaveData();

      await pumpGameScreen(tester);

      expect(hintFinder, findsNothing);
      expect(gameState.controlHintDismissed, isTrue,
          reason: 'the missing flag reads as dismissed, never re-arms');
    });

    testWidgets('a save that dismissed the hint once is never shown it again',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey:
            jsonEncode(seasonedSave(controlHintDismissed: true)),
      });
      final storage = StorageService();
      await storage.init();
      gameState = GameStateService(storage);
      await gameState.loadSaveData();

      await pumpGameScreen(tester);
      expect(hintFinder, findsNothing);
    });
  });

  group('the save flag', () {
    test('a fresh save has not dismissed the hint, and false round-trips',
        () {
      final fresh = SaveData.createDefault();
      expect(fresh.controlHintDismissed, isFalse);

      final round = SaveData.fromJson(fresh.toJson());
      expect(round.controlHintDismissed, isFalse,
          reason: 'a fresh save stays teachable across sessions');
    });

    test('a save written before the hint existed loads as dismissed', () {
      final preFlag = SaveData.fromJson(seasonedSave());

      expect(preFlag.controlHintDismissed, isTrue,
          reason: 'a missing key means "already a player", not "unseen"');
      expect(SaveData.fromJson(preFlag.toJson()).controlHintDismissed, isTrue,
          reason: 'and it round-trips into new saves');
    });

    test('dismissing the hint persists and is idempotent', () async {
      gameState.dismissControlHint();
      gameState.dismissControlHint();

      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();

      expect(reloaded.controlHintDismissed, isTrue);
    });

    test('resetting progress re-arms the hint', () async {
      gameState.dismissControlHint();
      expect(gameState.controlHintDismissed, isTrue);

      gameState.resetProgress();
      expect(gameState.controlHintDismissed, isFalse,
          reason: 'a wiped save is a first-time player again');

      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();
      expect(reloaded.controlHintDismissed, isFalse);
    });
  });

  group('after a reset', () {
    testWidgets('the next game start teaches the stick again',
        (tester) async {
      await pumpGameScreen(tester);
      expect(hintFinder, findsOneWidget);

      // Dismiss the hint the way a player does.
      final gesture = await tester.startGesture(const Offset(400, 450));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, -160));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(hintFinder, findsNothing);

      // Wipe everything, same as the settings screen does.
      gameState.resetProgress();
      await tester.pump();
      expect(gameState.controlHintDismissed, isFalse);

      await pumpNextSession(tester, gameState, seed: 44);
      expect(hintFinder, findsOneWidget,
          reason: 'the wiped save is taught once more');
    });
  });
}
