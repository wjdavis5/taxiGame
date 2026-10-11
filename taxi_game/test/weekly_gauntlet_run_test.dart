import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/weekly_gauntlet.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The gauntlet run wiring (issue #288): a game flagged as the week's
/// gauntlet drives the week-derived course under the week's modifier,
/// folds its finished numbers into the week's stored best, and hands its
/// retry to free play — never a silently counted second attempt.
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

  /// Mounts [game] headlessly so component `onLoad` hooks run (the
  /// endless-run test pattern; [Game.mount] is what GameWidget calls in
  /// production).
  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  Future<void> drain() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.value();
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> tickAndSettle(TaxiGame game) async {
    game.update(1 / 60);
    await drain();
    game.update(1 / 60);
    await drain();
  }

  /// Delivers [fare] by teleporting the taxi to its kerbs, the way the
  /// endless-run tests do. Assumes the fare's zones are mounted.
  void deliverFare(TaxiGame game, EndlessFare fare) {
    game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
    game.update(1 / 60);
    expect(game.player.hasPassenger, isTrue, reason: 'passenger boarded');
    game.player.position = Vector2(fare.dropoff.x, fare.dropoff.y + 30);
    game.update(1 / 60);
  }

  /// The week a test run belongs to — pinned so the assertions do not
  /// depend on the real calendar the suite happens to run on.
  const weekKey = '2026-W41';

  TaxiGame gauntletGame({GauntletModifier? modifier}) => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: WeeklyGauntlet.seedForWeek(weekKey),
        isGauntlet: true,
        gauntletWeekKey: weekKey,
        gauntletModifier:
            modifier ?? WeeklyGauntlet.planForWeek(weekKey).modifier,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());

  group('the gauntlet is the week\'s shared course', () {
    test('the game drives exactly the week-derived course', () async {
      final game = await mountGame(gauntletGame());
      await tickAndSettle(game);

      final shared = EndlessCourse(seed: WeeklyGauntlet.seedForWeek(weekKey));
      for (var i = 0; i < 5; i++) {
        final fare = game.course!.fare(i);
        final expected = shared.fare(i);
        expect(fare.pickup, expected.pickup, reason: 'fare $i pickup');
        expect(fare.dropoff, expected.dropoff, reason: 'fare $i dropoff');
        expect(fare.reward, expected.reward, reason: 'fare $i reward');
      }
      expect(game.isGauntlet, isTrue);
      expect(game.runSeed, WeeklyGauntlet.seedForWeek(weekKey));
    });
  });

  group('a finished gauntlet run folds into the week\'s best', () {
    test('the run\'s numbers land under the carried week key', () async {
      final game = await mountGame(gauntletGame());
      await tickAndSettle(game);

      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      game.bankShift();

      final record = gameState.weeklyGauntlet;
      expect(record.weekKey, weekKey,
          reason: 'the run records to the week the screen seeded it from');
      expect(record.bestScore, fare0.reward);
      expect(record.bestFares, 1);
      expect(record.bestChain, greaterThanOrEqualTo(1));
    });

    test('the pin wins over the clock: a carried week is what records',
        () async {
      // The screen derived the course from week W and carried it; the
      // clock already rolled into the next week. The run must record to
      // W, the week its course belongs to (the #248 rule).
      DailyShift.clock = () => DateTime(2026, 10, 12); // a later week
      addTearDown(() => DailyShift.clock = DateTime.now);

      final game = await mountGame(gauntletGame());
      await tickAndSettle(game);
      deliverFare(game, game.course!.fare(0));
      game.bankShift();

      expect(gameState.weeklyGauntlet.weekKey, weekKey);
    });
  });

  group('the week\'s modifier is a real rule', () {
    test('sudden death starts the run on one life', () async {
      final game = await mountGame(
          gauntletGame(modifier: GauntletModifier.suddenDeath));
      await tickAndSettle(game);

      expect(game.lives.remaining, 1,
          reason: 'one crash ends the gauntlet week\'s run');
    });

    test('every other week still starts on the standard three', () async {
      final game = await mountGame(
          gauntletGame(modifier: GauntletModifier.doubleFares));
      await tickAndSettle(game);

      expect(game.lives.remaining, 3);
    });

    test('double fares pays every fare twice', () async {
      final game = await mountGame(
          gauntletGame(modifier: GauntletModifier.doubleFares));
      await tickAndSettle(game);

      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);

      expect(gameState.totalCoins, fare0.reward * 2,
          reason: 'the wallet sees double; the chain score does not');
    });
  });

  group('the retry after a gauntlet run', () {
    test('is free play on a fresh seed, never a counted gauntlet replay',
        () async {
      final game = await mountGame(gauntletGame());
      await tickAndSettle(game);
      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      game.bankShift();
      expect(gameState.weeklyGauntlet.bestScore, fare0.reward);

      game.retryShift();
      await drain();
      await tickAndSettle(game);

      expect(game.isGauntlet, isFalse,
          reason: 'the summary\'s DRIVE AGAIN is a fresh city');
      expect(game.runSeed, isNot(WeeklyGauntlet.seedForWeek(weekKey)));

      // The free-play run grows the shift history but never the week's
      // stored best.
      deliverFare(game, game.course!.fare(0));
      game.bankShift();
      expect(gameState.runHistory, hasLength(2));
      expect(gameState.weeklyGauntlet.bestScore, fare0.reward,
          reason: 'free play never rewrites the week');
    });
  });

  group('the modifier never leaks into free play', () {
    test('a sudden-death game demoted by retry refills to three lives',
        () async {
      final game = await mountGame(
          gauntletGame(modifier: GauntletModifier.suddenDeath));
      await tickAndSettle(game);
      expect(game.lives.remaining, 1);

      game.retryShift();
      await drain();
      await tickAndSettle(game);

      expect(game.lives.remaining, 3,
          reason: 'the demoted run is an ordinary shift');
    });
  });
}
