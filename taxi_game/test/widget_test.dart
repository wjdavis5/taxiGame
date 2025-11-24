// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi_game/main.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('TaxiGameApp renders main menu title', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameStateService),
          Provider<AudioService>.value(value: AudioService()),
          Provider<StorageService>.value(value: storageService),
        ],
        child: const TaxiGameApp(),
      ),
    );

    await tester.pump();

    expect(find.text('TAXI GAME'), findsOneWidget);
  });
}
