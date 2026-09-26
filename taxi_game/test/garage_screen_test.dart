import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/data/vehicle_catalog.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/garage_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late GameStateService gameState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
  });

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<GameStateService>.value(value: gameState),
        ],
        child: MaterialApp(home: child),
      );

  /// Pumps the garage on a tall surface so every card is on screen and
  /// tappable. Scrolling behaviour gets its own test on a default surface.
  Future<void> pumpGarage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const GarageScreen()));
    await tester.pump();
  }

  testWidgets('lists every vehicle in the catalog by name', (tester) async {
    await tester.pumpWidget(wrap(const GarageScreen()));
    await tester.pump();

    for (final vehicle in VehicleCatalog.vehicles) {
      await tester.scrollUntilVisible(
        find.text(vehicle.name),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text(vehicle.name),
        findsOneWidget,
        reason: '${vehicle.id} must have a garage card',
      );
    }
  });

  testWidgets('the starter cab is equipped and offers no action', (tester) async {
    await pumpGarage(tester);

    expect(
      find.byKey(const ValueKey('garage_in_use_taxi_yellow')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('garage_buy_taxi_yellow')), findsNothing);
    expect(
      find.byKey(const ValueKey('garage_select_taxi_yellow')),
      findsNothing,
    );
  });

  testWidgets('locked cars show their price', (tester) async {
    await pumpGarage(tester);

    final executive = VehicleCatalog.byId('luxury_white')!;
    expect(
      find.byKey(const ValueKey('garage_buy_luxury_white')),
      findsOneWidget,
    );
    expect(find.text('${executive.price}'), findsOneWidget);
  });

  testWidgets('buying spends coins, unlocks, and equips the car',
      (tester) async {
    gameState.addCoins(1000);
    await pumpGarage(tester);

    final racer = VehicleCatalog.byId('sports_black')!;
    await tester.tap(find.byKey(const ValueKey('garage_buy_sports_black')));
    await tester.pumpAndSettle();

    expect(gameState.totalCoins, 1000 - racer.price);
    expect(gameState.unlockedVehicles, contains('sports_black'));
    // A purchase goes straight into service so it shows up in play.
    expect(gameState.selectedVehicle, 'sports_black');
    expect(
      find.byKey(const ValueKey('garage_in_use_sports_black')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('garage_in_use_taxi_yellow')),
      findsNothing,
    );
  });

  testWidgets('a car you cannot afford stays locked and says so',
      (tester) async {
    await pumpGarage(tester);

    await tester.tap(find.byKey(const ValueKey('garage_buy_luxury_white')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not enough coins'), findsOneWidget);
    expect(gameState.totalCoins, 0);
    expect(gameState.unlockedVehicles, isNot(contains('luxury_white')));
    expect(gameState.selectedVehicle, 'taxi_yellow');
  });

  testWidgets('selecting an owned car swaps the equipment', (tester) async {
    gameState.addCoins(500);
    expect(gameState.unlockVehicle('sedan_blue', 250), isTrue);
    await pumpGarage(tester);

    expect(gameState.selectedVehicle, 'taxi_yellow');
    await tester.tap(find.byKey(const ValueKey('garage_select_sedan_blue')));
    await tester.pumpAndSettle();

    expect(gameState.selectedVehicle, 'sedan_blue');
    expect(
      find.byKey(const ValueKey('garage_in_use_sedan_blue')),
      findsOneWidget,
    );
  });

  testWidgets('the header balance tracks spending', (tester) async {
    gameState.addCoins(400);
    await pumpGarage(tester);

    Finder balanceText(String amount) => find.descendant(
          of: find.byKey(const Key('garage_coin_balance')),
          matching: find.text(amount),
        );

    expect(balanceText('400'), findsOneWidget);

    final compact = VehicleCatalog.byId('compact_red')!;
    await tester.tap(find.byKey(const ValueKey('garage_buy_compact_red')));
    await tester.pumpAndSettle();

    expect(balanceText('${400 - compact.price}'), findsOneWidget);
    expect(balanceText('400'), findsNothing);
  });
}
