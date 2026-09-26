import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/impact_fx.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// The daily run wiring (issue #19): a game flagged as today's Daily
/// Shift drives the date-derived shared course, settles the day's one
/// attempt when the shift ends, and hands its retry to free play — never
/// to a replay of the day's course.
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

  /// Headless games have no overlay builder map; register stand-ins for
  /// the overlays the end-of-shift flows add, as [GameScreen] does in
  /// production.
  TaxiGame dailyGame() => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: DailyShift.seedForDateKey(DailyShift.todayKey),
        isDailyShift: true,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());

  TaxiGame freePlayGame(int seed) => TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: seed,
      )
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());

  /// Lets pending component mounts finish before the next simulated tick.
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

  /// Plays out the aftermath of a survivable crash: the crash hit-stop
  /// burns off first, then the stall elapses and the shift resumes.
  void playOutStall(TaxiGame game) {
    game.update(ImpactFx.crashHitStopDuration + 0.01);
    game.update(TaxiGame.crashStallSeconds + 0.01);
  }

  group('the daily shift is the shared course', () {
    test('the game drives exactly the date-derived course', () async {
      final game = await mountGame(dailyGame());
      await tickAndSettle(game);

      final shared = EndlessCourse(
          seed: DailyShift.seedForDateKey(DailyShift.todayKey));
      for (var i = 0; i < 5; i++) {
        final fare = game.course!.fare(i);
        final expected = shared.fare(i);
        expect(fare.pickup, expected.pickup, reason: 'fare $i pickup');
        expect(fare.dropoff, expected.dropoff, reason: 'fare $i dropoff');
        expect(fare.reward, expected.reward, reason: 'fare $i reward');
      }
      expect(game.isEndless, isTrue,
          reason: 'the daily rides the endless ramp, shared seed only');
      expect(game.runSeed, DailyShift.seedForDateKey(DailyShift.todayKey));
    });
  });

  group('a finished daily settles the day', () {
    test('the day\'s result lands in the history with the shift\'s score',
        () async {
      final game = await mountGame(dailyGame());
      await tickAndSettle(game);

      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      game.bankShift();

      expect(gameState.todayDailyComplete, isTrue);
      final result = gameState.todayDailyResult!;
      expect(result.dateKey, DailyShift.todayKey);
      expect(result.score, fare0.reward,
          reason: 'the banked payout is the shared, screenshotable number');
      expect(result.banked, isTrue);

      // The daily is a real shift: it feeds the personal best and the
      // shift history like any other.
      expect(gameState.endlessBestScore, fare0.reward);
      expect(gameState.runHistory, hasLength(1));
      expect(gameState.dailyHistory, hasLength(1));
    });

    test('a wrecked daily counts as the attempt too', () async {
      final game = await mountGame(dailyGame());
      await tickAndSettle(game);
      deliverFare(game, game.course!.fare(0));

      game.onCrash();
      playOutStall(game);
      game.onCrash();
      playOutStall(game);
      game.onCrash(); // the third: shift over, day done

      expect(gameState.todayDailyComplete, isTrue);
      final result = gameState.todayDailyResult!;
      expect(result.banked, isFalse);
      expect(result.score, greaterThan(0),
          reason: 'the forfeited score is still the day\'s score');
    });
  });

  group('the retry after a daily', () {
    test('is free play on a fresh seed, never a daily replay', () async {
      final game = await mountGame(dailyGame());
      await tickAndSettle(game);
      final fare0 = game.course!.fare(0);
      deliverFare(game, fare0);
      game.bankShift();
      expect(gameState.dailyHistory, hasLength(1));

      // The summary panel's retry: whatever it starts, it must not be
      // the day's course again.
      game.retryShift();
      await drain();
      await tickAndSettle(game);

      expect(game.isDailyShift, isFalse,
          reason: 'the day is done; the drive that follows is free play');
      expect(game.isGameActive, isTrue);
      expect(game.runSeed, isNot(DailyShift.seedForDateKey(DailyShift.todayKey)),
          reason: 'a fresh seed, not the shared one');

      // Wreck the free-play shift: it grows the shift history and leaves
      // the day's settled result untouched.
      game.onCrash();
      playOutStall(game);
      game.onCrash();
      playOutStall(game);
      game.onCrash();
      expect(gameState.runHistory, hasLength(2));
      expect(gameState.dailyHistory, hasLength(1),
          reason: 'free play never spends or rewrites the daily');
      expect(gameState.todayDailyResult!.score, fare0.reward,
          reason: 'the settled daily keeps its original score');
    });
  });

  group('a free-play shift', () {
    test('never touches the daily history', () async {
      final game = await mountGame(freePlayGame(42));
      await tickAndSettle(game);

      expect(game.isDailyShift, isFalse);
      deliverFare(game, game.course!.fare(0));
      game.bankShift();

      expect(gameState.runHistory, hasLength(1));
      expect(gameState.dailyHistory, isEmpty);
      expect(gameState.todayDailyComplete, isFalse,
          reason: 'only the daily spends the day');
    });
  });
}
