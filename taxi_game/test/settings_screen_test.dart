import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/credits_screen.dart';
import 'package:taxi_game/ui/screens/garage_screen.dart';
import 'package:taxi_game/ui/screens/main_menu_screen.dart';
import 'package:taxi_game/ui/screens/records_screen.dart';
import 'package:taxi_game/ui/screens/settings_screen.dart';
import 'package:taxi_game/ui/screens/stats_screen.dart';

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
      // A recorded shift is progress too (issue #17): the reset must take
      // the history with the coins.
      await gameState.recordEndlessRun(const RunRecord(
        endedAtMs: 0,
        distancePx: 5000,
        score: 120,
        faresDelivered: 2,
        longestChain: 3,
        livesLost: 0,
        lifeLossDistancesPx: [],
        banked: true,
        durationSeconds: 90,
      ));

      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('reset_progress_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reset_confirm_button')));
      await tester.pumpAndSettle();

      expect(gameState.totalCoins, 0);
      expect(gameState.currentLevel, 1);
      expect(gameState.runHistory, isEmpty,
          reason: 'the shift history resets with everything else');
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
      // A tall surface so every about tile is on screen and tappable (the
      // garage tests use the same trick).
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('settings_credits_tile')));
      await tester.pumpAndSettle();

      expect(find.byType(CreditsScreen), findsOneWidget);
    });

    testWidgets('records is reachable from settings', (tester) async {
      // The records screen (issue #21) is where personal bests and the
      // achievement set live; the tile must lead to the real screen.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('settings_records_tile')));
      await tester.pumpAndSettle();

      expect(find.byType(RecordsScreen), findsOneWidget);
      expect(find.textContaining('coming soon'), findsNothing);
    });

    testWidgets('shift stats is reachable from settings', (tester) async {
      // The on-device history (issue #17) is only worth having if it can
      // actually be opened: the tile must lead to the real screen.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('settings_stats_tile')));
      await tester.pumpAndSettle();

      expect(find.byType(StatsScreen), findsOneWidget);
      expect(find.textContaining('coming soon'), findsNothing);
    });

    testWidgets('the sound and music switches drive the save settings',
        (tester) async {
      // Audio is real now (issue #4), so the toggles belong here — wired to
      // the same settings the running audio service obeys.
      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      SwitchListTile soundToggle =
          tester.widget(find.byKey(const ValueKey('sound_toggle')));
      SwitchListTile musicToggle =
          tester.widget(find.byKey(const ValueKey('music_toggle')));
      expect(soundToggle.value, isTrue);
      expect(musicToggle.value, isTrue);

      await tester.tap(find.byKey(const ValueKey('sound_toggle')));
      await tester.pumpAndSettle();
      expect(gameState.soundEnabled, isFalse,
          reason: 'the sound switch flips the save setting');

      await tester.tap(find.byKey(const ValueKey('music_toggle')));
      await tester.pumpAndSettle();
      expect(gameState.musicEnabled, isFalse,
          reason: 'the music switch flips the save setting');

      soundToggle = tester.widget(find.byKey(const ValueKey('sound_toggle')));
      musicToggle = tester.widget(find.byKey(const ValueKey('music_toggle')));
      expect(soundToggle.value, isFalse);
      expect(musicToggle.value, isFalse);
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
