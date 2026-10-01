import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/levels/level.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/credits_screen.dart';
import 'package:taxi_game/ui/screens/garage_screen.dart';
import 'package:taxi_game/ui/screens/main_menu_screen.dart';
import 'package:taxi_game/ui/screens/records_screen.dart';
import 'package:taxi_game/ui/screens/settings_screen.dart';
import 'package:taxi_game/ui/screens/stats_screen.dart';

import 'helpers/fake_audio_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;
  late StorageService storage;
  late HapticsService haptics;
  late AudioService audio;

  setUp(() async {
    installFakeAudioPlatform();
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    haptics = HapticsService();
    audio = AudioService();
    // Mirror main()'s live forwarding (issues #4 and #5): each save setting
    // drives the running service's gate on every notify, exactly as the
    // composition root does in production.
    gameState.addListener(() {
      audio.setSoundEnabled(gameState.soundEnabled);
      audio.setMusicEnabled(gameState.musicEnabled);
      haptics.setEnabled(gameState.vibrationEnabled);
    });
  });

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          Provider<AudioService>.value(value: audio),
          Provider<HapticsService>.value(value: haptics),
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

    testWidgets(
        'a finished tutorial says so instead of counting a phantom rung '
        '(issue #109)', (tester) async {
      // Completing the last rung parks the stored counter at
      // ladderLength + 1 — the deliberate "done" sentinel (issue #16),
      // never a real level. Walk a fresh save up the whole ladder the
      // way gameplay does, one furthest-level completion at a time.
      for (var rung = 1; rung <= GameLevel.ladderLength; rung++) {
        gameState.completeLevel(rung, 10);
      }
      expect(gameState.currentLevel, GameLevel.ladderLength + 1,
          reason: 'the ladder walk must reach the done sentinel first');
      expect(gameState.tutorialComplete, isTrue);

      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      // The card branches like the menu does: no "Level 11" exists to
      // show, and the coins still stand next to the finished-ladder
      // wording.
      expect(find.textContaining('Level 11'), findsNothing);
      expect(find.textContaining('Tutorial complete'), findsOneWidget);
      expect(
        find.textContaining(
            'Tutorial complete · ${GameLevel.ladderLength * 10} coins'),
        findsOneWidget,
        reason: 'the coins ride along, as they did beside the rung count',
      );
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

  group('vibration (issue #5)', () {
    testWidgets('the vibration switch drives the save setting',
        (tester) async {
      // The save always carried vibrationEnabled; the switch that moves it
      // belongs here next to its audio siblings.
      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      SwitchListTile vibrationToggle =
          tester.widget(find.byKey(const ValueKey('vibration_toggle')));
      expect(vibrationToggle.value, isTrue,
          reason: 'a fresh save vibrates by default');

      await tester.tap(find.byKey(const ValueKey('vibration_toggle')));
      await tester.pumpAndSettle();
      expect(gameState.vibrationEnabled, isFalse,
          reason: 'the vibration switch flips the save setting');

      vibrationToggle =
          tester.widget(find.byKey(const ValueKey('vibration_toggle')));
      expect(vibrationToggle.value, isFalse);

      await tester.tap(find.byKey(const ValueKey('vibration_toggle')));
      await tester.pumpAndSettle();
      expect(gameState.vibrationEnabled, isTrue);
    });

    testWidgets('enabling buzzes its own confirmation; disabling is silent',
        (tester) async {
      // The switch fires its button tick *after* the flip, so the very
      // tap that turns vibration on can be felt — and the tap that turns
      // it off stays quiet. That ordering is the toggle's behaviour proof.
      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();

      // Default is on; first tap turns vibration off.
      await tester.tap(find.byKey(const ValueKey('vibration_toggle')));
      await tester.pumpAndSettle();
      expect(gameState.vibrationEnabled, isFalse);
      expect(haptics.attemptedBuzzes, isEmpty,
          reason: 'turning vibration off fires no buzz');

      // Second tap turns it back on through its own gate.
      await tester.tap(find.byKey(const ValueKey('vibration_toggle')));
      await tester.pumpAndSettle();
      expect(gameState.vibrationEnabled, isTrue);
      expect(haptics.attemptedBuzzes['button_light'], 1,
          reason: 'enabling confirms itself in the hand');
    });
  });

  group('audio (issue #10)', () {
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

      // And the save remembers: the flips persist like every other setting.
      final persisted = await storage.loadSaveData();
      expect(persisted?.settings.soundEnabled, isFalse);
      expect(persisted?.settings.musicEnabled, isFalse);
    });

    testWidgets('the switches reach the running audio service, live',
        (tester) async {
      // The save setting is bookkeeping; what makes the switch functional
      // is the composition root forwarding it into the running service on
      // every notify (mirrored in this harness above). A flip must move the
      // audible gates on the spot — the observable surface is the same one
      // audio_service_test.dart reads.
      //
      // playMusic is not awaited: its platform chain hops through real IO
      // turns that the fake-async widget zone never pumps (the plain-test
      // suite can await it; see audio_service_test.dart's settle()). The
      // *want* is set synchronously before the first platform call, which
      // is everything asserted below.
      unawaited(audio.playMusic());
      await tester.pumpWidget(wrap(const SettingsScreen()));
      await tester.pump();
      expect(audio.isMusicWanted, isTrue,
          reason: 'music enabled plays everywhere, menu included');

      // Turning sound off: the switch's own click is the last sound the
      // gate lets through.
      await tester.tap(find.byKey(const ValueKey('sound_toggle')));
      await tester.pumpAndSettle();
      expect(audio.attemptedPlays, {'button_click': 1},
          reason: 'the disabling tap itself clicks, then the gate closes');

      audio.playSound('crash');
      expect(audio.attemptedPlays, {'button_click': 1},
          reason: 'a muted service attempts nothing');

      // Turning music off stops the wanted track with the switch.
      await tester.tap(find.byKey(const ValueKey('music_toggle')));
      await tester.pumpAndSettle();
      expect(audio.isMusicWanted, isFalse,
          reason: 'the shift backing track stops when music is switched off');
      expect(audio.attemptedPlays, {'button_click': 1},
          reason: 'the music tap clicks into an already-silent service');

      // Both switches back up: the gates reopen.
      await tester.tap(find.byKey(const ValueKey('sound_toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('music_toggle')));
      await tester.pumpAndSettle();
      audio.playSound('crash');
      expect(audio.attemptedPlays['crash'], 1,
          reason: 'sound enabled again reaches for the player');
      // Clicks: the sound-off tap (gate open) and the music-on tap (gate
      // open again); the two taps made while muted stayed silent.
      expect(audio.attemptedPlays['button_click'], 2);
      expect(audio.isMusicWanted, isTrue,
          reason: 'the wanted track comes back when music is switched on');
    });
  });

  group('diagnostics', () {
    testWidgets('the section offers share and clear', (tester) async {
      await tester.pumpWidget(wrap(const SettingsScreen()));
      // The settings list is lazy: drag the section into the tree before
      // anything can be found in it.
      final button = find.byKey(const Key('share_diagnostics_button'));
      await tester.dragUntilVisible(
          button, find.byType(Scrollable).first, const Offset(0, -200));
      expect(button, findsOneWidget);
      expect(find.byKey(const Key('clear_diagnostics_button')), findsOneWidget);
    });

    testWidgets('a failing share explains itself instead of dying '
        'silently', (tester) async {
      // An un-mocked void channel call resolves silently on modern
      // Flutter, so force the real failure shape: a handler that errors,
      // like a native side with no sheet to present.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('cab_hustle/share'),
              (call) async {
        throw PlatformException(code: 'not_ready');
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
                const MethodChannel('cab_hustle/share'), null);
      });

      await tester.pumpWidget(wrap(const SettingsScreen()));
      final button = find.byKey(const Key('share_diagnostics_button'));
      await tester.dragUntilVisible(
          button, find.byType(Scrollable).first, const Offset(0, -200));
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Could not open the share sheet.'), findsOneWidget,
          reason: 'the diagnostics button never dies silently');
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
