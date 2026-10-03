import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/ghost_replay.dart';
import 'package:taxi_game/game/systems/impact_fx.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'helpers/calendar_days.dart';

/// The ghost replay wiring (issue #20): a finished run on the daily
/// course offers its path as the day's ghost; a ghost race — a later run
/// of the same day's course — shows the stored best run as a translucent
/// car, freezes it with the shift's clock, and replaces it only by
/// scoring strictly more. Free play never records and never shows one.
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
  /// Advances game time by [seconds], in clamped frames (issue #36): no
  /// single frame may consume more than [TaxiGame.maxUpdateDelta], so
  /// fast-forwarding a shift means many small frames, never one giant
  /// one — exactly the invariant the live game now runs under.
  void advanceGameTime(TaxiGame game, double seconds) {
    var remaining = seconds;
    while (remaining > 0) {
      final step = math.min(remaining, TaxiGame.maxUpdateDelta);
      game.update(step);
      remaining -= step;
    }
  }

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
  TaxiGame withOverlays(TaxiGame game) => game
    ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
    ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
    ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
    ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());

  TaxiGame dailyGame() => withOverlays(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: DailyShift.seedForDateKey(DailyShift.todayKey),
        isDailyShift: true,
      ));

  TaxiGame ghostRaceGame() => withOverlays(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: DailyShift.seedForDateKey(DailyShift.todayKey),
        isGhostRace: true,
      ));

  TaxiGame freePlayGame(int seed) => withOverlays(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
        endlessSeed: seed,
      ));

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

  /// Ends a shift the way the player does: the dropoff opens the
  /// bank-or-push choice, banking takes it.
  void bankAfterFare(TaxiGame game, EndlessFare fare) {
    deliverFare(game, fare);
    game.bankShift();
  }

  /// Plays out the aftermath of a survivable crash: the crash hit-stop
  /// burns off first, then the stall elapses and the shift resumes.
  void playOutStall(TaxiGame game) {
    advanceGameTime(game, ImpactFx.crashHitStopDuration + 0.01);
    advanceGameTime(game, TaxiGame.crashStallSeconds + 0.01);
  }

  /// Plants a synthetic ghost for [dateKey] driving straight down the
  /// road centre: 100 px of road per grid sample. Requires no stored
  /// ghost for the day — call [GameStateService.resetProgress] first if
  /// one may exist.
  Future<void> plantGhost({
    String? dateKey,
    int score = 100,
    int samples = 5,
  }) async {
    assert(dateKey != null || gameState.todayGhost == null,
        'planting over an existing ghost would test the best-run rule by '
        'accident; reset first');
    final flat = <int>[];
    for (var i = 0; i < samples; i++) {
      flat..add(200)..add(-100 * i);
    }
    final stored = await gameState.recordDailyGhostRun(
      dateKey: dateKey ?? DailyShift.todayKey,
      score: score,
      banked: true,
      vehicleId: 'taxi_yellow',
      samples: flat,
    );
    expect(stored, isTrue, reason: 'ghost setup must store');
  }

  group('recording a finished daily', () {
    test("the day's first daily runs with no ghost on the road", () async {
      final game = await mountGame(dailyGame());
      await tickAndSettle(game);

      expect(game.ghostCar, isNull,
          reason: 'no trace exists for a course never driven');
      expect(game.ghostGapMetres, isNull);
    });

    test('a finished daily offers its path, and it becomes the ghost',
        () async {
      final game = await mountGame(dailyGame());
      await tickAndSettle(game);
      final fare0 = game.course!.fare(0);
      bankAfterFare(game, fare0);

      final ghost = gameState.todayGhost;
      expect(ghost, isNotNull,
          reason: 'the first finished run of the day is the ghost');
      expect(ghost!.dateKey, DailyShift.todayKey);
      expect(ghost.score, fare0.reward,
          reason: 'the ghost carries the score a replay must beat');
      expect(ghost.sampleCount, greaterThan(0));
      expect(ghost.samples[0], TaxiGame.roadCenterX.toInt(),
          reason: 'the first sample is the start position');
      expect(ghost.vehicleId, game.player.vehicleId,
          reason: 'the ghost renders the car that set it');
    });

    test('free play never offers a trace', () async {
      final game = await mountGame(freePlayGame(42));
      await tickAndSettle(game);
      bankAfterFare(game, game.course!.fare(0));

      expect(gameState.todayGhost, isNull,
          reason: 'a ghost of a random course is meaningless (issue #20)');
    });
  });

  group('the ghost on the road', () {
    test('a ghost race shows the stored best run as a translucent car',
        () async {
      await plantGhost();
      final game = await mountGame(ghostRaceGame());
      await tickAndSettle(game);

      expect(game.ghostCar, isNotNull);
      expect(game.isEndless, isTrue);
      expect(game.isDailyShift, isFalse,
          reason: 'the race is a replay, never a second scoring attempt');

      // The replay follows the recorded path on the driven-time clock:
      // two ticks in, it sits 1/6 of the way into the first leg.
      final expected = GhostPlayback(gameState.todayGhost!).positionAt(
        2 / 60,
      );
      expect(game.ghostCar!.position.x, closeTo(expected.x, 0.001));
      expect(game.ghostCar!.position.y, closeTo(expected.y, 0.001));
      expect(expected.y, lessThan(0), reason: 'sanity: down the road');
    });

    test('the daily itself also races a ghost stored the same day',
        () async {
      await plantGhost();
      final game = await mountGame(dailyGame());
      await tickAndSettle(game);
      expect(game.ghostCar, isNotNull,
          reason: 'a retry of the settled course still races the ghost');
    });

    test('a ghost from another day never takes the road', () async {
      // Calendar yesterday (issue #196): on the 25-hour fall-back day,
      // now − 24h is still today for the hour after midnight — and a
      // "yesterday" ghost planted for today is exactly the same-day ghost
      // this test must not match.
      final yesterday = DailyShift.dateKeyFor(calendarDaysFromNow(-1));
      await plantGhost(dateKey: yesterday);

      final daily = await mountGame(dailyGame());
      await tickAndSettle(daily);
      expect(daily.ghostCar, isNull,
          reason: 'a ghost of a different course is not a ghost');
      expect(daily.ghostGapMetres, isNull);

      final race = await mountGame(ghostRaceGame());
      await tickAndSettle(race);
      expect(race.ghostCar, isNull);
    });

    test('the ghost freezes when the shift is not live', () async {
      await plantGhost();
      final game = await mountGame(ghostRaceGame());
      await tickAndSettle(game);
      bankAfterFare(game, game.course!.fare(0));
      expect(game.isGameActive, isFalse, reason: 'the shift is settled');

      final frozen = game.ghostCar!.position.clone();
      for (var i = 0; i < 20; i++) {
        game.update(1 / 60);
      }
      expect(game.ghostCar!.position, frozen,
          reason: 'the recorded clock stopped with the shift');
    });

    test('the ghost parks where its recording ended', () async {
      await plantGhost(samples: 3);
      final game = await mountGame(ghostRaceGame());
      await tickAndSettle(game);

      final trace = gameState.todayGhost!;
      advanceGameTime(game, trace.coveredSeconds + 30);
      expect(game.ghostCar!.position.x, 200);
      expect(game.ghostCar!.position.y, -200,
          reason: 'past the trace, the ghost holds its last position');
    });

    test('the ghost gap reads metres ahead and behind', () async {
      await plantGhost(samples: 11);
      final game = await mountGame(ghostRaceGame());
      await tickAndSettle(game);

      // The ghost is already down the road; the player at the start
      // line is behind it — a negative gap.
      expect(game.ghostGapMetres!, lessThan(0));

      // Drive the player well past the ghost's last recorded position.
      game.player.position = Vector2(200, -1200);
      game.update(1 / 60);
      expect(game.ghostGapMetres!, greaterThan(0),
          reason: 'a positive gap is the player ahead');
    });
  });

  group('the ghost race loop', () {
    test('a race that scores more replaces the ghost', () async {
      await plantGhost(score: 1);
      final game = await mountGame(ghostRaceGame());
      await tickAndSettle(game);
      deliverFare(game, game.course!.fare(0));
      // Camera catches up so the next fare generates and mounts.
      await tickAndSettle(game);
      deliverFare(game, game.course!.fare(1));
      game.bankShift();
      expect(game.fareChain.score, greaterThan(1),
          reason: 'two fares beat the planted score of 1');

      expect(gameState.todayGhost!.score, game.fareChain.score,
          reason: 'the race trace is now the ghost');
    });

    test('a race that cannot beat the ghost leaves it standing',
        () async {
      await plantGhost(score: 100000);
      final game = await mountGame(ghostRaceGame());
      await tickAndSettle(game);
      bankAfterFare(game, game.course!.fare(0));

      expect(gameState.todayGhost!.score, 100000,
          reason: 'only a strictly better run replaces the ghost');
    });

    test('a ghost race never rewrites the settled daily', () async {
      final first = await mountGame(dailyGame());
      await tickAndSettle(first);
      bankAfterFare(first, first.course!.fare(0));
      final settled = gameState.todayDailyResult!;
      expect(gameState.dailyHistory, hasLength(1));

      final race = await mountGame(ghostRaceGame());
      await tickAndSettle(race);
      deliverFare(race, race.course!.fare(0));
      // Camera catches up so the next fare generates and mounts.
      await tickAndSettle(race);
      deliverFare(race, race.course!.fare(1));
      race.bankShift();

      final after = gameState.todayDailyResult!;
      expect(after.dateKey, settled.dateKey);
      expect(after.score, settled.score,
          reason: "the day's result is the first attempt's, untouched");
      expect(gameState.dailyHistory, hasLength(1));
    });

    test('a ghost race with a survivable crash resumes both clocks',
        () async {
      await plantGhost();
      final game = await mountGame(ghostRaceGame());
      await tickAndSettle(game);

      game.onCrash();
      final frozen = game.ghostCar!.position.clone();
      game.update(1 / 60); // mid-crash-stall: the world holds still
      expect(game.ghostCar!.position, frozen,
          reason: 'the ghost freezes through the stall like the run did');

      playOutStall(game);
      expect(game.isGameActive, isTrue);
      final before = game.ghostCar!.position.clone();
      advanceGameTime(game, 0.1);
      expect(game.ghostCar!.position, isNot(before),
          reason: 'the replay resumes with the shift');
    });

    test('the retry after a ghost race is free play', () async {
      await plantGhost();
      final game = await mountGame(ghostRaceGame());
      await tickAndSettle(game);
      bankAfterFare(game, game.course!.fare(0));

      game.retryShift();
      await drain();
      await tickAndSettle(game);

      expect(game.isGhostRace, isFalse);
      expect(game.isDailyShift, isFalse);
      expect(game.ghostCar, isNull, reason: 'free play has no ghost');
      expect(game.runSeed,
          isNot(DailyShift.seedForDateKey(DailyShift.todayKey)));
    });

    test('a run abandoned unfinished offers nothing', () async {
      await plantGhost(score: 7);
      final game = await mountGame(ghostRaceGame());
      await tickAndSettle(game);
      deliverFare(game, game.course!.fare(0));
      // No bank, no third crash: back to the menu leaves the shift
      // running, and only an ended run offers its trace.

      expect(gameState.todayGhost!.score, 7,
          reason: 'the planted ghost stands; the live run offered nothing');
      expect(gameState.todayGhost!.sampleCount, 5);
    });

    test('a race refused after midnight writes no D+1 ghost (issue #96)',
        () async {
      // Day D: the scoring daily is driven and settled — its trace is
      // D's ghost, and the summary's RACE YOUR GHOST was built for D.
      final game = await mountGame(dailyGame());
      await tickAndSettle(game);
      bankAfterFare(game, game.course!.fare(0));
      final dayD = DailyShift.todayKey;
      final dayDGhost = gameState.todayGhost;
      expect(dayDGhost, isNotNull, reason: 'precondition: D has a ghost');
      // Calendar tomorrow (issue #196): a 24-hour step from now can still
      // be day D across a DST change day, and then this D+1 — and the
      // pinned clock below — were never another day at all.
      final dayE = DailyShift.dateKeyFor(calendarDaysFromNow(1));

      // Midnight passes with the summary up (issue #96): the tap the
      // bug would have honoured starts a D+1 ghost race whose trace —
      // the first for that "new" day — overwrites D's ghost outright.
      DailyShift.clock = () => calendarDaysFromNow(1);
      addTearDown(() => DailyShift.clock = DateTime.now);
      game.raceGhost();

      expect(game.isGhostRace, isFalse,
          reason: 'the refused tap starts no race');
      expect(game.isGameActive, isFalse,
          reason: 'the settled shift still owns the game');
      expect(game.ghostCar, isNull,
          reason: 'no replay car materialised for a day nothing was raced');
      expect(gameState.ghostFor(dayE), isNull,
          reason: 'no practice trace was written as D+1\'s ghost');
      expect(gameState.ghostFor(dayD)!.score, dayDGhost!.score,
          reason: "D's ghost survives untouched");
    });
  });
}
