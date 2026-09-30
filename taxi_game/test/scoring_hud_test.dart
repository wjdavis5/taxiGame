import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/systems/fare_chain.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/passenger_data.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/widgets/hud_overlay.dart';

/// The HUD's scoring bar (issue #12): run score, chain multiplier, and the
/// active fare countdown. The bar polls the game on a repeating 100 ms
/// timer, so these tests always pump fixed durations — never
/// pumpAndSettle.
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

  /// A 50-coin fare waiting at the left kerb, 700 px from its dropoff.
  PassengerData waitingFare() => PassengerData(
        id: 'hud_fare',
        pickupLocation: Vector2(85, 400),
        dropoffLocation: Vector2(85, -300),
        reward: 50,
      );

  Widget hudFor(TaxiGame game) =>
      ChangeNotifierProvider<GameStateService>.value(
        value: gameState,
        child: MaterialApp(home: Scaffold(body: HudOverlay(game: game))),
      );

  TaxiGame levelGame() => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      );

  testWidgets('an idle run shows the score at 1x with no meter running',
      (tester) async {
    await tester.pumpWidget(hudFor(levelGame()));
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('SCORE 0'), findsOneWidget);
    expect(find.text('\u00d71'), findsOneWidget,
        reason: 'the multiplier is always visible, even before any fare');
    expect(find.byIcon(Icons.timer), findsNothing,
        reason: 'no passenger, no countdown');
    expect(find.text('LATE'), findsNothing);
  });

  testWidgets('a boarding passenger starts the visible countdown',
      (tester) async {
    final game = levelGame();
    await tester.pumpWidget(hudFor(game));
    await tester.pump(const Duration(milliseconds: 150));

    game.fareChain.startFare(waitingFare());
    await tester.pump(const Duration(milliseconds: 150)); // poll tick

    // The meter reads tenths of a second — the fare's budget is 6 s +
    // 700 px / 75 px/s, so well above ten.
    expect(find.byIcon(Icons.timer), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'^\d+\.\ds$')),
      findsOneWidget,
    );
    expect(find.text('LATE'), findsNothing);
  });

  testWidgets('an expired meter reads LATE while the passenger is still '
      'aboard', (tester) async {
    final game = levelGame();
    await tester.pumpWidget(hudFor(game));
    await tester.pump(const Duration(milliseconds: 150));

    game.fareChain.startFare(waitingFare());
    await tester.pump(const Duration(milliseconds: 150));

    // Burn the whole budget in one step.
    game.fareChain.update(FareChain.maxFareSeconds + 1);
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('LATE'), findsOneWidget);
    expect(find.byIcon(Icons.timer_off), findsOneWidget);
    expect(game.fareChain.multiplier, 1,
        reason: 'the HUD reflects the chain the expiry broke');
  });

  testWidgets('an on-time delivery banks the score, steps the multiplier, '
      'and stops the meter', (tester) async {
    final game = levelGame();
    await tester.pumpWidget(hudFor(game));
    await tester.pump(const Duration(milliseconds: 150));

    final fare = waitingFare();
    game.fareChain.startFare(fare);
    await tester.pump(const Duration(milliseconds: 150));

    game.fareChain.completeFare(fare, fareValue: fare.reward);
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('SCORE 50'), findsOneWidget);
    expect(find.text('\u00d72'), findsOneWidget,
        reason: 'the next fare rides at 2x');
    expect(find.byIcon(Icons.timer), findsNothing);
    expect(find.byIcon(Icons.timer_off), findsNothing,
        reason: 'delivered, so no meter at all');
  });

  group('the ghost gap badge (issue #20)', () {
    Future<void> plantGhost() async {
      await gameState.recordDailyGhostRun(
        dateKey: DailyShift.todayKey,
        score: 500,
        banked: true,
        vehicleId: 'taxi_yellow',
        samples: const [200, 0, 200, -100, 200, -200],
      );
    }

    /// A ghost race mounted headlessly — the badge reads live positions
    /// off the game, so an unmounted one cannot exercise it.
    Future<TaxiGame> mountedGhostRace(WidgetTester tester) async {
      await plantGhost();
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: DailyShift.seedForDateKey(DailyShift.todayKey),
        isGhostRace: true,
      );
      await tester.runAsync(() async {
        game.onGameResize(Vector2(400, 800));
        await game.onLoad();
        // ignore: invalid_use_of_internal_member
        game.mount();
        await game.ready();
      });
      return game;
    }

    testWidgets('a live ghost shows the gap; none hides it',
        (tester) async {
      final game = await mountedGhostRace(tester);

      // No GameWidget drives a headless game: tick the run by hand so
      // the ghost advances down the road while the player holds the
      // start line.
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }

      await tester.pumpWidget(hudFor(game));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byKey(const ValueKey('ghost_badge')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^GHOST [+-]?\d+ m$')),
          findsOneWidget);
      expect(find.text('AT RISK 0'), findsOneWidget,
          reason: 'an endless run labels its score with what it is: '
              'forfeit-able until banked, unlike the wallet beside it');
      expect(game.ghostGapMetres!, lessThan(0),
          reason: 'the ghost is down the road; the player is behind');

      // Take the ghost off the road (as free play would never have one):
      // the badge goes with it rather than showing a gap to nothing.
      game.ghostCar = null;
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(const ValueKey('ghost_badge')), findsNothing);
    });

    testWidgets('an unmounted endless shift has no ghost and no badge',
        (tester) async {
      await tester.pumpWidget(hudFor(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: 7,
      )));
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byKey(const ValueKey('ghost_badge')), findsNothing);
    });

    testWidgets('the worst-case wide HUD fits a 375 pt phone (issue #43)',
        (tester) async {
      // The overflow report's worst case, gathered on one screen: a live
      // ghost gap, a carried fare, a 4-digit at-risk score, and the
      // multiplier maxed — on the narrowest iPhone width. Before the fix
      // this was a 141 px overflow that pushed the fare timer and the
      // multiplier fully off-screen.
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final game = await mountedGhostRace(tester);
      // The ghost gap goes live as the replay runs away from the start
      // line — same hand-ticked drive the badge test above uses.
      for (var i = 0; i < 30; i++) {
        game.update(1 / 60);
      }
      game.fareChain
        ..score = 1234
        ..multiplier = 10
        ..startFare(waitingFare());

      await tester.pumpWidget(hudFor(game));
      await tester.pump(const Duration(milliseconds: 150)); // poll tick

      // The overflow stripe is a layout exception in tests: none means
      // the row fits.
      expect(tester.takeException(), isNull);
      // And the chips it used to shove off-screen are fully on it — the
      // HUD's content area ends 16 px short of the 375 pt surface.
      const contentRight = 375.0 - 16.0;
      final timerRect = tester.getRect(find.byIcon(Icons.timer));
      expect(timerRect.right, lessThanOrEqualTo(contentRight));
      expect(timerRect.left, greaterThan(0));
      final multiplierRect = tester.getRect(find.text('\u00d710'));
      expect(multiplierRect.right, lessThanOrEqualTo(contentRight));
      expect(multiplierRect.left, greaterThan(0));
      // The ghost badge survived the reflow — on its own line below the
      // row, still exactly one of it.
      expect(find.byKey(const ValueKey('ghost_badge')), findsOneWidget);
      expect(find.text('AT RISK 1234'), findsOneWidget);
    });
  });
}
