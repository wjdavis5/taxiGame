import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/systems/run_summary.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/share_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/widgets/share_score_button.dart';

/// The SHARE SCORE button (issue #22): taps render the settled shift
/// into a card and hand it to the share channel; a failure surfaces as a
/// message instead of a dead tap.
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

  /// Clears the platform override inside the test body — the binding
  /// verifies its invariants before dart-test teardowns run.
  void clearPlatformOverride() {
    debugDefaultTargetPlatformOverride = null;
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ShareService.channel, null);
  });

  const bankedSummary = RunSummary(
    outcome: ShiftOutcome.banked,
    score: 1234,
    bestChain: 4,
    faresDelivered: 12,
    distancePx: 12340,
    coinsEarned: 195,
    isPersonalBest: true,
    previousBest: 1100,
  );

  /// An unmounted daily game: the button reads only the summary snapshot
  /// and the game's seed/flags — the run-summary tests use the same
  /// unmounted-game pattern.
  TaxiGame dailyGame() => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: 9,
        isDailyShift: true,
      );

  Future<void> showButton(WidgetTester tester, TaxiGame game) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ShareScoreButton(game: game, summary: bankedSummary),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The render + channel round-trip runs real async work inside the
  /// widget tree; [runAsync] lets it finish, then the tree is pumped to
  /// show whatever the completion did.
  Future<void> letSharingFinish(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }

  testWidgets('a tap hands a rendered card to the share channel',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ShareService.channel, (call) async {
        calls.add(call);
        return null;
      });

      await showButton(tester, dailyGame());
      await tester.tap(find.byKey(const ValueKey('share_score_button')));
      await letSharingFinish(tester);

      expect(calls, hasLength(1));
      expect(calls.single.method, 'shareScoreCard');
      final args = calls.single.arguments as Map<Object?, Object?>;
      final png = args['png'] as List<int>;
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47],
          reason: 'what reaches the sheet is a PNG, not raw pixels');
      final text = args['text'] as String;
      expect(text, contains('1234 pts'));
      // The unmounted game never pinned a day, so the card dates itself
      // to today and carries the run's seed — the day's course, findable.
      expect(text, contains('seed 9'));
      expect(text, contains(DailyShift.todayKey));
    } finally {
      clearPlatformOverride();
    }
  });

  testWidgets('the button shows it is working, and recovers after',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ShareService.channel, (call) async {
        return null;
      });

      await showButton(tester, dailyGame());
      await tester.tap(find.byKey(const ValueKey('share_score_button')));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('share_score_button')),
      );
      expect(button.onPressed, isNull,
          reason: 'no second sheet while the first is being made');

      await letSharingFinish(tester);
      final settled = tester.widget<ElevatedButton>(
        find.byKey(const ValueKey('share_score_button')),
      );
      expect(settled.onPressed, isNotNull,
          reason: 'the next share must be one tap away');
    } finally {
      clearPlatformOverride();
    }
  });

  testWidgets('a failed share says so instead of dying quietly',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ShareService.channel, (call) async {
        throw PlatformException(code: 'stage_failed');
      });

      await showButton(tester, dailyGame());
      await tester.tap(find.byKey(const ValueKey('share_score_button')));
      await letSharingFinish(tester);

      expect(find.text('Could not open the share sheet.'), findsOneWidget);
    } finally {
      clearPlatformOverride();
    }
  });

  testWidgets('a platform without a native handler fails the same way',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      // No handler registered: MissingPluginException — the Android case.
      await showButton(tester, dailyGame());
      await tester.tap(find.byKey(const ValueKey('share_score_button')));
      await letSharingFinish(tester);

      expect(find.text('Could not open the share sheet.'), findsOneWidget);
    } finally {
      clearPlatformOverride();
    }
  });
}
