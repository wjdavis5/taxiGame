import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/credits_screen.dart';
import 'package:taxi_game/ui/screens/garage_screen.dart';
import 'package:taxi_game/ui/screens/main_menu_screen.dart';
import 'package:taxi_game/ui/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
  });

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          Provider<AudioService>.value(value: AudioService()),
          Provider<StorageService>.value(value: storage),
        ],
        child: MaterialApp(home: child),
      );

  group('menu destinations', () {
    testWidgets('garage opens the real garage screen', (tester) async {
      // The garage used to be a dead 'coming soon' snackbar and was removed;
      // now that it exists, the button must lead to a working screen.
      await tester.pumpWidget(wrap(const MainMenuScreen()));
      await tester.pump();

      final button = find.byKey(const ValueKey('garage_button'));
      expect(button, findsOneWidget);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.byType(GarageScreen), findsOneWidget);
      expect(find.textContaining('coming soon'), findsNothing);
    });

    testWidgets('settings opens the settings screen rather than a snackbar',
        (tester) async {
      await tester.pumpWidget(wrap(const MainMenuScreen()));
      await tester.pump();

      final button = find.byKey(const ValueKey('settings_button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.textContaining('coming soon'), findsNothing);
    });
  });

  group('reset progress', () {
    testWidgets('shows current level and coins', (tester) async {
      gameState.addCoins(120);
      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      expect(find.textContaining('Level 1'), findsOneWidget);
      expect(find.textContaining('120 coins'), findsOneWidget);
    });

    testWidgets('asks for confirmation before wiping the save',
        (tester) async {
      gameState.addCoins(200);
      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('reset_progress_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('reset_confirm_dialog')), findsOneWidget);
      // Nothing is destroyed merely by opening the dialog.
      expect(gameState.totalCoins, 200);
    });

    testWidgets('cancelling leaves progress untouched', (tester) async {
      gameState.addCoins(200);
      gameState.completeLevel(1, 0);
      final levelBefore = gameState.currentLevel;

      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('reset_progress_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reset_cancel_button')));
      await tester.pumpAndSettle();

      expect(gameState.totalCoins, 200);
      expect(gameState.currentLevel, levelBefore);
      expect(find.byKey(const ValueKey('reset_confirm_dialog')), findsNothing);
    });

    testWidgets('confirming clears coins and returns to level 1',
        (tester) async {
      gameState.addCoins(200);
      gameState.completeLevel(1, 50);

      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('reset_progress_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reset_confirm_button')));
      await tester.pumpAndSettle();

      expect(gameState.totalCoins, 0);
      expect(gameState.currentLevel, 1);
    });

    testWidgets('the displayed totals refresh after a reset', (tester) async {
      gameState.addCoins(75);
      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      expect(find.textContaining('75 coins'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('reset_progress_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reset_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('0 coins'), findsOneWidget);
      expect(find.textContaining('75 coins'), findsNothing);
    });
  });

  group('about', () {
    testWidgets('credits is reachable from settings', (tester) async {
      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('settings_credits_tile')));
      await tester.pumpAndSettle();

      expect(find.byType(CreditsScreen), findsOneWidget);
    });

    testWidgets('no non-functional audio toggles are shown', (tester) async {
      // Audio is not implemented, so a sound or music switch would be a control
      // that changes nothing the player can perceive.
      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('Sound'), findsNothing);
      expect(find.textContaining('Music'), findsNothing);
    });

    testWidgets('renders without overflow on a narrow portrait screen',
        (tester) async {
      tester.view.physicalSize = const Size(750, 1334);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
