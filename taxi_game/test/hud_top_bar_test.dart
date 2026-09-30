import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/levels/level.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/widgets/hud_overlay.dart';

/// The HUD's top bar (issue #57): level title · coins · pause. None of the
/// three could shrink, so on Level 8 · Keep the Chain with a 4-digit coin
/// total the row overflowed by 43 px on a 420 pt phone and pushed the
/// pause button off the right edge — the player could no longer pause.
/// These tests pin the #43 treatment for this row too: the title yields,
/// coins and pause stay rigid and fully on screen, for every authored
/// level name at the widest coin pill, on the narrowest iPhone width.
///
/// The bar's badges poll the game on repeating 100-300 ms timers, so these
/// tests pump fixed durations — never pumpAndSettle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;

  /// The real authored names, loaded once from the shipped assets — the
  /// test must exercise the actual strings, not a guess at their lengths
  /// (the whole bug is that 'Level 8 · Keep the Chain' is longer than
  /// anyone guessed).
  final levelLoader = LevelLoaderService();
  final levelNames = <int, String>{};

  setUpAll(() async {
    for (var n = 1; n <= GameLevel.ladderLength; n++) {
      levelNames[n] = (await levelLoader.loadLevel(n)).name;
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
    // A 5-digit total — the widest the coin pill gets, so every rung is
    // judged at the row's worst case, not just the issue's 4 digits.
    gameState.addCoins(99999);
  });

  Widget hudFor(TaxiGame game) =>
      ChangeNotifierProvider<GameStateService>.value(
        value: gameState,
        child: MaterialApp(home: Scaffold(body: HudOverlay(game: game))),
      );

  testWidgets('every level name keeps the pause button on screen '
      '(issue #57)', (tester) async {
    // The narrowest iPhone width — the iPhone Air's 420 pt already
    // overflowed by 43 px, so 375 pt is where the fix earns its keep.
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (var n = 1; n <= GameLevel.ladderLength; n++) {
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      );
      game.currentLevelNumber = n;
      game.currentLevelName = levelNames[n];

      await tester.pumpWidget(hudFor(game));
      await tester.pump(const Duration(milliseconds: 350)); // poll tick

      // The overflow stripe is a layout exception in tests: none means
      // the row fits.
      expect(tester.takeException(), isNull,
          reason: 'level $n "${levelNames[n]}" overflowed the top bar');

      // The pause control is fully inside the padded content area — the
      // one thing this row must never shove off screen. The HUD's content
      // ends 16 px short of the 375 pt surface.
      final pauseRect = tester.getRect(find.byIcon(Icons.pause));
      expect(pauseRect.right, lessThanOrEqualTo(375.0 - 16.0),
          reason: 'level $n "${levelNames[n]}" pushed the pause button '
              'off the right edge');
      expect(pauseRect.left, greaterThan(0),
          reason: 'level $n "${levelNames[n]}" pushed the pause button '
              'off the left edge');

      // The title still renders — scaled down to fit, not clipped away —
      // and the coins with it.
      expect(
        find.text('LEVEL $n \u00b7 ${levelNames[n]!.toUpperCase()}'),
        findsOneWidget,
        reason: 'level $n title missing from the bar',
      );
      expect(find.text('99999'), findsOneWidget);
    }
  });

  testWidgets('a fitting title keeps its natural size — the yield only '
      'happens under pressure', (tester) async {
    // The test font renders every glyph as a full em square, so even
    // 'LEVEL 1 · FIRST RIDE' does not fit 375 pt beside the 5-digit coin
    // pill (the production font is far narrower — that is why the issue
    // only bit on the longest names and widest phones). Natural size is
    // therefore proven on a wide surface, and the yield on the narrow
    // one, by comparing the title's rendered height against itself: the
    // 18 px style's line height when unscaled, strictly less once the
    // scale-down box has to shrink it.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final game = TaxiGame(
      levelLoader: LevelLoaderService(),
      gameState: gameState,
    );
    game.currentLevelNumber = 1;
    game.currentLevelName = levelNames[1];

    // Wide: everything fits, so the title renders at natural size.
    tester.view.physicalSize = const Size(900, 812);
    await tester.pumpWidget(hudFor(game));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);

    final naturalTitle = tester.getRect(find.text('LEVEL 1 \u00b7 FIRST RIDE'));
    final coins = tester.getRect(find.text('99999'));
    // Same 18 px bold style, both unscaled: same rendered text height.
    expect(naturalTitle.height, closeTo(coins.height, 0.5),
        reason: 'a fitting title must not be scaled down');
    expect(tester.getRect(find.byIcon(Icons.pause)).right,
        lessThanOrEqualTo(900.0 - 16.0));

    // Narrow: the same widgets must now yield, and the shrink must be
    // the title's, never the pause button's.
    tester.view.physicalSize = const Size(375, 812);
    await tester.pumpWidget(hudFor(game));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);

    final squeezedTitle =
        tester.getRect(find.text('LEVEL 1 \u00b7 FIRST RIDE'));
    expect(
      squeezedTitle.height,
      lessThan(naturalTitle.height - 1),
      reason: 'under pressure the scale-down box must actually shrink '
          'the title',
    );
    expect(tester.getRect(find.text('99999')).height,
        closeTo(coins.height, 0.5),
        reason: 'the coin pill stays rigid at natural size');
    final pauseRect = tester.getRect(find.byIcon(Icons.pause));
    expect(pauseRect.right, lessThanOrEqualTo(375.0 - 16.0));
    expect(pauseRect.height, closeTo(32.0, 0.5),
        reason: 'the pause icon stays rigid at natural size');
  });
}
