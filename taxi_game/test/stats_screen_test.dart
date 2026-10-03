import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/models/run_record.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/stats_screen.dart';

/// The on-device stats screen (issue #17): shows the aggregates over the
/// shift history, an honest empty state before any shift has ended, and
/// survives a narrow portrait phone without overflowing.
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
    List<double> lifeLossesPx = const [],
    bool banked = true,
    double durationSeconds = 65,
  }) {
    return gameState.recordEndlessRun(RunRecord(
      endedAtMs: 0,
      distancePx: distancePx,
      score: score,
      faresDelivered: fares,
      longestChain: chain,
      livesLost: lifeLossesPx.length,
      lifeLossDistancesPx: lifeLossesPx,
      banked: banked,
      durationSeconds: durationSeconds,
    ));
  }

  group('before any shift has ended', () {
    testWidgets('an empty history shows the invitation, not blank space',
        (tester) async {
      await tester.pumpWidget(wrap(const StatsScreen()));
      await tester.pump();

      expect(find.byKey(const Key('stats_empty_state')), findsOneWidget);
      expect(find.text('No shifts recorded yet'), findsOneWidget);
      expect(find.text('Shifts ended'), findsNothing);
    });
  });

  group('with a history', () {
    testWidgets('the totals carry the run of shifts', (tester) async {
      await recordRun();
      await recordRun(
        distancePx: 12000,
        score: 80,
        fares: 2,
        chain: 2,
        lifeLossesPx: [3000, 6000],
        banked: false,
        durationSeconds: 125,
      );

      await tester.pumpWidget(wrap(const StatsScreen()));
      await tester.pump();

      expect(find.text('Shifts ended'), findsOneWidget);
      expect(find.byKey(const Key('stats_shifts_total')),
          findsOneWidget);
      expect(
        tester.widget<Text>(
          find.byKey(const Key('stats_shifts_total')),
        ),
        isA<Text>().having((t) => t.data, 'data', '2'),
      );
      expect(find.text('Total score'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      expect(find.text('Distance driven'), findsOneWidget);
      expect(find.text('1.6 km'), findsOneWidget);
      expect(find.text('Fares delivered'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Lives lost'), findsOneWidget);
      expect(find.text('Time driven'), findsOneWidget);
      expect(find.text('3:10'), findsOneWidget);
    });

    testWidgets('the medians describe the typical shift', (tester) async {
      await recordRun();
      await recordRun(
        distancePx: 12000,
        score: 80,
        lifeLossesPx: [3000, 6000],
        banked: false,
        durationSeconds: 125,
      );

      await tester.pumpWidget(wrap(const StatsScreen()));
      await tester.pump();

      expect(find.text('Median score'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('Median distance'), findsOneWidget);
      expect(find.text('800 m'), findsOneWidget);
      expect(find.text('Median duration'), findsOneWidget);
      expect(find.text('1:35'), findsOneWidget);
      expect(find.text('Median crash distance'), findsOneWidget);
      expect(find.text('450 m'), findsOneWidget,
          reason: 'median of 300 m and 600 m');
    });

    testWidgets('the bank-vs-push ratio counts both endings',
        (tester) async {
      await recordRun(banked: true);
      await recordRun(banked: false);

      await tester.pumpWidget(wrap(const StatsScreen()));
      await tester.pump();

      expect(find.text('Banked at a dropoff'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('stats_banked_count'))),
        isA<Text>().having((t) => t.data, 'data', '1'),
      );
      expect(find.text('Wrecked, score forfeited'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('stats_forfeited_count'))),
        isA<Text>().having((t) => t.data, 'data', '1'),
      );
      expect(
        find.byKey(const Key('stats_banked_share')),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('stats_banked_share'))),
        isA<Text>()
            .having((t) => t.data, 'data', '50% of recent shifts end in a bank'),
      );
    });

    testWidgets('the run-length bands are all shown', (tester) async {
      await recordRun(distancePx: 4000); // 400 m
      await recordRun(distancePx: 12000); // 1.2 km

      await tester.pumpWidget(wrap(const StatsScreen()));
      await tester.pump();

      expect(find.text('Under 500 m'), findsOneWidget);
      expect(find.text('500 m – 1 km'), findsOneWidget);
      expect(find.text('1 – 2 km'), findsOneWidget);
      expect(find.text('2 – 4 km'), findsOneWidget);
      expect(find.text('Over 4 km'), findsOneWidget);
    });

    testWidgets(
        'the totals keep counting past the 200-shift window (issue #183)',
        (tester) async {
      // The issue's own case at widget level: maxRecordedRuns + 1 shifts
      // recorded, the first fallen off the window, and every Totals row
      // still counting all of them.
      for (var i = 1; i <= GameStateService.maxRecordedRuns + 1; i++) {
        await recordRun(score: i);
      }

      await tester.pumpWidget(wrap(const StatsScreen()));
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('stats_shifts_total'))),
        isA<Text>().having((t) => t.data, 'data',
            '${GameStateService.maxRecordedRuns + 1}'),
        reason: 'the window pins at maxRecordedRuns — the row is the '
            'lifetime count, or the issue is back',
      );
      expect(find.text('20301'), findsOneWidget,
          reason: 'the sum of scores 1..201 — the window would show the '
              'sum of 2..201');
      expect(find.text('603'), findsOneWidget,
          reason: '3 fares × 201 shifts');
      expect(find.text('3:37:45'), findsOneWidget,
          reason: '65 s × 201 shifts, as a clock');
      expect(find.text('80.4 km'), findsOneWidget,
          reason: '400 m × 201 shifts');
    });

    testWidgets(
        'the window-scoped sections name their window once shifts age out '
        '(issue #192)',
        (tester) async {
      // The issue's own complaint: "Shifts ended" shows 201 while Banked
      // + Wrecked and the run-length bands still sum to 200, and nothing
      // on screen says those sections cover only the recent shifts. The
      // fix is a caption on each of the four window-scoped sections.
      for (var i = 1; i <= GameStateService.maxRecordedRuns + 1; i++) {
        await recordRun(score: i);
      }

      await tester.pumpWidget(wrap(const StatsScreen()));
      await tester.pump();

      expect(
        find.text(
            'Covers only your last ${GameStateService.maxRecordedRuns} shifts.'),
        findsNWidgets(4),
        reason: 'one caption per window-scoped section: typical shift, '
            'run lengths, bank or push, crashes',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('stats_banked_share'))),
        isA<Text>().having((t) => t.data, 'data',
            '100% of recent shifts end in a bank'),
        reason: 'the share claims recent shifts, not shifts at large',
      );
      expect(find.text('How far recent shifts drove, in bands.'),
          findsOneWidget,
          reason: 'the bands footer claims recent shifts too');
    });

    testWidgets(
        'no window caption while the history holds every shift ever ended',
        (tester) async {
      // Below the trim point the window *is* the whole history — every
      // number on the screen already agrees, so the caption stays out of
      // sight rather than calling a difference that does not exist.
      await recordRun();
      await recordRun(banked: false);

      await tester.pumpWidget(wrap(const StatsScreen()));
      await tester.pump();

      expect(find.textContaining('Covers only'), findsNothing);
    });
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
      lifeLossesPx: [1000, 20000, 25000],
      banked: false,
      durationSeconds: 3725,
    );

    await tester.pumpWidget(wrap(const StatsScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
