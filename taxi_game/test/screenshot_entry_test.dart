import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/credits_screen.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';
import 'package:taxi_game/ui/screens/garage_screen.dart';
import 'package:taxi_game/ui/screens/main_menu_screen.dart';
import 'package:taxi_game/ui/screens/settings_screen.dart';

import '../tool/screenshot_entry.dart';
import 'helpers/fake_audio_platform.dart';

/// The screenshot entry must boot every App Store target (issue #99).
///
/// `SHOT=game` used to crash: GameScreen's initState reads a
/// HapticsService provider the entry never supplied, so the documented
/// capture recipe photographed Flutter's error screen instead of the
/// shift — ProviderNotFoundException before the first frame. The entry's
/// `shot` is a compile-time `String.fromEnvironment`, so no test can
/// vary it through `main`; instead these tests pump each target's home
/// ([homeForShot]) inside the entry's real provider widget
/// ([screenshotProviders] — the very stack the haptics service was
/// missing from), with the same hermetic services the rest of the widget
/// suite uses. A missing provider now fails here, in seconds, rather than
/// at the next screenshot session on a Mac.
///
/// The HUD polls the game on a repeating timer, so the game shot pumps
/// fixed durations and never pumpAndSettle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late GameStateService gameState;

  setUp(() async {
    installFakeAudioPlatform();
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  /// Boots one shot exactly the way the entry's `main` does: the entry's
  /// own provider widget around the entry's own home widget, then the
  /// settle a real capture waits out before `simctl io screenshot` fires.
  Future<void> pumpShot(WidgetTester tester, String shotName) async {
    await tester.pumpWidget(
      screenshotProviders(
        gameStateService: gameState,
        audioService: AudioService(),
        hapticsService: HapticsService()
          ..setEnabled(gameState.vibrationEnabled),
        storageService: storage,
        levelLoaderService: LevelLoaderService(),
        child: MaterialApp(home: homeForShot(shotName)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // GameScreen mounts a Flame game whose load is async; the runAsync
    // hop lets real futures (asset reads, audio platform calls) complete
    // the same way they do in game_screen_back_swipe_test.dart.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('SHOT=game boots the shift, not the error screen (issue #99)',
      (tester) async {
    await pumpShot(tester, 'game');

    expect(tester.takeException(), isNull,
        reason: 'GameScreen reads HapticsService in initState; the entry '
            'must supply it, or the capture is a red screen');
    expect(find.byType(GameScreen), findsOneWidget,
        reason: 'the game screen itself is mounted — an initState throw '
            'would have replaced it with the error widget');
  });

  testWidgets('SHOT=menu boots', (tester) async {
    await pumpShot(tester, 'menu');

    expect(tester.takeException(), isNull);
    expect(find.byType(MainMenuScreen), findsOneWidget);
  });

  testWidgets('SHOT=garage boots', (tester) async {
    await pumpShot(tester, 'garage');

    expect(tester.takeException(), isNull);
    expect(find.byType(GarageScreen), findsOneWidget);
  });

  testWidgets('SHOT=credits boots', (tester) async {
    await pumpShot(tester, 'credits');

    expect(tester.takeException(), isNull);
    expect(find.byType(CreditsScreen), findsOneWidget);
  });

  testWidgets('SHOT=settings boots', (tester) async {
    await pumpShot(tester, 'settings');

    expect(tester.takeException(), isNull);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
