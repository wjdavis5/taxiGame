import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/game_state_service.dart';
import 'services/audio_service.dart';
import 'services/diagnostics.dart';
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

  // Telemetry begins before anything can go wrong: the previous
  // session's tail is on disk, and from here every debugPrint, framework
  // error, and uncaught exception lands in the ring buffer (and back on
  // disk), so a hard kill on a device still leaves the last moments
  // readable on the next launch. Local only — see Diagnostics.
  await Diagnostics.instance.load();
  Diagnostics.instance.installGlobalHooks();
  Diagnostics.instance.log('[app] start '
      'mode=${kReleaseMode ? 'release' : 'debug'} '
      'platform=${defaultTargetPlatform.name}');

  // Initialize services
  final storageService = StorageService();
  await storageService.init();

  final gameStateService = GameStateService(storageService);
  await gameStateService.loadSaveData();
  Diagnostics.instance.log('[save] loaded level='
      '${gameStateService.currentLevel}');

  // The save's Sound flag reaches the service at construction (issue
  // #207) — the haptics seed's pattern below. Until it was seeded here,
  // the flag only landed inside the un-awaited start-up chain's
  // applySettings, so a menu tap in the first moments after launch —
  // while that chain was still winding through platform calls — found
  // the flag's `true` default and clicked with Sound turned off. Safe
  // before initialize: setSoundEnabled only flips the flag and syncs the
  // engine loop, and with no engine player and no engine want (nothing
  // is on the road yet) that sync makes no platform call at all.
  final audioService = AudioService()
    ..setSoundEnabled(gameStateService.soundEnabled);
  // Candidate A of issue #40 + launch hygiene: never block the first
  // frame on audio I/O. Every await here is fenced inside AudioService,
  // but a platform call that HANGS (rather than throws) on a real device
  // would hold this pre-runApp chain hostage — a blank launch the iOS
  // watchdog eventually kills. runApp first; audio catches up a few
  // frames later, imperceptibly.
  unawaited(audioService.initialize().then((_) async {
    Diagnostics.instance.log('[audio] initialized');
    // Sound already governs from the first frame — the seed at the
    // service's construction above (issue #207); its half of this call
    // early-returns on the value the seed set. What starts here is
    // music: applySettings gates the track on the save's flag (issue
    // #4), and the listener below keeps both live.
    await audioService.applySettings(
      soundEnabled: gameStateService.soundEnabled,
      musicEnabled: gameStateService.musicEnabled,
    );
    // Music runs everywhere — menu and shift alike — whenever the player
    // has it enabled. Toggling the settings switch flips it through the
    // listener.
    await audioService.playMusic();
    Diagnostics.instance.log('[audio] music started');
  }).catchError((Object error, StackTrace stack) {
    Diagnostics.instance.logError('audio_init', error, stack);
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
      title: 'Cab Hustle',
      theme: ThemeData(
        // Tooltips are labels, never feedback (issue #169): a long-pressed
        // tooltip fires the framework's own feedback — Feedback.forLongPress,
        // which on iOS plays the system click AND a heavy-impact haptic —
        // straight from its gesture handler, where none of this app's
        // settings can gate it. Every Back arrow is an IconButton with a
        // tooltip, so a player with Sound and Vibration off still got the
        // buzz and the click. One theme line resolves every tooltip's
        // enableFeedback to false app-wide: the label stays (it is the
        // accessibility name), and feedback returns to the AudioService and
        // HapticsService paths the toggles actually control.
        tooltipTheme: const TooltipThemeData(enableFeedback: false),
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
