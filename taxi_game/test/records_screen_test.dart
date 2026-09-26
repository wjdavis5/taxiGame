import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/models/achievements.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/records_screen.dart';

/// The records screen (issue #21): the four personal bests, the whole
/// achievement set with earned/locked states and progress toward the
/// locked ones, and a narrow portrait screen it must never overflow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
  });

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
        ],
        child: MaterialApp(home: child),
      );

  Future<void> recordRun({
    double distancePx = 4000,
    int score = 120,
    int fares = 3,
    int chain = 4,
    bool banked = true,
  }) {
    return gameState.recordEndlessRun(RunRecord(
      endedAtMs: 0,
      distancePx: distancePx,
      score: score,
      faresDelivered: fares,
      longestChain: chain,
      livesLost: 0,
      lifeLossDistancesPx: const [],
      banked: banked,
      durationSeconds: 60,
    ));
  }

  testWidgets('a new player sees zeroed records and the full set',
      (tester) async {
    await tester.pumpWidget(wrap(const RecordsScreen()));
    await tester.pump();

    // The four personal bests, all zero — an invitation, not a blank.
    expect(
      tester.widget<Text>(find.byKey(const Key('records_pb_score'))).data,
      '0',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('records_pb_chain'))).data,
      '\u00d70',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('records_pb_distance'))).data,
      '0 m',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('records_pb_fares'))).data,
      '0',
    );

    // Every achievement is on the screen, locked with progress at zero.
    expect(find.byType(RecordsScreen), findsOneWidget);
    for (final achievement in AchievementCatalog.all) {
      expect(
        find.byKey(Key('achievement_card_${achievement.id}')),
        findsOneWidget,
        reason: '${achievement.id} must be listed',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(Key('achievement_progress_${achievement.id}')),
            )
            .data,
        // The starter cab is owned from the first launch, so the fleet
        // measure reads 1 on a fresh save — every cars tier shows 1 of N.
        achievement.id.startsWith('cars_')
            ? '1/${achievement.threshold}'
            : '0/${achievement.threshold}',
      );
    }
    expect(
      tester.widget<Text>(
        find.byKey(const Key('records_achievement_count')),
      ).data,
      '0 of ${AchievementCatalog.all.length} earned',
    );
    expect(find.text('EARNED'), findsNothing);
  });

  testWidgets('records and earned states render from the save',
      (tester) async {
    await recordRun(
      score: 340,
      distancePx: 12000,
      fares: 9,
      chain: 5,
      banked: true,
    );
    await tester.pumpWidget(wrap(const RecordsScreen()));
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('records_pb_score'))).data,
      '340',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('records_pb_chain'))).data,
      '\u00d75',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('records_pb_distance'))).data,
      '1.2 km',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('records_pb_fares'))).data,
      '9',
    );

    // The chain run earned chain_3 and chain_5, the 1 km distance tier,
    // and the clean bank: their cards flip to EARNED and lose the
    // progress line.
    expect(find.text('EARNED'), findsNWidgets(4));
    expect(
      find.byKey(const Key('achievement_progress_chain_5')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('achievement_progress_distance_1000')),
      findsNothing,
    );
    // Locked achievements show live progress against their threshold.
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('achievement_progress_distance_3000')),
          )
          .data,
      '1200/3000',
      reason: 'progress shows the measured value against the threshold',
    );
    expect(
      tester.widget<Text>(
        find.byKey(const Key('records_achievement_count')),
      ).data,
      '4 of ${AchievementCatalog.all.length} earned',
    );
  });

  testWidgets('the back button pops', (tester) async {
    await tester.pumpWidget(wrap(
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const RecordsScreen()),
            ),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordsScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('records_back_button')));
    await tester.pumpAndSettle();
    expect(find.byType(RecordsScreen), findsNothing);
  });

  testWidgets('renders without overflow on a narrow portrait screen',
      (tester) async {
    tester.view.physicalSize = const Size(750, 1334);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await recordRun(
      distancePx: 26000,
      score: 1234,
      fares: 12,
      chain: 9,
      banked: true,
    );

    await tester.pumpWidget(wrap(const RecordsScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
