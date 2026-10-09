import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('two BUY invocations inside one frame charge once (issue #221)',
      (tester) async {
    // The double-tap window: both taps reach the button before the
    // post-purchase rebuild swaps BUY for SELECT. The second invocation
    // must not spend again — one car, one charge.
    final compact = VehicleCatalog.byId('compact_red')!;
    gameState.addCoins(compact.price * 2 + 137);
    await pumpGarage(tester);

    final buy = tester.widget<ElevatedButton>(
      find.byKey(const ValueKey('garage_buy_compact_red')),
    );
    buy.onPressed!();
    buy.onPressed!();
    await tester.pumpAndSettle();

    expect(gameState.totalCoins, compact.price + 137,
        reason: 'a duplicate BUY invocation must not charge a second time');
    expect(gameState.unlockedVehicles, contains('compact_red'));
    expect(gameState.selectedVehicle, 'compact_red');
  });

  testWidgets('a car you cannot afford stays locked and says so',
      (tester) async {
    await pumpGarage(tester);

    final executive = VehicleCatalog.byId('luxury_white')!;
    await tester.tap(find.byKey(const ValueKey('garage_buy_luxury_white')));
    await tester.pumpAndSettle();

    // The exact wording, not just a prefix: the template must not add an
    // article of its own. The Executive's name already starts with "The",
    // and "for the The Executive" was the stutter of issue #173 — a
    // textContaining('Not enough coins') check would let it back in.
    expect(
      find.text(
        'Not enough coins — you need ${executive.price} more '
        'for ${executive.name}.',
      ),
      findsOneWidget,
    );
    expect(gameState.totalCoins, 0);
    expect(gameState.unlockedVehicles, isNot(contains('luxury_white')));
    expect(gameState.selectedVehicle, 'taxi_yellow');
  });

  testWidgets('hammering an unaffordable car replays one refusal, not one '
      'per tap (issue #171)', (tester) async {
    await pumpGarage(tester);

    // Four taps 100 ms apart straddle the snackbar's 250 ms entrance and
    // exit windows — the cadence a player actually produces on a button
    // that keeps refusing. showSnackBar queues one two-second bar per
    // call, so before the fix this stacked four of them.
    final buy = find.byKey(const ValueKey('garage_buy_luxury_white'));
    for (var i = 0; i < 4; i++) {
      await tester.tap(buy);
      await tester.pump(const Duration(milliseconds: 100));
    }

    // However many taps landed, exactly one refusal may be showing — the
    // taps must have replaced each other, not queued.
    expect(find.textContaining('Not enough coins'), findsOneWidget);

    // One bar is over within ~3 s of the last tap (entrance, its 2 s
    // duration, exit). The pumps must be animation-sized: one multi-second
    // pump renders a single frame and leaves a mid-exit bar stranded in
    // the tree. Five seconds past the taps the messenger must be silent —
    // with one bar queued per tap, the four bars replay back to back for
    // ~10 s and bars 3–4 would still be showing here. Asserting before
    // pumpAndSettle matters: pumpAndSettle would drain a leftover queue
    // and hide the bug.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.textContaining('Not enough coins'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.textContaining('Not enough coins'), findsNothing);
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

  testWidgets('on a 320 pt screen every stat bar keeps a real track',
      (tester) async {
    // The 4-inch iPhone SE / Display Zoom width (issue #149): the
    // side-by-side card row starved the middle column below the 58 px a
    // stat row needs before its track, so every track collapsed to zero
    // width and every row overflowed. Ahem, the test font, advances a
    // square per glyph — roughly twice Roboto — which alone overflows the
    // header ("GARAGE" at 32 px); 0.85 text scale stands in for real-font
    // metrics at the default scale while keeping every card action wider
    // than Roboto renders it, so the no-overflow check below stays
    // conservative where the bug lived.
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 0.85;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(wrap(const GarageScreen()));
    await tester.pump();

    for (final vehicle in VehicleCatalog.vehicles) {
      for (final axis in const ['speed', 'accel', 'steering', 'size']) {
        final bar = find.byKey(Key('garage_stat_${axis}_${vehicle.id}'));
        await tester.scrollUntilVisible(
          bar,
          120,
          scrollable: find.byType(Scrollable).first,
        );
        // The fill is a fraction of its track, so the pair of numbers
        // recovers the track the fill sits in. Stacked, a card spans the
        // ~190 px track the issue's bars need; collapsed, it was exactly
        // 0.0. The fleet's shortest fill (0.06 of the track) is only
        // ~11 px by design, so it is the track — not the fill — that
        // must clear the threshold.
        final fillWidth = tester.getSize(bar).width;
        final factor =
            tester.widget<FractionallySizedBox>(bar).widthFactor!;
        final trackWidth = fillWidth / factor;
        expect(
          trackWidth,
          greaterThan(40),
          reason: 'the ${vehicle.name} $axis bar needs a visible track on a '
              '320 pt screen, got $trackWidth px',
        );
        expect(
          fillWidth,
          greaterThan(0),
          reason: 'the ${vehicle.name} $axis fill must paint something',
        );
      }
    }

    // The stacked layout leaves every row — header, cards, actions —
    // inside the screen: nothing may overflow at this width.
    expect(tester.takeException(), isNull);
  });

  // The standard iPhones the issue names (issue #156): 375 pt (SE 3rd
  // gen / mini under Display Zoom), 390 (iPhone 14/15), 393 (14/15 Pro).
  // Every card keeps the row layout at these widths, whose middle
  // column could not fund the longest Roboto-Bold names — "Family
  // Minivan" showed as "Family Min..." at all three, "The Executive"
  // at 375. Ahem, the test font, advances a square per glyph — roughly
  // twice Roboto — so it truncated all seven names at every one of
  // these widths before the fix: the check below is strictly
  // conservative, failing on any regression the real font could show.
  for (final width in [375.0, 390.0, 393.0]) {
    testWidgets('on a ${width.round()} pt iPhone every car name shows in '
        'full (issue #156)', (tester) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(const GarageScreen()));
      await tester.pump();

      for (final vehicle in VehicleCatalog.vehicles) {
        await tester.scrollUntilVisible(
          find.text(vehicle.name),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        // The name renders at natural one-line width inside a
        // scale-down box, so its paragraph must never have needed the
        // ellipsis — didExceedMaxLines is exactly what the "Family
        // Min..." truncation set before the fix.
        final paragraph =
            tester.renderObject<RenderParagraph>(find.text(vehicle.name));
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '${vehicle.name} must not be cut short on a '
              '${width.round()} pt screen',
        );
      }

      expect(tester.takeException(), isNull);
    });
  }
}
