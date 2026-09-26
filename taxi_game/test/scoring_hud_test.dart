import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}
