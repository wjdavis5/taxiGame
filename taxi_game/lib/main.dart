import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/game_state_service.dart';
import 'services/audio_service.dart';
import 'services/haptics_service.dart';
import 'services/storage_service.dart';
import 'services/level_loader_service.dart';
import 'ui/screens/main_menu_screen.dart';

/// The orientations this app supports.
///
/// `ios/Runner/Info.plist` declares the same set under
/// `UISupportedInterfaceOrientations`. The two must stay in sync: a
/// declared-but-unreachable orientation is the first thing a reviewer finds by
/// rotating the device.
///
/// The app ships iPhone-only. Declaring iPad support would require all four
/// orientations and resizable-window support, since iPadOS 26 removed the
/// multitasking opt-out.
const supportedOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
];

/// Locks the app to [supportedOrientations].
///
/// Extracted from [main] so it can be exercised without booting the service
/// graph.
Future<void> lockOrientation() {
  return SystemChrome.setPreferredOrientations(supportedOrientations);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await lockOrientation();
  
  // Initialize services
  final storageService = StorageService();
  await storageService.init();

  final gameStateService = GameStateService(storageService);
  await gameStateService.loadSaveData();

  final audioService = AudioService();
  // Candidate A of issue #40 + launch hygiene: never block the first
  // frame on audio I/O. Every await here is fenced inside AudioService,
  // but a platform call that HANGS (rather than throws) on a real device
  // would hold this pre-runApp chain hostage — a blank launch the iOS
  // watchdog eventually kills. runApp first; audio catches up a few
  // frames later, imperceptibly.
  unawaited(audioService.initialize().then((_) async {
    // The save's sound and music settings govern playback from the first
    // frame (issue #4); the listener below keeps it that way live.
    await audioService.applySettings(
      soundEnabled: gameStateService.soundEnabled,
      musicEnabled: gameStateService.musicEnabled,
    );
    // Music runs everywhere — menu and shift alike — whenever the player
    // has it enabled. Toggling the settings switch flips it through the
    // listener.
    await audioService.playMusic();
  }));
  // Haptics (issue #5): the save's vibration setting governs the buzz from
  // the first frame, and the listener below keeps the running service's
  // gate live — the same forwarding the audio flags ride.
  final hapticsService = HapticsService()
    ..setEnabled(gameStateService.vibrationEnabled);

  gameStateService.addListener(() {
    audioService.setSoundEnabled(gameStateService.soundEnabled);
    audioService.setMusicEnabled(gameStateService.musicEnabled);
    hapticsService.setEnabled(gameStateService.vibrationEnabled);
  });

  final levelLoaderService = LevelLoaderService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gameStateService),
        Provider.value(value: audioService),
        Provider.value(value: hapticsService),
        Provider.value(value: storageService),
        Provider.value(value: levelLoaderService),
      ],
      child: const TaxiGameApp(),
    ),
  );
}

class TaxiGameApp extends StatelessWidget {
  const TaxiGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Taxi Game',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.yellow,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      debugShowCheckedModeBanner: false,
      home: const MainMenuScreen(),
    );
  }
}
