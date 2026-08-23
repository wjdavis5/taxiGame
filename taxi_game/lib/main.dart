import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/game_state_service.dart';
import 'services/audio_service.dart';
import 'services/storage_service.dart';
import 'services/level_loader_service.dart';
import 'ui/screens/main_menu_screen.dart';

/// The orientations this app supports.
///
/// `ios/Runner/Info.plist` declares the same set under
/// `UISupportedInterfaceOrientations` and `UISupportedInterfaceOrientations~ipad`.
/// The two must stay in sync: a declared-but-unreachable orientation is the
/// first thing a reviewer finds by rotating the device.
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
  final levelLoaderService = LevelLoaderService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gameStateService),
        Provider.value(value: audioService),
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
