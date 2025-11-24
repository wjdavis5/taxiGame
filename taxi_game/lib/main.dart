import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/game_state_service.dart';
import 'services/audio_service.dart';
import 'services/storage_service.dart';
import 'services/level_loader_service.dart';
import 'ui/screens/main_menu_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set preferred orientations (portrait mode for mobile)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
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
