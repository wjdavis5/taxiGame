import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

    test('the first pickup of every rung opens clear of the HUD chip band',
        () async {
      // Issue #45: with the camera centred on the taxi, the first marker
      // always materialised 150 px below the view top — inside the ~110 px
      // band the HUD chips occupy, hiding under the ×1 (rung 1) or the
      // SCORE 0 chip (rungs 2 and 3). The camera now leads the taxi by
      // [TaxiGame.levelCameraLead], and the start stays pinned 250 px
      // below the lowest marker, so the marker's depth below the view
      // top is structural: 400 (half the 800-tall frame) - 250 + lead.
      const viewHalf = 400.0; // TaxiGame's fixed-resolution frame
      for (var i = 1; i <= GameLevel.ladderLength; i++) {
        final game = await mountGame(
            ladderGame(await gameStateAtLevel(i)));
        game.update(1 / 60);

        // The first marker the player can reach is the route's lowest
        // point — the start is authored 250 px below it.
        final route = [
          ...game.currentLevel.pickupPoints,
          ...game.currentLevel.dropoffPoints,
        ];
        final firstMarkerY =
            route.map((p) => p.y).reduce((a, b) => a > b ? a : b);
        final viewTop = game.camera.viewfinder.position.y - viewHalf;
        final depth = firstMarkerY - viewTop;

        expect(depth, closeTo(250.0, 0.01),
            reason: 'rung $i: the first pickup must open 250 px below the '
                'view top (was 150 px, under the chips)');
        // And the viewfinder really is leading, not centred on the taxi.
        expect(game.camera.viewfinder.position.y,
            closeTo(game.player.position.y - TaxiGame.levelCameraLead, 0.01),
            reason: 'rung $i: the level camera must lead the taxi');
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

    /// Collects every fare the rung offers, then makes the first
    /// delivery — the realistic route, and since issue #112 the required
    /// one: a delivery made past an uncollected pickup strands that fare
    /// behind the one-way cab and fails the level. Leaves the game one
    /// delivery in with the bank choice armed (on the banking rungs) and
    /// the remaining fare aboard.
    Future<void> rideTheFirstDelivery(TaxiGame game) async {
      final level = game.currentLevel;
      await rideTo(game, level.pickupPoints.first, level.pickupPoints.last);
      game.player.position = Vector2(
          level.dropoffPoints.first.x, level.dropoffPoints.first.y + 30);
      game.update(1 / 60);
      await drain();
    }

    test('a dropoff with fares still open arms the real choice', () async {
      final game = await mountBankLevel();
      final level = game.currentLevel;
      expect(level.bankPromptEnabled, isTrue);

      await rideTheFirstDelivery(game);

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

      await rideTheFirstDelivery(game);
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

      await rideTheFirstDelivery(game);
      expect(game.fareChain.multiplier, 2, reason: 'the delivery stepped it');

      game.pushOn();

      expect(game.fareChain.multiplier, 3);
      expect(game.bankPrompt.isActive, isFalse);
      expect(game.isGameActive, isTrue);

      // The remaining fare is already aboard (collected en route, as
      // the one-way street now demands — issue #112): straight to its
      // kerb for the completing delivery.
      game.player.position = Vector2(
          level.dropoffPoints.last.x, level.dropoffPoints.last.y + 30);
      game.update(1 / 60);
      await drain();

      expect(game.passengersDelivered, 2);
      expect(game.overlays.isActive('levelComplete'), isTrue);
      expect(game.lastBankedScore, isNull,
          reason: 'no bank happened, so no bank line');
      // The pushed finish pays the better of the two payouts on a rung
      // that teaches banking (issue #155): the run rode 125 at ×1, pushed
      // to ×3, and finished 125 + 375 = 500 — above the flat 250 reward,
      // which can no longer cap it below what a bank would have paid.
      expect(game.score, 500, reason: '125 ridden, 375 pushed');
      expect(game.lastCompletionPayout, 500,
          reason: 'the panel names the payout actually credited');
      expect(saveAtNine.totalCoins, coinsBefore + 500,
          reason: 'completion pays max(score, reward) — the score here');
      expect(game.isGameActive, isFalse);
    });

    test('a crash with the choice open fails the level and forfeits the '
        'unbanked score', () async {
      final game = await mountBankLevel();
      final coinsBefore = saveAtNine.totalCoins;

      await rideTheFirstDelivery(game);
      expect(game.bankPrompt.isActive, isTrue);
      expect(game.score, greaterThan(0));

      game.onCrash();

      expect(game.bankPrompt.isActive, isFalse);
      expect(game.overlays.isActive('levelFailed'), isTrue);
      expect(game.lastFailReason, LevelFailReason.crash,
          reason: 'a collision is still worded as one (issue #112 split '
              'the reasons)');
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

      // And the stood-down prompt can never pay out twice. The open
      // choice resolved as its default push the moment the second kerb
      // scored it (issue #186): the ridden finish is 125 at ×1 plus 375
      // at the pushed ×3 = 500 — the better of the two payouts (issue
      // #155) — and the stray BANK cannot top it up.
      game.bankShift();
      expect(game.score, 500, reason: '125 at ×1, 375 at the pushed ×3');
      expect(saveAtNine.totalCoins, coinsBefore + 500,
          reason: 'exactly max(score, reward) was paid, exactly once');
    });

    test('rungs that do not teach banking arm nothing', () async {
      final game = await mountGame(ladderGame());
      await game.loadLevel(3);
      await tickAndSettle(game);

      final level = game.currentLevel;
      expect(level.bankPromptEnabled, isFalse);
      expect(level.pickupPoints.length, greaterThan(1),
          reason: 'a multi-fare level, so the offer would be possible');

      await rideTheFirstDelivery(game);

      expect(game.passengersDelivered, 1);
      expect(game.bankPrompt.isActive, isFalse);
      expect(game.overlays.isActive('bankOrPush'), isFalse);
      expect(game.isGameActive, isTrue);
    });
  });

  group('the graduation rung makes the last choice real (issue #155)', () {
    // Level 10 — three fares at 100 each, flat reward 300 — is where the
    // issue lived: its second bank-or-push prompt offered BANK 300-400
    // while PUSH ON to the finish paid a flat 300 whatever the chain had
    // earned, so pushing on could only lose. The unbanked finish now pays
    // the better of the chain score and the flat reward, and both ways of
    // playing the rung — riding the chain, or pushing both prompts — must
    // show the push beating the bank it declined.

    late GameStateService saveAtTen;

    setUp(() async {
      saveAtTen = await gameStateAtLevel(10);
    });

    Future<TaxiGame> mountGraduation() async {
      final game = await mountGame(ladderGame(saveAtTen));
      await game.loadLevel(10);
      await tickAndSettle(game);
      expect(game.currentLevel.pickupPoints, hasLength(3));
      expect(game.currentLevel.coinReward, 300);
      return game;
    }

    /// Collects every fare the rung offers — a delivery made past an
    /// uncollected pickup strands the fare (issue #112), so all three
    /// board before any kerb.
    Future<void> collectFares(TaxiGame game) async {
      for (final pickup in game.currentLevel.pickupPoints) {
        game.player.position = Vector2(pickup.x, pickup.y + 30);
        game.update(1 / 60);
        await drain();
      }
      expect(game.player.hasPassenger, isTrue);
    }

    /// Delivers fare [index] to its authored kerb.
    Future<void> deliver(TaxiGame game, int index) async {
      final dropoff = game.currentLevel.dropoffPoints[index];
      game.player.position = Vector2(dropoff.x, dropoff.y + 30);
      game.update(1 / 60);
      await drain();
    }

    test('riding the chain, pushing the last choice beats banking it',
        () async {
      // The bank's offer: two ridden deliveries — the second reached
      // straight through the first's open prompt, which resolves as its
      // default push (issue #186): 100 at ×1, 300 at the superseded
      // push's ×3 — then BANK at the second prompt, the exact decision
      // the issue found one-sided.
      final banked = await mountGraduation();
      await collectFares(banked);
      await deliver(banked, 0);
      await deliver(banked, 1);
      expect(banked.bankPrompt.isActive, isTrue,
          reason: 'the second prompt is where the issue lived');
      banked.bankShift();
      expect(banked.lastBankedScore, 400,
          reason: 'the bankable chain is 100 + 300 at the pushed ×3');

      // The push's payoff: the same ride, PUSH ON at that prompt, and the
      // last fare delivered at the ×5 both pushes bought — 100 + 300 +
      // 500.
      final coinsBefore = saveAtTen.totalCoins;
      final pushed = await mountGraduation();
      await collectFares(pushed);
      await deliver(pushed, 0);
      await deliver(pushed, 1);
      pushed.pushOn();
      await deliver(pushed, 2);

      expect(pushed.overlays.isActive('levelComplete'), isTrue);
      expect(pushed.score, 900,
          reason: '100 at ×1, 300 at the superseded push\'s ×3, 500 at '
              'the explicitly pushed ×5');
      expect(pushed.lastCompletionPayout, 900,
          reason: 'the panel names the payout actually credited');
      expect(saveAtTen.totalCoins, coinsBefore + 900,
          reason: 'the finish pays the score it earned, not the flat 300');
      expect(900, greaterThan(banked.lastBankedScore!),
          reason: 'the choice the issue asked for: pushing on can win');
    });

    test('pushing both prompts beats banking the pushed chain', () async {
      // The bank's offer: PUSH ON at the first prompt (×3), one more
      // ridden delivery, then BANK at the second — 100 + 300.
      final banked = await mountGraduation();
      await collectFares(banked);
      await deliver(banked, 0);
      banked.pushOn();
      await deliver(banked, 1);
      banked.bankShift();
      expect(banked.lastBankedScore, 400,
          reason: 'the pushed chain banks 100 + 300');

      // The push's payoff: both prompts pushed (×3, then ×5) and the run
      // finished — 100 + 300 + 500.
      final coinsBefore = saveAtTen.totalCoins;
      final pushed = await mountGraduation();
      await collectFares(pushed);
      await deliver(pushed, 0);
      pushed.pushOn();
      await deliver(pushed, 1);
      pushed.pushOn();
      await deliver(pushed, 2);

      expect(pushed.overlays.isActive('levelComplete'), isTrue);
      expect(pushed.score, 900,
          reason: '100 at ×1, 300 at the first pushed ×3, 500 at ×5');
      expect(saveAtTen.totalCoins, coinsBefore + 900,
          reason: 'the finish pays the score it earned, not the flat 300');
      expect(900, greaterThan(banked.lastBankedScore!),
          reason: 'even the richer bank loses to finishing the push');
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

  group('a stranded fare fails the level (issue #112)', () {
    // The issue's own scenario: the cab misses one pickup or drop-off,
    // and a level street runs one way — the fare behind it can never be
    // completed, but nothing ended the run: the cab parked at the road's
    // end with no fail, no retry, and no message. The verdict is the
    // existing failure flow with a reason of its own; RETRY on the
    // panel restarts the rung.

    /// Rung 1 mounted and settled: a single fare whose pickup (y 400)
    /// and dropoff (y -300) bracket the whole course.
    Future<TaxiGame> mountRungOne() async {
      final game = await mountGame(ladderGame());
      await game.loadLevel(1);
      await tickAndSettle(game);
      expect(game.isEndless, isFalse);
      expect(game.currentLevel.pickupPoints, hasLength(1));
      return game;
    }

    test('sailing past the unpicked pickup fails with the missed-fare '
        'reason, and RETRY answers', () async {
      final game = await mountRungOne();
      final pickupY = game.currentLevel.pickupPoints.first.y;

      // Down the road's middle — nowhere near the kerb the pickup sits
      // on — and 200 px beyond it: the fare can never be collected now.
      game.player.position = Vector2(200, pickupY - 200);
      game.update(1 / 60);

      expect(game.isGameActive, isFalse,
          reason: 'the one-way street makes the missed pickup '
              'unreachable');
      expect(game.lastFailReason, LevelFailReason.fareMissed);
      expect(game.overlays.isActive('levelFailed'), isTrue);

      // RETRY is the recovery the panel promises: the rung restarts
      // below every zone, verdict cleared. (A plain bounded wait, not
      // tickAndSettle — restartLevel kicks loadLevel off un-awaited.)
      game.restartLevel();
      for (var i = 0; i < 100 && !game.isGameActive; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(game.isGameActive, isTrue, reason: 'RETRY re-runs the rung');
      expect(game.lastFailReason, isNull);
      expect(game.overlays.isActive('levelFailed'), isFalse);
    });

    test('carrying a fare past its dropoff fails it the same way', () async {
      final game = await mountRungOne();
      final level = game.currentLevel;

      // Collect the fare...
      game.player.position = Vector2(
          level.pickupPoints.first.x, level.pickupPoints.first.y + 30);
      game.update(1 / 60);
      await drain();
      expect(game.player.hasPassenger, isTrue);

      // ...then sail past its kerb down the middle of the road.
      game.player.position =
          Vector2(200, level.dropoffPoints.first.y - 200);
      game.update(1 / 60);

      expect(game.isGameActive, isFalse,
          reason: 'the carried fare can never be delivered');
      expect(game.lastFailReason, LevelFailReason.fareMissed);
      expect(game.overlays.isActive('levelFailed'), isTrue);
    });

    test('the grace margin forgives a graze — 80 px, the endless rule',
        () async {
      final game = await mountRungOne();
      final pickupY = game.currentLevel.pickupPoints.first.y;

      // 79 px past the needed zone still counts as at it (the mirror
      // of the endless passHysteresis); 81 px is stranded.
      game.player.position = Vector2(200, pickupY - 79);
      game.update(1 / 60);
      expect(game.isGameActive, isTrue,
          reason: 'inside the grace the fare is not yet stranded');

      game.player.position = Vector2(200, pickupY - 81);
      game.update(1 / 60);
      expect(game.isGameActive, isFalse,
          reason: 'past the grace, the fare is behind the cab for good');
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

    testWidgets('the title stays one centred line at every iPhone width '
        '(issue #159)', (tester) async {
      // "TUTORIAL COMPLETE!" is wider than the panel on every standard
      // iPhone (296 px of bold type in a 255-273 px panel at 375-393 pt),
      // and the bare Text had no scale-down box — it wrapped into two
      // flush-left lines while everything around it sat centred. Both
      // branches ride the same box now, so both are pinned. Ahem
      // advances a square per glyph — roughly twice Roboto — so the
      // unfixed Text wrapped at every one of these widths: the check is
      // strictly conservative, failing on anything the real font could
      // show (the garage width-sweep reasoning, issue #156).
      addTearDown(tester.view.reset);
      final handoff = await panelGame(tester, GameLevel.ladderLength);
      final midLadder = await panelGame(tester, 1);
      final panels = <(TaxiGame, String)>[
        (handoff, 'TUTORIAL COMPLETE!'),
        (midLadder, 'LEVEL COMPLETE!'),
      ];

      for (final width in [320.0, 375.0, 390.0, 393.0]) {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1.0;

        for (final (game, title) in panels) {
          await showPanel(tester, game);

          final finder = find.text(title);
          expect(finder, findsOneWidget);
          // One line of ink: this Text sets no maxLines, so the garage
          // test's didExceedMaxLines pin cannot see a wrap — the
          // paragraph's own height can (one Ahem line ≈ the font size,
          // two ≈ double).
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          final fontSize = tester.widget<Text>(finder).style!.fontSize!;
          expect(
            paragraph.size.height,
            lessThan(fontSize * 1.5),
            reason: '$title must be a single line on a ${width.round()} pt '
                'screen — two Ahem lines measure ~${(fontSize * 2).round()}',
          );
          // And the line it laid out under was unbounded — the
          // scale-down box's doing. A bare Text holds the panel's width
          // as its constraint, and that is what wraps it.
          expect(paragraph.constraints.maxWidth, equals(double.infinity),
              reason: '$title must lay out under the FittedBox\'s '
                  'unbounded width to be wrap-proof');
        }
      }
    });
  });

  group('the failure panel (issue #112)', () {
    /// Rung 1 mounted inside [tester.runAsync] — mounting loads real
    /// sprite assets, and real IO only completes in the test binding's
    /// real-async window (the completion-panel group's pattern).
    Future<TaxiGame> failureGame(WidgetTester tester) async {
      return (await tester.runAsync<TaxiGame>(() async {
        final game = await mountGame(ladderGame());
        await game.loadLevel(1);
        return game;
      }))!;
    }

    Future<void> showPanel(WidgetTester tester, TaxiGame game) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LevelFailedOverlay(game: game)),
        ),
      );
      await tester.pump();
    }

    testWidgets('a missed fare is worded as one, not as a crash',
        (tester) async {
      final game = await failureGame(tester);
      game.lastFailReason = LevelFailReason.fareMissed;
      await showPanel(tester, game);

      expect(find.text('FARE MISSED!'), findsOneWidget);
      expect(
          find.textContaining('the street only runs one way'),
          findsOneWidget,
          reason: 'the panel must say why the run ended, in the player\'s '
              'own terms — a route gone wrong, not a collision');
      expect(find.text('CRASH!'), findsNothing);
      expect(find.text('RETRY'), findsOneWidget,
          reason: 'the recovery the panel promises');
    });

    testWidgets('a crash still reads as a crash', (tester) async {
      final game = await failureGame(tester);
      game.lastFailReason = LevelFailReason.crash;
      await showPanel(tester, game);

      expect(find.text('CRASH!'), findsOneWidget);
      // No telemetry on this run: the fallback collision line.
      expect(find.text('You collided with traffic.'), findsOneWidget);
      expect(find.text('FARE MISSED!'), findsNothing);
    });

    testWidgets('the failure title stays one centred line at every iPhone '
        'width (issue #187)', (tester) async {
      // The completion title's #159 sweep, applied to the failure panel's
      // own title: 'FARE MISSED!' is 384 px of bold type against the 200
      // px this panel's column offers on a 320 pt phone, and the bare
      // Text wrapped into two flush-left lines while the panel sat
      // centred. Both branches ride the same scale-down box now, so both
      // are pinned. Ahem advances a square per glyph — roughly twice
      // Roboto — so the checks are strictly conservative (the garage
      // width-sweep reasoning, issue #156).
      addTearDown(tester.view.reset);
      final game = await failureGame(tester);

      for (final width in [320.0, 375.0, 390.0, 393.0]) {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1.0;

        for (final (reason, title) in [
          (LevelFailReason.fareMissed, 'FARE MISSED!'),
          (LevelFailReason.crash, 'CRASH!'),
        ]) {
          game.lastFailReason = reason;
          await showPanel(tester, game);

          final finder = find.text(title);
          expect(finder, findsOneWidget);
          // One line of ink: this Text sets no maxLines, so the
          // paragraph's own height is what sees a wrap (one Ahem line ≈
          // the font size, two ≈ double).
          final paragraph = tester.renderObject<RenderParagraph>(finder);
          final fontSize = tester.widget<Text>(finder).style!.fontSize!;
          expect(
            paragraph.size.height,
            lessThan(fontSize * 1.5),
            reason: '$title must be a single line on a ${width.round()} pt '
                'screen — two Ahem lines measure ~${(fontSize * 2).round()}',
          );
          // And the line it laid out under was unbounded — the
          // scale-down box's doing. A bare Text holds the panel's width
          // as its constraint, and that is what wraps it.
          expect(paragraph.constraints.maxWidth, equals(double.infinity),
              reason: '$title must lay out under the FittedBox\'s '
                  'unbounded width to be wrap-proof');
        }
      }
    });
  });
}
