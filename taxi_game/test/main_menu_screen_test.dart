import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/main_menu_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildMenu(GameStateService gameState, StorageService storage) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<GameStateService>.value(value: gameState),
        Provider<AudioService>.value(value: AudioService()),
        Provider<StorageService>.value(value: storage),
      ],
      child: const MaterialApp(
        home: MainMenuScreen(),
      ),
    );
  }

  testWidgets('displays current level and coin total', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    gameStateService.addCoins(75);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('75 Coins'), findsOneWidget);
    expect(find.text('TAXI GAME'), findsOneWidget);
  });

  testWidgets('play button is present and enabled', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final playButton = find.byKey(const ValueKey('play_button'));
    expect(playButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(playButton).onPressed, isNotNull);
  });
}
