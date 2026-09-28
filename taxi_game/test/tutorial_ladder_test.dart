import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/dropoff_zone.dart';
import 'package:taxi_game/game/levels/level.dart';
import 'package:taxi_game/game/systems/fare_chain.dart';
import 'package:taxi_game/game/systems/lives.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';

/// The tutorial ladder (issue #16): the ten hand-made levels are the
/// onboarding that teaches Endless — hold-and-steer, pickup and dropoff,
/// the fare timer, the chain multiplier, and banking — the last two rungs
/// offer the real bank-or-push choice, and finishing level 10 hands off
/// to an endless shift instead of replaying the final level forever.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameStateService gameState;
  late LevelLoaderService levelLoader;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.init();
    gameState = GameStateService(storage);
    await gameState.loadSaveData();
    levelLoader = LevelLoaderService();
  });

  /// A game state whose save sits at [level], as if the player had fought
  /// their way there: written through the storage key [StorageService]
  /// reads, so [GameStateService.loadSaveData] picks it up.
  Future<GameStateService> gameStateAtLevel(int level) async {
    final data = SaveData.createDefault()..currentLevel = level;
    SharedPreferences.setMockInitialValues({
      StorageService.saveDataKey: jsonEncode(data.toJson()),
    });
    final storage = StorageService();
    await storage.init();
    final service = GameStateService(storage);
    await service.loadSaveData();
    return service;
  }

  /// Mounts [game] headlessly so component `onLoad` hooks run (the
  /// endless-run test pattern; [Game.mount] is what GameWidget calls in
  /// production). Headless games have no overlay builder map, so the
  /// flows under test register stand-in entries, as the tests for issues
  /// #13-#15 do.
  Future<TaxiGame> mountGame(TaxiGame game) async {
    game.onGameResize(Vector2(400, 800));
    await game.onLoad();
    // ignore: invalid_use_of_internal_member
    game.mount();
    await game.ready();
    return game;
  }

  TaxiGame ladderGame([GameStateService? state]) => TaxiGame(
        levelLoader: levelLoader,
        gameState: state ?? gameState,
      )
        ..overlays.addEntry('levelComplete', (_, __) => const SizedBox.shrink())
        ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
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

  /// Teleports the taxi through [pickup] then [dropoff], the way the
  /// level-mode fare-chain tests do. Each hop gets a tick so the zone
  /// collisions fire.
  Future<void> rideTo(TaxiGame game, Vector2 pickup, Vector2 dropoff) async {
    game.player.position = Vector2(pickup.x, pickup.y + 30);
    game.update(1 / 60);
    await drain();
    game.player.position = Vector2(dropoff.x, dropoff.y + 30);
    game.update(1 / 60);
    await drain();
  }

  group('the ladder teaches in order', () {
    test('ten rungs ship, and the ladder constant agrees with the assets',
        () async {
      expect(await levelLoader.getTotalLevels(), GameLevel.ladderLength);

      for (var i = 1; i <= GameLevel.ladderLength; i++) {
        final level = await levelLoader.loadLevel(i);
        // The loader falls back to a throwaway test level when an asset
        // is missing; a levelNumber mismatch catches that silently.
        expect(level.levelNumber, i, reason: 'rung $i failed to load');
        expect(level.name, isNot(equals('Test Level')));
      }
    });

    test('each rung has a unique name', () async {
      final names = <String>{};
      for (var i = 1; i <= GameLevel.ladderLength; i++) {
        final level = await levelLoader.loadLevel(i);
        expect(names.add(level.name), isTrue,
            reason: 'level $i repeats the name "${level.name}"');
      }
    });

    test('traffic ramps rung by rung', () async {
      double? previousProbability;
      double? previousSpeed;
      double? previousInterval;

      for (var i = 1; i <= GameLevel.ladderLength; i++) {
        final pattern = (await levelLoader.loadLevel(i)).trafficPattern;

        final maxProbability = pattern.lanes
            .map((lane) => lane.spawnProbability)
            .reduce((a, b) => a > b ? a : b);
        final maxSpeed = pattern.lanes
            .map((lane) => lane.speedRange.max)
            .reduce((a, b) => a > b ? a : b);

        if (previousProbability != null) {
          expect(maxProbability, greaterThan(previousProbability),
              reason: 'level $i loosens the spawn probability');
          expect(maxSpeed, greaterThanOrEqualTo(previousSpeed!),
              reason: 'level $i slows traffic down');
          expect(pattern.spawnInterval, lessThan(previousInterval!),
              reason: 'level $i spawns less often');
        }

        previousProbability = maxProbability;
        previousSpeed = maxSpeed;
        previousInterval = pattern.spawnInterval;
      }
    });

    test('the last rung is a graduation, not the old nightmare wall',
        () async {
      final pattern =
          (await levelLoader.loadLevel(GameLevel.ladderLength))
              .trafficPattern;

      final maxProbability = pattern.lanes
          .map((lane) => lane.spawnProbability)
          .reduce((a, b) => a > b ? a : b);
      final maxSpeed = pattern.lanes
          .map((lane) => lane.speedRange.max)
          .reduce((a, b) => a > b ? a : b);

      expect(maxProbability, lessThanOrEqualTo(0.75),
          reason: 'the old nightmare spawned at 0.95');
      expect(maxSpeed, lessThanOrEqualTo(200),
          reason: 'the old nightmare closed at 250 px/s');
      expect(pattern.spawnInterval, greaterThanOrEqualTo(1.5),
          reason: 'the old nightmare spawned every second');
    });

    test('banking is taught last, by the final two rungs', () async {
      for (var i = 1; i <= GameLevel.ladderLength; i++) {
        final level = await levelLoader.loadLevel(i);
        expect(level.bankPromptEnabled, i >= 9,
            reason: 'level $i got the bank-or-push flag wrong');
      }
    });

    test('every rung is a well-formed route down the road', () async {
      for (var i = 1; i <= GameLevel.ladderLength; i++) {
        final level = await levelLoader.loadLevel(i);

        expect(level.pickupPoints, isNotEmpty,
            reason: 'level $i has no fares');
        expect(level.pickupPoints.length, level.dropoffPoints.length,
            reason: 'level $i mismatches pickups and dropoffs');

        for (var f = 0; f < level.pickupPoints.length; f++) {
          final pickup = level.pickupPoints[f];
          final dropoff = level.dropoffPoints[f];

          // The road spans x 100..300 and the kerbs sit at 85 and 315.
          for (final point in [pickup, dropoff]) {
            expect(point.x, inInclusiveRange(85, 315),
                reason: 'level $i fare $f parks off the street');
          }
          // The taxi only drives up (negative y), so every pickup must
          // sit below its dropoff.
          expect(pickup.y, greaterThan(dropoff.y),
              reason: 'level $i fare $f asks the taxi to drive backwards');
        }
      }
    });

    test('every fare is winnable at a cautious learner pace', () async {
      // A new player will not hold the throttle flat out (the starter cab
      // tops at 150 px/s). A third of that must still beat the meter on
      // every ride in the ladder — the fare timer teaches, it does not
      // punish.
      const learnerSpeed = 55.0;

      for (var i = 1; i <= GameLevel.ladderLength; i++) {
        final level = await levelLoader.loadLevel(i);
        for (var f = 0; f < level.pickupPoints.length; f++) {
          final ride =
              (level.dropoffPoints[f] - level.pickupPoints[f]).length;
          final budget = FareChain.secondsForRide(ride);

          expect(budget * learnerSpeed, greaterThanOrEqualTo(ride),
              reason: 'level $i fare $f cannot be run in time at '
                  '$learnerSpeed px/s');
        }
      }
    });
  });

  group('the banking rungs', () {
    late GameStateService saveAtNine;

    setUp(() async {
      saveAtNine = await gameStateAtLevel(9);
    });

    /// The rung under test, mounted and settled. `loadLevel(9)` after the
    /// mount replaces the level the save pointed at.
    Future<TaxiGame> mountBankLevel() async {
      final game = await mountGame(ladderGame(saveAtNine));
      await game.loadLevel(9);
      await tickAndSettle(game);
      return game;
    }

    test('a dropoff with fares still open arms the real choice', () async {
      final game = await mountBankLevel();
      final level = game.currentLevel;
      expect(level.bankPromptEnabled, isTrue);

      await rideTo(
        game,
        level.pickupPoints.first,
        level.dropoffPoints.first,
      );

      expect(game.passengersDelivered, 1);
      expect(game.bankPrompt.isActive, isTrue);
      expect(game.overlays.isActive('bankOrPush'), isTrue);
      // The question is asked over a live level, exactly as over a live
      // shift.
      expect(game.isGameActive, isTrue);
    });

    test('banking pays the score 1:1 in coins and settles the level',
        () async {
      final game = await mountBankLevel();
      final level = game.currentLevel;
      final coinsBefore = saveAtNine.totalCoins;

      await rideTo(
        game,
        level.pickupPoints.first,
        level.dropoffPoints.first,
      );
      final score = game.score;
      expect(score, greaterThan(0));

      game.bankShift();

      expect(game.lastBankedScore, score,
          reason: 'the bank converts the whole chain score');
      // The bank is the whole payout (issue #34): the chain score OR the
      // flat level reward, never both. Banking forfeits the reward along
      // with the undelivered fares — the same trade an endless bank makes.
      expect(saveAtNine.totalCoins, coinsBefore + score,
          reason: 'only the bank lands in the wallet — no reward on top');
      expect(level.coinReward, greaterThan(0),
          reason: 'the rung does carry a reward, which banking gives up');
      expect(game.isGameActive, isFalse, reason: 'the level is settled');
      expect(game.overlays.isActive('levelComplete'), isTrue);
      expect(game.overlays.isActive('bankOrPush'), isFalse);
      // Settling rung 9 unlocks rung 10 — banking is a success, not a
      // forfeit.
      expect(saveAtNine.currentLevel, 10);
      expect(saveAtNine.tutorialComplete, isFalse);
    });

    test('pushing on steps the multiplier, and the final delivery '
        'completes the level without a bank payout', () async {
      final game = await mountBankLevel();
      final level = game.currentLevel;
      final coinsBefore = saveAtNine.totalCoins;

      await rideTo(
        game,
        level.pickupPoints.first,
        level.dropoffPoints.first,
      );
      expect(game.fareChain.multiplier, 2, reason: 'the delivery stepped it');

      game.pushOn();

      expect(game.fareChain.multiplier, 3);
      expect(game.bankPrompt.isActive, isFalse);
      expect(game.isGameActive, isTrue);

      await rideTo(
        game,
        level.pickupPoints.last,
        level.dropoffPoints.last,
      );

      expect(game.passengersDelivered, 2);
      expect(game.overlays.isActive('levelComplete'), isTrue);
      expect(game.lastBankedScore, isNull,
          reason: 'no bank happened, so no bank line');
      expect(saveAtNine.totalCoins, coinsBefore + level.coinReward,
          reason: 'completion pays the level reward alone');
      expect(game.isGameActive, isFalse);
    });

    test('a crash with the choice open fails the level and forfeits the '
        'unbanked score', () async {
      final game = await mountBankLevel();
      final coinsBefore = saveAtNine.totalCoins;

      final level = game.currentLevel;
      await rideTo(
        game,
        level.pickupPoints.first,
        level.dropoffPoints.first,
      );
      expect(game.bankPrompt.isActive, isTrue);
      expect(game.score, greaterThan(0));

      game.onCrash();

      expect(game.bankPrompt.isActive, isFalse);
      expect(game.overlays.isActive('levelFailed'), isTrue);
      expect(saveAtNine.totalCoins, coinsBefore,
          reason: 'nothing unbanked ever reached the wallet');
      expect(game.isGameActive, isFalse);
    });

    test('delivering the last fare while a choice is open settles the '
        'level once and stands the choice down', () async {
      final game = await mountBankLevel();
      final level = game.currentLevel;
      final coinsBefore = saveAtNine.totalCoins;

      // Both passengers aboard, then two dropoffs in quick succession:
      // the second lands while the first's prompt is still up.
      await rideTo(
        game,
        level.pickupPoints.first,
        level.pickupPoints.last,
      );
      expect(game.player.hasPassenger, isTrue);

      game.player.position =
          Vector2(level.dropoffPoints.first.x, level.dropoffPoints.first.y + 30);
      game.update(1 / 60);
      await drain();
      expect(game.bankPrompt.isActive, isTrue, reason: 'the open choice');

      game.player.position =
          Vector2(level.dropoffPoints.last.x, level.dropoffPoints.last.y + 30);
      game.update(1 / 60);
      await drain();

      expect(game.passengersDelivered, 2);
      expect(game.overlays.isActive('levelComplete'), isTrue);
      expect(game.bankPrompt.isActive, isFalse,
          reason: 'a settled level owes no choice');

      // And the stood-down prompt can never pay out twice.
      game.bankShift();
      expect(saveAtNine.totalCoins, coinsBefore + level.coinReward,
          reason: 'exactly the level reward was paid, exactly once');
    });

    test('rungs that do not teach banking arm nothing', () async {
      final game = await mountGame(ladderGame());
      await game.loadLevel(3);
      await tickAndSettle(game);

      final level = game.currentLevel;
      expect(level.bankPromptEnabled, isFalse);
      expect(level.pickupPoints.length, greaterThan(1),
          reason: 'a multi-fare level, so the offer would be possible');

      await rideTo(
        game,
        level.pickupPoints.first,
        level.dropoffPoints.first,
      );

      expect(game.passengersDelivered, 1);
      expect(game.bankPrompt.isActive, isFalse);
      expect(game.overlays.isActive('bankOrPush'), isFalse);
      expect(game.isGameActive, isTrue);
    });
  });

  group('the end state hands off to Endless', () {
    test('rungs 1-9 have a next rung; rung 10 does not', () async {
      final game = await mountGame(ladderGame());
      await game.loadLevel(1);
      expect(game.hasNextLevel, isTrue);

      await game.loadLevel(GameLevel.ladderLength);
      expect(game.hasNextLevel, isFalse);
    });

    test('startNextLevel advances within the ladder and refuses past it',
        () async {
      final game = await mountGame(ladderGame());

      expect(await game.startNextLevel(), isTrue);
      expect(game.currentLevelNumber, 2);

      await game.loadLevel(GameLevel.ladderLength);
      expect(await game.startNextLevel(), isFalse,
          reason: 'there is no rung 11');
    });

    test('startFirstShift begins an endless shift in the same session',
        () async {
      final game = await mountGame(ladderGame());
      await game.loadLevel(GameLevel.ladderLength);
      game.overlays.add('levelComplete');

      game.startFirstShift();

      expect(game.overlays.isActive('levelComplete'), isFalse);
      expect(game.isEndless, isTrue);
      expect(game.isGameActive, isTrue);
      expect(game.score, 0);
      expect(game.lives.remaining, LivesTracker.maxLives,
          reason: 'a fresh shift starts with a full budget');
      expect(game.lastRunSummary, isNull);
    });

    test('a save past the last rung opens onto Endless, never a level-10 '
        'replay', () async {
      final finished = await gameStateAtLevel(GameLevel.ladderLength + 1);
      expect(finished.tutorialComplete, isTrue);

      final game = await mountGame(ladderGame(finished));

      expect(game.isEndless, isTrue,
          reason: 'the ladder is done; the handoff is the end state');
      expect(game.isGameActive, isTrue);
      expect(game.faresDelivered, 0);
    });

    test('a fresh save still starts the ladder at rung 1', () async {
      final game = await mountGame(ladderGame());

      expect(game.isEndless, isFalse);
      expect(game.currentLevelNumber, 1);
      expect(gameState.tutorialComplete, isFalse);
    });

    test('tutorialComplete reads true only past the last rung', () async {
      expect((await gameStateAtLevel(1)).tutorialComplete, isFalse);
      expect((await gameStateAtLevel(GameLevel.ladderLength)).tutorialComplete,
          isFalse);
      expect(
          (await gameStateAtLevel(GameLevel.ladderLength + 1))
              .tutorialComplete,
          isTrue);
    });
  });

  group('levels keep their authored dropoffs (issue #28)', () {
    test('driving past a level dropoff never relocates it', () async {
      final game = await mountGame(ladderGame());
      await tickAndSettle(game);
      expect(game.isEndless, isFalse);

      final zone = game.world.children.whereType<DropoffZone>().first;
      final authored = zone.position.clone();

      // Drive straight past the dropoff down the road's middle: level
      // objectives are hand-placed and mandatory, and issue #28's
      // forgiveness is an endless-run behaviour only.
      game.player.position = Vector2(200, authored.y - 400);
      game.update(1 / 60);
      await drain();

      expect(zone.position, authored);
    });
  });

  group('the completion panel', () {
    /// Loads [levelNumber] into a mounted game, inside [tester.runAsync]:
    /// mounting loads real sprite assets, and real IO can only complete
    /// in the test binding's real-async window (the pattern
    /// `bank_or_push_test.dart` uses). Everything after is synchronous —
    /// the panel reads only fields, so no ticks are needed.
    Future<TaxiGame> panelGame(WidgetTester tester, int levelNumber) async {
      return (await tester.runAsync<TaxiGame>(() async {
        final game = await mountGame(ladderGame());
        await game.loadLevel(levelNumber);
        return game;
      }))!;
    }

    Future<void> showPanel(WidgetTester tester, TaxiGame game) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LevelCompleteOverlay(game: game)),
        ),
      );
      await tester.pump();
    }

    testWidgets('mid-ladder it offers the next rung', (tester) async {
      final game = await panelGame(tester, 1);
      await showPanel(tester, game);

      expect(find.text('LEVEL COMPLETE!'), findsOneWidget);
      expect(find.text('+50 Coins'), findsOneWidget);
      expect(find.text('NEXT LEVEL'), findsOneWidget);
      expect(find.text('START SHIFT'), findsNothing);
    });

    testWidgets('past the last rung it offers the Endless handoff',
        (tester) async {
      final game = await panelGame(tester, GameLevel.ladderLength);
      await showPanel(tester, game);

      expect(find.text('TUTORIAL COMPLETE!'), findsOneWidget);
      expect(find.text('+300 Coins'), findsOneWidget);
      expect(find.text('START SHIFT'), findsOneWidget);
      expect(find.text('NEXT LEVEL'), findsNothing,
          reason: 'a next-level button could only dead-end here');
    });

    testWidgets('a bank shows its payout line', (tester) async {
      final game = await panelGame(tester, 9);
      game.lastBankedScore = 120;
      await showPanel(tester, game);

      // The bank is the payout (issue #34): the panel names it in coins
      // and does not also claim the flat reward that banking forfeited.
      expect(find.text('Banked: +120 Coins'), findsOneWidget);
      expect(find.text('+${game.currentLevel.coinReward} Coins'),
          findsNothing);
    });

    testWidgets('tapping START SHIFT begins the first endless shift',
        (tester) async {
      final game = await panelGame(tester, GameLevel.ladderLength);
      game.overlays.add('levelComplete');
      await showPanel(tester, game);

      await tester.tap(find.text('START SHIFT'));
      await tester.pump();

      expect(game.isEndless, isTrue);
      expect(game.isGameActive, isTrue);
      expect(game.overlays.isActive('levelComplete'), isFalse);
    });
  });
}
