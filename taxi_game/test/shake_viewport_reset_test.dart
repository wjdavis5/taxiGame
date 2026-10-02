import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/fake_audio_platform.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';

/// The shake's bookkeeping survives a mid-shake overlay swap (issue
/// #145).
///
/// Screen shake applies as a delta on the camera viewport, and the rest
/// position is *derived* every frame from the live viewport minus the
/// offset currently applied. But every overlay change — the bank-or-push
/// panel coming up over a crash, any panel going away — refreshes the
/// GameWidget, and the rebuild unconditionally re-runs `onGameResize`,
/// where the fixed-resolution viewport resets its position to the
/// canonical letterbox offset. A shake that was live across that rebuild
/// used to keep its stale offset in the books, subtract jitter the
/// viewport no longer carried, and settle the whole playfield up to
/// ~12 px off-centre — permanently, until the next overlay swap. The
/// game now zeroes its applied-offset ledger in `onGameResize`, after
/// the viewport has stood itself back at canonical.
///
/// This has to be a widget test: the headless shake test
/// (impact_fx_test.dart) mounts the game directly, so no GameWidget
/// ever rebuilds and the reset path is never taken. The HUD polls the
/// game on a repeating timer, so fixed-duration pumps only, never
/// pumpAndSettle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;

  setUp(() async {
    installFakeAudioPlatform();
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  Future<TaxiGame> pumpGameScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          Provider<AudioService>.value(value: AudioService()),
          Provider<HapticsService>.value(value: HapticsService()),
          Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        ],
        child: const MaterialApp(home: GameScreen(endlessSeed: 42)),
      ),
    );
    // One pump resolves the GameWidget's load future, a real-async settle
    // lets the taxi's sprite decode finish, then the next pumps run the
    // first live frames.
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final game = tester
        .widget<GameWidget<TaxiGame>>(find.byType(GameWidget<TaxiGame>))
        .game!;
    expect(game.isGameActive, isTrue,
        reason: 'the endless run must be live before any shake');
    return game;
  }

  testWidgets('the viewport returns to rest when an overlay changes '
      'mid-shake (issue #145)', (tester) async {
    final game = await pumpGameScreen(tester);

    // Where an undisturbed view sits: the canonical letterbox offset.
    final rest = game.camera.viewport.position.clone();

    // Crash-grade shake: 13 px, decaying over the stock 0.35 s.
    game.shake.trigger(13);

    // Run the shake until the viewport has actually moved — the ledger
    // now holds a live offset (the viewport's only writers are the shake
    // and the resize, so moved means jittered).
    var moved = false;
    for (var i = 0; i < 10 && !moved; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      moved = game.camera.viewport.position != rest;
    }
    expect(moved, isTrue, reason: 'precondition: the shake must be live');

    // The overlay swap: the crash-while-banked sequence in miniature.
    // Dropping 'hud' (active from the first frame) refreshes the widget,
    // and the rebuild resets the viewport to canonical while the shake
    // is still decaying — the exact frame the stale ledger used to
    // poison.
    game.overlays.remove('hud');
    await tester.pump(const Duration(milliseconds: 16));

    // Let the shake finish decaying (0.35 s) and add the idle tick that
    // applies the final zero offset.
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 16));

    // The view must sit back on the canonical rest, both axes — the
    // stale-ledger build rests whatever the mid-shake offset happened to
    // be (up to the full 13 px) short of it. The tolerance is float32
    // scale, not exact: the viewport position lives in single precision,
    // and the round trip through the shake deltas and the resize reset
    // legitimately leaves ulp-scale residue (~1.5e-5 px) — a thousandth
    // of a pixel is still four orders tighter than the bug being pinned.
    expect(game.camera.viewport.position.x, closeTo(rest.x, 1e-3),
        reason: 'the horizontal rest is the canonical letterbox offset, '
            'not offset by leftover shake bookkeeping');
    expect(game.camera.viewport.position.y, closeTo(rest.y, 1e-3),
        reason: 'the vertical rest is the canonical letterbox offset, '
            'not offset by leftover shake bookkeeping');
  });
}
