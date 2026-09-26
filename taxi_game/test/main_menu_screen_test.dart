import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/models/daily_result.dart';
import 'package:taxi_game/services/audio_service.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/main_menu_screen.dart';
import 'package:taxi_game/ui/screens/records_screen.dart';

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
    expect(find.text('CAB HUSTLE'), findsOneWidget);
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

  testWidgets('garage button is present and enabled', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final garageButton = find.byKey(const ValueKey('garage_button'));
    expect(garageButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(garageButton).onPressed, isNotNull);
  });

  testWidgets('endless shift button is present and enabled', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final endlessButton = find.byKey(const ValueKey('endless_button'));
    expect(endlessButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(endlessButton).onPressed, isNotNull);
    expect(find.text('ENDLESS SHIFT'), findsOneWidget);
  });

  testWidgets('endless shift is the first button on the menu — the '
      'primary mode, not a secondary one (issue #15)', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final endlessButton = find.byKey(const ValueKey('endless_button'));
    final playButton = find.byKey(const Key('play_button'));
    expect(
      tester.getRect(endlessButton).top,
      lessThan(tester.getRect(playButton).top),
      reason: 'endless sits above the career ladder',
    );

    // And it is styled as the primary action: the yellow signature
    // colour, while the ladder button steps back in white.
    final endlessColor =
        tester.widget<ElevatedButton>(endlessButton).style?.backgroundColor;
    final playColor =
        tester.widget<ElevatedButton>(playButton).style?.backgroundColor;
    expect(endlessColor, isNot(playColor),
        reason: 'the headline mode is styled like one');
  });

  testWidgets('the personal best shows under the endless button once a '
      'shift has ended (issue #15)', (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();
    expect(find.text('BEST 340'), findsNothing,
        reason: 'a new player has no best to show');

    gameStateService.recordEndlessScore(340);
    await tester.pump();

    expect(find.text('BEST 340'), findsOneWidget);
  });

  testWidgets('records button is present and opens the records screen',
      (tester) async {
    final storageService = StorageService();
    await storageService.init();
    final gameStateService = GameStateService(storageService);

    await tester.pumpWidget(buildMenu(gameStateService, storageService));
    await tester.pump();

    final recordsButton = find.byKey(const Key('records_button'));
    expect(recordsButton, findsOneWidget);
    expect(tester.widget<ElevatedButton>(recordsButton).onPressed, isNotNull);
    expect(find.text('RECORDS'), findsOneWidget);

    await tester.ensureVisible(recordsButton);
    await tester.tap(recordsButton);
    await tester.pumpAndSettle();

    expect(find.byType(RecordsScreen), findsOneWidget);
  });

  group('daily shift (issue #19)', () {
    testWidgets('button is present and enabled with today\'s date status',
        (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      final dailyButton = find.byKey(const ValueKey('daily_button'));
      expect(dailyButton, findsOneWidget);
      expect(tester.widget<ElevatedButton>(dailyButton).onPressed, isNotNull);
      expect(find.text('DAILY SHIFT'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('daily_status')),
        findsOneWidget,
      );
      expect(find.textContaining(DailyShift.todayKey), findsOneWidget,
          reason: 'the shared course is the date, shown on the menu');
      expect(find.textContaining('ONE SHIFT'), findsOneWidget);
    });

    testWidgets('the daily is the first button on the menu — the day\'s '
        'ritual comes before the open-ended mode', (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      final dailyButton = find.byKey(const ValueKey('daily_button'));
      final endlessButton = find.byKey(const ValueKey('endless_button'));
      expect(
        tester.getRect(dailyButton).top,
        lessThan(tester.getRect(endlessButton).top),
        reason: 'today\'s shared course leads the menu',
      );
    });

    testWidgets('once today\'s daily has ended, the button shows the day '
        'is done instead of offering a replay', (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();
      expect(find.text('DAILY COMPLETE'), findsNothing);

      await gameStateService.recordDailyResult(DailyResult(
        dateKey: DailyShift.todayKey,
        score: 340,
        banked: true,
        completedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));
      await tester.pump();

      expect(find.text('DAILY COMPLETE'), findsOneWidget);
      expect(find.text('DAILY SHIFT'), findsNothing);
      expect(find.textContaining('340 PTS'), findsOneWidget,
          reason: 'the day\'s score stays on the menu until midnight');

      final dailyButton = find.byKey(const ValueKey('daily_button'));
      expect(tester.widget<ElevatedButton>(dailyButton).onPressed, isNotNull,
          reason: 'done is not dead — the button opens the day\'s result');
    });

    testWidgets('a completed daily button opens the daily result screen',
        (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);
      await gameStateService.recordDailyResult(DailyResult(
        dateKey: DailyShift.todayKey,
        score: 340,
        banked: true,
        completedAtMs: DateTime.now().millisecondsSinceEpoch,
      ));

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('daily_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('daily_screen')), findsOneWidget);
    });

    testWidgets('the daily history link opens the daily result screen',
        (tester) async {
      final storageService = StorageService();
      await storageService.init();
      final gameStateService = GameStateService(storageService);

      await tester.pumpWidget(buildMenu(gameStateService, storageService));
      await tester.pump();

      await tester
          .tap(find.byKey(const ValueKey('daily_history_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('daily_screen')), findsOneWidget,
          reason: 'history is reachable even before today\'s shift ends');
    });
  });
}
