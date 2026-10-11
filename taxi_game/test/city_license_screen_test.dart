import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/models/city_license.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/haptics_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/city_license_screen.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';
import 'package:taxi_game/ui/screens/garage_screen.dart';
import 'package:taxi_game/ui/widgets/cab_button.dart';
import 'helpers/fake_audio_platform.dart';

/// The City License board screen (issue #278): every objective renders
/// with its status, completion flips a card to DONE without a reload, and
/// each card's attempt button does what its label says — a fresh shift,
/// or the garage for a car the save does not own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameStateService;
  late StorageService storageService;

  setUp(() async {
    installFakeAudioPlatform();
    SharedPreferences.setMockInitialValues({});
    storageService = StorageService();
    await storageService.init();
    gameStateService = GameStateService(storageService);
    await gameStateService.loadSaveData();
  });

  Widget buildBoard() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<GameStateService>.value(
            value: gameStateService),
        Provider<AudioService>.value(value: AudioService()),
        Provider<HapticsService>.value(value: HapticsService()),
        Provider<LevelLoaderService>.value(value: LevelLoaderService()),
        Provider<StorageService>.value(value: storageService),
      ],
      child: const MaterialApp(home: CityLicenseScreen()),
    );
  }

  /// A clean banked shift: completes CLEAN BANK and nothing else.
  Future<void> recordCleanBank() => gameStateService.recordEndlessRun(
        const RunRecord(
          endedAtMs: 0,
          distancePx: 9000,
          score: 300,
          faresDelivered: 3,
          longestChain: 2,
          livesLost: 0,
          lifeLossDistancesPx: [],
          banked: true,
          durationSeconds: 120,
        ),
      );

  testWidgets('every objective renders with its status, and a completion '
      'flips its card to DONE', (tester) async {
    await tester.pumpWidget(buildBoard());
    await tester.pump();

    expect(find.byKey(const Key('city_license_screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('license_progress')), findsOneWidget);
    expect(find.text('0 OF ${CityLicense.board.length} COMPLETE \u2014 '
        'EVERY OBJECTIVE IS REPLAYABLE'), findsOneWidget);
    expect(find.byKey(const ValueKey('license_status_cleanBank')),
        findsOneWidget);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('license_status_cleanBank')))
            .data,
        'OPEN');

    await recordCleanBank();
    await tester.pump();

    expect(find.text('1 OF ${CityLicense.board.length} COMPLETE \u2014 '
        'EVERY OBJECTIVE IS REPLAYABLE'), findsOneWidget);
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('license_status_cleanBank')))
            .data,
        'DONE',
        reason: 'the card rebuilds off the save notification');

    // The board is a lazily built list: scroll it end to end so every
    // objective proves it renders, not just the visible head.
    for (final rule in CityLicense.board) {
      await tester.scrollUntilVisible(
          find.byKey(ValueKey('license_card_${rule.id}')), 200.0);
      expect(find.byKey(ValueKey('license_card_${rule.id}')), findsOneWidget,
          reason: '${rule.id} must be on the board');
    }
  });

  testWidgets('START SHIFT opens a fresh endless shift', (tester) async {
    await tester.pumpWidget(buildBoard());
    await tester.pump();

    final attempt = find.byKey(const ValueKey('license_attempt_cleanBank'));
    expect(tester.widget<CabButton>(attempt).label, 'START SHIFT');
    await tester.scrollUntilVisible(attempt, 200.0);
    await tester.tap(attempt);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GameScreen, skipOffstage: false), findsOneWidget);
  });

  testWidgets('an unowned car objective sends the player to the garage',
      (tester) async {
    await tester.pumpWidget(buildBoard());
    await tester.pump();

    final attempt =
        find.byKey(const ValueKey('license_attempt_compactThread'));
    await tester.scrollUntilVisible(attempt, 300.0);
    await tester.ensureVisible(attempt);
    await tester.pumpAndSettle();
    expect(tester.widget<CabButton>(attempt).label, 'GET THE CAR',
        reason: 'the compact is not owned on a fresh save');
    await tester.tap(attempt);
    await tester.pumpAndSettle();

    expect(find.byType(GarageScreen), findsOneWidget);
    expect(find.byType(GameScreen, skipOffstage: false), findsNothing,
        reason: 'no shift starts in a car the save cannot drive');
  });

  testWidgets('an owned car objective selects the car and starts the shift',
      (tester) async {
    gameStateService.addCoins(5000);
    gameStateService.unlockVehicle('compact_red', 5000);
    await tester.pumpWidget(buildBoard());
    await tester.pump();

    final attempt =
        find.byKey(const ValueKey('license_attempt_compactThread'));
    await tester.scrollUntilVisible(attempt, 300.0);
    await tester.ensureVisible(attempt);
    await tester.pumpAndSettle();
    expect(tester.widget<CabButton>(attempt).label, 'DRIVE IT');
    await tester.tap(attempt);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(gameStateService.selectedVehicle, 'compact_red',
        reason: 'the attempt is driven in the car the objective names');
    expect(find.byType(GameScreen, skipOffstage: false), findsOneWidget);
  });
}
