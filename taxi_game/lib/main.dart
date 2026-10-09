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

  await startApp();
}

/// Boots the service graph and starts the app.
///
/// Extracted from [main] so tests can exercise each startup failure
/// (issue #231). Every await here used to be unguarded before `runApp`:
/// a storage or orientation failure aborted `main()` before any UI was
/// mounted, leaving the launch storyboard on screen forever — a softlock
/// recoverable only by reinstall, with the error recorded in a ring the
/// player could never reach.
@visibleForTesting
Future<void> startApp({
  StorageService Function() storageFactory = StorageService.new,
}) async {
  // Orientation is presentation, not a reason to softlock: a refused
  // lock is logged and startup carries on with the platform default.
  try {
    await lockOrientation();
  } catch (error, stack) {
    Diagnostics.instance.logError('orientation', error, stack);
  }

  // The save is the one thing the game cannot quietly pretend about: a
  // defaults-only session would play on and throw the mismatched
  // progress away without telling anyone. A storage failure gets the
  // honest error surface instead, with a retry.
  final StorageService storageService;
  final GameStateService gameStateService;
  try {
    storageService = storageFactory();
    await storageService.init();

    gameStateService = GameStateService(storageService);
    await gameStateService.loadSaveData();
  } catch (error, stack) {
    Diagnostics.instance.logError('startup', error, stack);
    // The retry keeps the boot's own storage factory, so a test-injected
    // store recovers the same way the production one would.
    runApp(StartupFailureApp(
      onRetry: () => startApp(storageFactory: storageFactory),
    ));
    return;
  }
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

/// The launch surface for a boot that could not open its storage (issue
/// #231): a real screen — with the retry that a transient failure
/// deserves — instead of the frozen launch storyboard the old unguarded
/// awaits left behind. The failure itself is already in the diagnostics
/// tail for support.
class StartupFailureApp extends StatefulWidget {
  const StartupFailureApp({super.key, required this.onRetry});

  /// Runs the boot again; on success it replaces this app with the game.
  final Future<void> Function() onRetry;

  @override
  State<StartupFailureApp> createState() => _StartupFailureAppState();
}

class _StartupFailureAppState extends State<StartupFailureApp> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    // A retry that succeeds replaces this app from the root; one that
    // fails builds a fresh failure app. Either way this state is gone.
    await widget.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.yellow),
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_taxi, size: 64, color: Colors.amber),
                const SizedBox(height: 20),
                const Text(
                  "Cab Hustle couldn't start",
                  key: Key('startup_failure_title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your saved progress could not be opened. Try again — if '
                  'this keeps happening, reinstall the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.white70),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  key: const Key('startup_failure_retry'),
                  onPressed: _retrying ? null : _retry,
                  child: const Text('TRY AGAIN'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
