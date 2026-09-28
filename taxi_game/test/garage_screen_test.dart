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

  /// The fleet-relative fill of one stat bar on one card (issue #9): bars
  /// are FractionallySizedBoxes keyed by axis and vehicle.
  double statFill(WidgetTester tester, String axis, String id) => tester
          .widget<FractionallySizedBox>(
            find.byKey(Key('garage_stat_${axis}_$id')),
          )
          .widthFactor!;

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
    final racer = VehicleCatalog.byId('sports_black')!;
    gameState.addCoins(racer.price + 137);
    await pumpGarage(tester);

    await tester.tap(find.byKey(const ValueKey('garage_buy_sports_black')));
    await tester.pumpAndSettle();

    expect(gameState.totalCoins, 137);
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

  testWidgets('a purchase that grows the fleet announces the achievement',
      (tester) async {
    // The starter cab is owned from the first launch, so the first
    // purchase is the second car — the TWO-CAB OPERATION tier (issue
    // #21).
    gameState.addCoins(VehicleCatalog.byId('compact_red')!.price);
    await pumpGarage(tester);

    expect(find.textContaining('Achievement unlocked'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('garage_buy_compact_red')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('garage_achievement_snackbar_cars_2')),
        findsOneWidget);
    expect(
      find.textContaining('Achievement unlocked — TWO-CAB OPERATION'),
      findsOneWidget,
    );
  });

  testWidgets('selecting an owned car swaps the equipment', (tester) async {
    final sedan = VehicleCatalog.byId('sedan_blue')!;
    gameState.addCoins(sedan.price);
    expect(gameState.unlockVehicle('sedan_blue', sedan.price), isTrue);
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
    final compact = VehicleCatalog.byId('compact_red')!;
    // Enough to buy the compact and keep a visible 400-coin remainder.
    gameState.addCoins(compact.price + 400);
    await pumpGarage(tester);

    Finder balanceText(String amount) => find.descendant(
          of: find.byKey(const Key('garage_coin_balance')),
          matching: find.text(amount),
        );

    expect(balanceText('${compact.price + 400}'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('garage_buy_compact_red')));
    await tester.pumpAndSettle();

    expect(balanceText('400'), findsOneWidget);
    expect(balanceText('${compact.price + 400}'), findsNothing);
  });

  testWidgets('every card surfaces the four handling stats', (tester) async {
    await pumpGarage(tester);

    for (final vehicle in VehicleCatalog.vehicles) {
      for (final axis in const ['speed', 'accel', 'steering', 'size']) {
        expect(
          find.byKey(Key('garage_stat_${axis}_${vehicle.id}')),
          findsOneWidget,
          reason: 'the ${vehicle.name} card must show its $axis stat so the '
              'purchase is an informed choice',
        );
      }
    }
  });

  testWidgets('stat bars read on one shared fleet scale', (tester) async {
    await pumpGarage(tester);

    // Faster: the racer is the fastest thing in the garage.
    expect(
      statFill(tester, 'speed', 'sports_black'),
      greaterThan(statFill(tester, 'speed', 'taxi_yellow')),
    );
    // Sharper: the compact steers in harder than the starter...
    expect(
      statFill(tester, 'steering', 'compact_red'),
      greaterThan(statFill(tester, 'steering', 'taxi_yellow')),
    );
    // ...and pays for it in speed on the very same scale, so a card shows
    // the trade without a second trip to the road.
    expect(
      statFill(tester, 'speed', 'compact_red'),
      lessThan(statFill(tester, 'speed', 'taxi_yellow')),
    );
    // Size bars show body, not virtue: the minivan dwarfs the compact.
    expect(
      statFill(tester, 'size', 'minivan_gray'),
      greaterThan(statFill(tester, 'size', 'compact_red')),
    );
  });
}
