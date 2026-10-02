import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/main.dart' show TaxiGameApp;
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// Tooltip long-press feedback vs the settings screens (issue #169).
///
/// Every screen's Back arrow is an IconButton with `tooltip: 'Back'`, and
/// a long-pressed tooltip fires the *framework's* feedback straight from
/// its own gesture handler — `Feedback.forLongPress`, which on iOS plays
/// the system click AND a heavy-impact haptic. No app code runs in
/// between, so neither settings toggle could ever gate it: a player with
/// Sound and Vibration both off still got the buzz and the click. The app
/// theme now resolves every tooltip's `enableFeedback` to false
/// (lib/main.dart), which leaves the tooltip doing what it was there for
/// — naming the button for accessibility — and returns all feedback to
/// the gated AudioService/HapticsService paths.
///
/// The test pumps the real [TaxiGameApp] over the same five providers
/// lib/main.dart mounts, with the save's Sound and Vibration toggles both
/// off (the services gated to match), intercepts SystemChannels.platform,
/// navigates to the settings screen the way a player does, and long-
/// presses its Back arrow. The iOS target override matters: widget tests
/// default to android, where the framework only vibrates, but this app
/// ships iPhone-only and iOS is the platform that answers long-press
/// feedback with both the click and the impact the issue names.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'long-pressing a Back arrow stays silent with Sound and Vibration off '
    '(issue #169)',
    (tester) async {
      // The platform the bug ships on. Feedback.forLongPress answers iOS
      // with SystemSound.play + HapticFeedback.heavyImpact — the exact
      // buzz+click pair — so pin the override before anything renders.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // Every platform-channel call lands here. The assertions filter to
      // the two feedback families; nothing else in this scenario may speak
      // on this channel at all.
      final platformCalls = <String>[];
      TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call.method);
        return 0;
      });
      addTearDown(() =>
          TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null));

      // The save the issue describes: both feedback toggles off, and the
      // running services gated to match — exactly the composition root
      // lib/main.dart builds from this save state. With the app's own
      // feedback gated, any call that still arrives is unambiguously the
      // framework's tooltip path.
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      final gameState = GameStateService(storage);
      gameState.toggleSound();
      gameState.toggleVibration();
      expect(gameState.soundEnabled, isFalse);
      expect(gameState.vibrationEnabled, isFalse);

      final audio = AudioService()..setSoundEnabled(gameState.soundEnabled);
      final haptics = HapticsService()
        ..setEnabled(gameState.vibrationEnabled);

      // A phone-shaped surface: the menu is a tall portrait column, and
      // the default 800x600 test surface puts SETTINGS below the fold.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<GameStateService>.value(value: gameState),
            Provider<AudioService>.value(value: audio),
            Provider<HapticsService>.value(value: haptics),
            Provider<StorageService>.value(value: storage),
            Provider<LevelLoaderService>.value(value: LevelLoaderService()),
          ],
          child: const TaxiGameApp(),
        ),
      );
      await tester.pump();

      // Reach the settings screen the way a player does; the menu button's
      // own sound and buzz are gated off above, so this leg must already
      // be silent.
      await tester.tap(find.byKey(const Key('settings_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_back_button')), findsOneWidget);
      expect(
        platformCalls
            .where((m) =>
                m.startsWith('HapticFeedback.') ||
                m.startsWith('SystemSound.'))
            .toList(),
        isEmpty,
        reason: 'reaching the screen is ordinary navigation — its feedback '
            'rides the gated services, which are off',
      );

      // The long-press itself. Not a tap: a tap navigates home and never
      // wakes the tooltip's own long-press handler — the one that fires
      // the ungated feedback.
      await tester.longPress(find.byKey(const Key('settings_back_button')));
      // Run the tooltip's entrance animation so its text is on screen. No
      // pumpAndSettle here: it would sit out the tooltip's display timer.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The tooltip appeared — proof the long-press reached the very
      // handler that fires the feedback, so the silence below is the gate
      // holding, not a gesture that never landed.
      expect(find.text('Back'), findsOneWidget);

      expect(
        platformCalls
            .where((m) =>
                m.startsWith('HapticFeedback.') ||
                m.startsWith('SystemSound.'))
            .toList(),
        isEmpty,
        reason: 'a long-pressed Back arrow must not buzz or click with both '
            'toggles off: the framework\'s tooltip feedback is what '
            'bypassed them (issue #169)',
      );

      // And the fix cost nothing: the arrow still works as a button, and
      // a plain tap still goes home.
      await tester.tap(find.byKey(const Key('settings_back_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_back_button')), findsNothing);

      // The binding verifies foundation vars are unset before tearDowns
      // run, so the override is cleared in the body (the tearDown is a
      // backstop for a mid-body failure).
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
