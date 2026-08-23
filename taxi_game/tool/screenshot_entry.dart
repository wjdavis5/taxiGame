// Development entrypoint for capturing App Store screenshots.
//
// The App Store listing needs shots of specific screens, and driving the UI
// from outside the app needs accessibility permissions that CI and a clean
// machine do not have. This entrypoint sidesteps that by launching directly
// into one screen, chosen at build time:
//
//   flutter run -d <simulator-id> -t tool/screenshot_entry.dart \
//     --dart-define=SHOT=menu     # or: game, credits, settings
//
// Then capture with `xcrun simctl io <simulator-id> screenshot out.png`.
// `tool/capture_screenshots.sh` wraps the whole sequence.
//
// This file is never referenced by lib/main.dart and ships in no build.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:taxi_game/main.dart' show lockOrientation;
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/credits_screen.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';
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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gameStateService),
        Provider.value(value: audioService),
        Provider.value(value: storageService),
        Provider.value(value: levelLoaderService),
      ],
      child: const _ScreenshotApp(),
    ),
  );
}

class _ScreenshotApp extends StatelessWidget {
  const _ScreenshotApp();

  Widget get _home => switch (shot) {
        'game' => const GameScreen(),
        'credits' => const CreditsScreen(),
        'settings' => const SettingsScreen(),
        _ => const MainMenuScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cab Hustle',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.yellow,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      debugShowCheckedModeBanner: false,
      home: _home,
    );
  }
}
