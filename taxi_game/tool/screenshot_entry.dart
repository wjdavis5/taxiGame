// Development entrypoint for capturing App Store screenshots.
//
// The App Store listing needs shots of specific screens, and driving the UI
// from outside the app needs accessibility permissions that CI and a clean
// machine do not have. This entrypoint sidesteps that by launching directly
// into one screen, chosen at build time:
//
//   flutter run -d <simulator-id> -t tool/screenshot_entry.dart \
//     --dart-define=SHOT=menu     # or: game, garage, credits, settings
//
// Then capture with `xcrun simctl io <simulator-id> screenshot out.png`,
// following the full sequence in CLAUDE.md ("Screenshots for the App Store").
//
// This file is never referenced by lib/main.dart and ships in no build.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:taxi_game/main.dart' show lockOrientation;
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

/// Which screen to launch into. Mirrors the production startup path so the
/// captures show the real app rather than a mock.
const shot = String.fromEnvironment('SHOT', defaultValue: 'menu');

/// Coins to seed, so the menu reads like a played save rather than a fresh
/// install showing zeroes.
const seedCoins = int.fromEnvironment('SEED_COINS', defaultValue: 0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await lockOrientation();

  final storageService = StorageService();
  await storageService.init();

  final gameStateService = GameStateService(storageService);
  await gameStateService.loadSaveData();
  if (seedCoins > 0) {
    gameStateService.addCoins(seedCoins);
  }

  final audioService = AudioService();
  final levelLoaderService = LevelLoaderService();
  // Haptics (issue #99): GameScreen reads a HapticsService provider in
  // initState, and this entry's stack used to stop one service short — the
  // SHOT=game capture died with a ProviderNotFoundException before its
  // first frame, photographing Flutter's error screen instead of the
  // shift. Built exactly like the production root (lib/main.dart): the
  // save's vibration flag gates the buzz from the first frame. No live
  // settings listener here — a capture never toggles settings, and a
  // still frame cannot feel either way.
  final hapticsService = HapticsService()
    ..setEnabled(gameStateService.vibrationEnabled);

  runApp(
    screenshotProviders(
      gameStateService: gameStateService,
      audioService: audioService,
      hapticsService: hapticsService,
      storageService: storageService,
      levelLoaderService: levelLoaderService,
      child: const _ScreenshotApp(),
    ),
  );
}

/// The provider stack every shot launches under, as one widget around
/// [child] — the same five services the production root provides
/// (lib/main.dart), so a capture shows the real app and no screen can
/// miss, here only, a dependency production hands it.
///
/// Public and handed its services so the regression test can pump each
/// shot's home under this exact stack (test/screenshot_entry_test.dart):
/// `shot` is a compile-time constant, so no test run can vary it through
/// `main`. (Returns the whole MultiProvider rather than a bare provider
/// list because `SingleChildWidget` lives in package:nested, which
/// provider does not re-export.)
MultiProvider screenshotProviders({
  required GameStateService gameStateService,
  required AudioService audioService,
  required HapticsService hapticsService,
  required StorageService storageService,
  required LevelLoaderService levelLoaderService,
  required Widget child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: gameStateService),
      Provider.value(value: audioService),
      Provider.value(value: hapticsService),
      Provider.value(value: storageService),
      Provider.value(value: levelLoaderService),
    ],
    child: child,
  );
}

/// The screen a shot name launches into. Extracted from [_ScreenshotApp]
/// so the regression test can drive every target — `shot` is resolved at
/// compile time, so this switch is the only way a test can vary it.
Widget homeForShot(String shot) => switch (shot) {
      'game' => const GameScreen(),
      'garage' => const GarageScreen(),
      'credits' => const CreditsScreen(),
      'settings' => const SettingsScreen(),
      _ => const MainMenuScreen(),
    };

class _ScreenshotApp extends StatelessWidget {
  const _ScreenshotApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cab Hustle',
      theme: ThemeData(
        // Same tooltip silencing as lib/main.dart (issue #169): a capture
        // must show the app as it ships, and the framework's ungated
        // long-press feedback would buzz and click a capture device with
        // both toggles off.
        tooltipTheme: const TooltipThemeData(enableFeedback: false),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.yellow,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      debugShowCheckedModeBanner: false,
      home: homeForShot(shot),
    );
  }
}
