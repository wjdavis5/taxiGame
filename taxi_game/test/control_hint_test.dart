import 'dart:convert';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';

/// The one-time stick-control hint (issue #37): a first game start on a
/// save that has never dismissed it teaches the invisible relative stick,
/// the first real stick touch dismisses it for good, and a reset re-arms
/// it — the same wipe convention as the run history.
///
/// The HUD polls the game on a repeating timer, so the widget tests pump
/// fixed durations — never pumpAndSettle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The hint pill's key, as [ControlHintOverlay] mounts it.
  final hintFinder = find.byKey(const ValueKey('controlHint'));

  /// A minimal valid save JSON, as an older build of the game wrote it —
  /// optionally carrying the hint flag for the saves that know it.
  Map<String, dynamic> seasonedSave({bool? controlHintDismissed}) => {
        'currentLevel': 4,
        'totalCoins': 30,
        'totalGems': 0,
        'unlockedVehicles': ['taxi_yellow'],
        'selectedVehicle': 'taxi_yellow',
        'achievements': <String, bool>{},
        'settings': Settings.createDefault().toJson(),
        if (controlHintDismissed != null)
          'controlHintDismissed': controlHintDismissed,
      };

  late GameStateService gameState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  /// Pumps a live endless [GameScreen] on a fresh save.
  Future<TaxiGame> pumpGameScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
          Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        ],
        child: const MaterialApp(home: GameScreen(endlessSeed: 42)),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final game = tester
        .widget<GameWidget<TaxiGame>>(find.byType(GameWidget<TaxiGame>))
        .game!;
    expect(game.isGameActive, isTrue,
        reason: 'the endless run must be live before any input');
    return game;
  }

  /// Pumps a follow-up [GameScreen] on [service] — the next session's
  /// first render. The screen is keyed so it cannot reuse the first
  /// session's state: a real next session constructs the screen anew,
  /// and only then is the hint decision made.
  Future<void> pumpNextSession(WidgetTester tester, GameStateService service,
      {int seed = 43}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: service),
          Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        ],
        child: MaterialApp(
          home: GameScreen(
            key: ValueKey('session-$seed'),
            endlessSeed: seed,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('a fresh save (issue #37)', () {
    testWidgets('the first game start shows the stick-control hint',
        (tester) async {
      await pumpGameScreen(tester);

      expect(hintFinder, findsOneWidget);
      expect(find.textContaining('Touch and hold the lower half'),
          findsOneWidget,
          reason: 'the hint names the invisible control in the stick\'s '
              'own terms');
    });

    testWidgets('the first real stick input dismisses it and drives the taxi',
        (tester) async {
      final game = await pumpGameScreen(tester);
      expect(hintFinder, findsOneWidget);

      // A real stick drag on the lower half: glide up-right past the rim.
      final gesture = await tester.startGesture(const Offset(400, 450));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(72, -144));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));

      expect(hintFinder, findsNothing,
          reason: 'the thumb landed where the hint said it would');
      expect(gameState.controlHintDismissed, isTrue);
      expect(game.player.throttleInput, greaterThan(0.8),
          reason: 'the dismissal came from a real input, not a timer');

      await gesture.up();
    });

    testWidgets('a tap on the hint itself dismisses it', (tester) async {
      await pumpGameScreen(tester);
      expect(hintFinder, findsOneWidget);

      // The hint sits inside the stick's touch region, so a tap on it is
      // a lower-half touch: down, up, no movement.
      final gesture =
          await tester.startGesture(tester.getCenter(hintFinder));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));

      expect(hintFinder, findsNothing);
      expect(gameState.controlHintDismissed, isTrue);
    });

    testWidgets('the dismissal persists — the next session renders no hint',
        (tester) async {
      await pumpGameScreen(tester);

      final gesture = await tester.startGesture(const Offset(400, 450));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, -160));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(hintFinder, findsNothing);

      // Flush the fire-and-forget save so the reload below reads the
      // on-device state a real device would already have.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );

      // Simulate an app restart: a brand-new service stack reading the
      // same on-device store.
      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();
      expect(reloaded.controlHintDismissed, isTrue);

      await pumpNextSession(tester, reloaded);
      expect(hintFinder, findsNothing,
          reason: 'the flag is set before the next session renders');
    });
  });

  group('a seasoned save', () {
    testWidgets('a save from before this feature is never shown the hint',
        (tester) async {
      // A pre-issue-#37 save: no hint flag at all — its player has
      // already driven.
      SharedPreferences.setMockInitialValues(
          {StorageService.saveDataKey: jsonEncode(seasonedSave())});
      final storage = StorageService();
      await storage.init();
      gameState = GameStateService(storage);
      await gameState.loadSaveData();

      await pumpGameScreen(tester);

      expect(hintFinder, findsNothing);
      expect(gameState.controlHintDismissed, isTrue,
          reason: 'the missing flag reads as dismissed, never re-arms');
    });

    testWidgets('a save that dismissed the hint once is never shown it again',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        StorageService.saveDataKey:
            jsonEncode(seasonedSave(controlHintDismissed: true)),
      });
      final storage = StorageService();
      await storage.init();
      gameState = GameStateService(storage);
      await gameState.loadSaveData();

      await pumpGameScreen(tester);
      expect(hintFinder, findsNothing);
    });
  });

  group('the save flag', () {
    test('a fresh save has not dismissed the hint, and false round-trips',
        () {
      final fresh = SaveData.createDefault();
      expect(fresh.controlHintDismissed, isFalse);

      final round = SaveData.fromJson(fresh.toJson());
      expect(round.controlHintDismissed, isFalse,
          reason: 'a fresh save stays teachable across sessions');
    });

    test('a save written before the hint existed loads as dismissed', () {
      final preFlag = SaveData.fromJson(seasonedSave());

      expect(preFlag.controlHintDismissed, isTrue,
          reason: 'a missing key means "already a player", not "unseen"');
      expect(SaveData.fromJson(preFlag.toJson()).controlHintDismissed, isTrue,
          reason: 'and it round-trips into new saves');
    });

    test('dismissing the hint persists and is idempotent', () async {
      gameState.dismissControlHint();
      gameState.dismissControlHint();

      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();

      expect(reloaded.controlHintDismissed, isTrue);
    });

    test('resetting progress re-arms the hint', () async {
      gameState.dismissControlHint();
      expect(gameState.controlHintDismissed, isTrue);

      gameState.resetProgress();
      expect(gameState.controlHintDismissed, isFalse,
          reason: 'a wiped save is a first-time player again');

      final reloadedStorage = StorageService();
      await reloadedStorage.init();
      final reloaded = GameStateService(reloadedStorage);
      await reloaded.loadSaveData();
      expect(reloaded.controlHintDismissed, isFalse);
    });
  });

  group('after a reset', () {
    testWidgets('the next game start teaches the stick again',
        (tester) async {
      await pumpGameScreen(tester);
      expect(hintFinder, findsOneWidget);

      // Dismiss the hint the way a player does.
      final gesture = await tester.startGesture(const Offset(400, 450));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(0, -160));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      expect(hintFinder, findsNothing);

      // Wipe everything, same as the settings screen does.
      gameState.resetProgress();
      await tester.pump();
      expect(gameState.controlHintDismissed, isFalse);

      await pumpNextSession(tester, gameState, seed: 44);
      expect(hintFinder, findsOneWidget,
          reason: 'the wiped save is taught once more');
    });
  });
}
