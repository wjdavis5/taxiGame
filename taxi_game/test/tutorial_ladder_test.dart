import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/close_call_pop.dart';
import 'package:taxi_game/game/components/dropoff_zone.dart';
import 'package:taxi_game/game/components/pickup_zone.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/levels/level.dart';
import 'package:taxi_game/game/systems/collision_rules.dart';
import 'package:taxi_game/game/systems/fare_chain.dart';
import 'package:taxi_game/game/systems/lives.dart';
import 'package:taxi_game/game/systems/near_miss.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/game/vehicle_sprites.dart';
import 'package:taxi_game/models/save_data.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/screens/game_screen.dart';
import 'package:taxi_game/ui/widgets/hud_overlay.dart';

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
        // An unreadable rung throws from the loader (issue #229), so a
        // failure surfaces at the load itself; the name check stands as a
        // tripwire in case the old test-level substitution is ever
        // reintroduced.
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

  group('the close-call lesson (issue #269)', () {
    // Rung 8 — "Keep the Chain" before this issue — is the repurposed
    // lesson: its completion waits on one qualifying close call, and the
    // first award of the run states the rule the economy rests on.

    late GameStateService saveAtEight;

    setUp(() async {
      saveAtEight = await gameStateAtLevel(8);
    });

    /// The lesson rung mounted and settled.
    Future<TaxiGame> mountLesson() async {
      final game = await mountGame(ladderGame(saveAtEight));
      await game.loadLevel(8);
      await tickAndSettle(game);
      return game;
    }

    /// Puts the traffic sprites in the game's image cache so a
    /// test-added vehicle's `onLoad` completes after a microtask hop
    /// (the near-miss tests' determinism trick).
    Future<void> preloadTrafficSprites(TaxiGame game) async {
      for (final type in TrafficVehicleType.values) {
        await game.images.load(VehicleSprites.trafficSpritePath(type));
      }
    }

    /// A sedan parked in the player's path: zero speed, straight path,
    /// so the test controls the pass geometry exactly.
    TrafficVehicle parkedSedan(Vector2 position) => TrafficVehicle(
          position: position.clone(),
          vehicleType: TrafficVehicleType.sedan,
          baseSpeed: 0,
          path: [position.clone(), Vector2(position.x, position.y + 3000)],
        );

    /// Collects every fare, then rides each to its kerb — the whole
    /// route, with nobody shaved.
    Future<void> rideEveryFare(TaxiGame game) async {
      final level = game.currentLevel;
      for (final pickup in level.pickupPoints) {
        game.player.position = Vector2(pickup.x, pickup.y + 30);
        game.update(1 / 60);
        await drain();
      }
      for (final dropoff in level.dropoffPoints) {
        game.player.position = Vector2(dropoff.x, dropoff.y + 30);
        game.update(1 / 60);
        await drain();
      }
    }

    test('the ladder stays ten rungs and only the lesson requires a shave',
        () async {
      expect(GameLevel.ladderLength, 10);

      for (var i = 1; i <= GameLevel.ladderLength; i++) {
        final level = await levelLoader.loadLevel(i);
        expect(level.closeCallsRequired, i == 8 ? 1 : 0,
            reason: 'rung $i got the close-call requirement wrong');
      }
      final lesson = await levelLoader.loadLevel(8);
      expect(lesson.name, 'Shave the Traffic');
      expect(lesson.bankPromptEnabled, isFalse,
          reason: 'banking still belongs to rungs 9 and 10');
    });

    test('the lesson pins the qualifying window and the award it pays', () {
      // The five facts the lesson rests on (issue #269): a qualifying
      // pass sits in a gap of (-9, 14] px at 95 px/s or more, a touch
      // disqualifies (judged by the caller, pinned in near_miss_test),
      // and the award is 15 points at the live multiplier.
      expect(NearMissRules.gapThreshold, 14.0);
      expect(NearMissRules.contactSlack, 9.0);
      expect(NearMissRules.minPassSpeed, 95.0);
      expect(
        NearMissRules.isCloseCall(
            gap: NearMissRules.gapThreshold, playerForwardSpeed: 95.0),
        isTrue,
        reason: 'the window top and the speed floor both count',
      );
      expect(
        NearMissRules.isCloseCall(
            gap: NearMissRules.gapThreshold + 0.5, playerForwardSpeed: 95.0),
        isFalse,
        reason: 'a wider pass is lane-keeping, not a shave',
      );
      expect(
        NearMissRules.isCloseCall(gap: 10.0, playerForwardSpeed: 94.9),
        isFalse,
        reason: 'a slow pass never pays, however tight',
      );
      expect(FareChain.nearMissScore, 15);
    });

    test('delivering every fare does not complete the rung — the '
        'qualifying shave does, and the first award explains it', () async {
      final game = await mountLesson();
      await preloadTrafficSprites(game);
      final level = game.currentLevel;
      expect(level.closeCallsRequired, 1);

      // Collect every fare, then ride each to its kerb: the whole route,
      // with nobody shaved.
      await rideEveryFare(game);

      expect(game.passengersDelivered, level.pickupPoints.length);
      expect(game.fareChain.nearMisses, 0);
      expect(game.fareChain.multiplier, 4,
          reason: 'three on-time deliveries stepped the chain to \u00d74');
      expect(game.isGameActive, isTrue,
          reason: 'the rung is not done until its close call lands');
      expect(game.overlays.isActive('levelComplete'), isFalse);

      // Earn it: a sedan in the next lane over, 40 px ahead, so the pass
      // clears with 10 px of daylight at full throttle.
      game.player.position = Vector2(200, -900);
      game.player.isAccelerating = true;
      game.player.velocity = Vector2(0, -game.player.maxSpeed);
      game.world.add(parkedSedan(Vector2(150, -940)));
      await drain();

      var frames = 0;
      while (game.isGameActive &&
          game.player.position.y > -940 &&
          frames < 120) {
        game.update(1 / 60);
        frames++;
      }
      // The award's feedback was queued mid-update; one more tick mounts
      // it (the near-miss tests' settle step).
      game.update(1 / 60);
      await drain();

      expect(game.fareChain.nearMisses, 1);
      expect(game.fareChain.score, 510,
          reason: '75 at \u00d71, 150 at \u00d72, 225 at \u00d73, and the shave '
              'at the live \u00d74 \u2014 15 \u00d7 4 = 60, into the at-risk '
              'chain the deliveries built');
      expect(game.overlays.isActive('levelComplete'), isTrue,
          reason: 'the shave that lands the requirement completes the rung');
      expect(game.isGameActive, isFalse);

      // The first award states the rule (issue #269).
      final pop = game.world.children.whereType<CloseCallPop>().single;
      expect(
        pop.text,
        'CLOSE CALL +60\nSPEED + PROXIMITY FEED THE AT-RISK CHAIN',
        reason: 'the first award must state that speed and proximity feed '
            'the at-risk chain',
      );

      expect(saveAtEight.currentLevel, 9,
          reason: 'the lesson completed and unlocked the next rung');
    });

    test('reaching the road end without the shave fails the rung, and '
        'RETRY re-runs it', () async {
      final game = await mountLesson();
      final level = game.currentLevel;

      await rideEveryFare(game);
      expect(game.passengersDelivered, level.pickupPoints.length);
      expect(game.fareChain.nearMisses, 0);
      expect(game.isGameActive, isTrue);

      // The street end (issue #31) is the lesson's deadline. Waves keep
      // spawning until the taxi is ~650 px from the road top, so the
      // stretch just past the final dropoff is still shaving ground —
      // the completion test earns its shave there. The last ~600 px to
      // the clamp accept no new waves and the cab cannot reverse, so
      // only a car already on the road could still be met there — and
      // the clamp is where the lesson stops waiting for one. The verdict
      // is failure, not a dead end with only MAIN MENU as an exit.
      final roadTop = game.levelRoadTopY!;
      game.player.position = Vector2(
          TaxiGame.roadCenterX, roadTop + game.player.vehicleSize.y + 1);
      game.player.isAccelerating = true;
      game.player.velocity = Vector2(0, -game.player.maxSpeed);
      game.update(1 / 60);
      await drain();

      expect(game.isGameActive, isFalse,
          reason: 'the lesson cannot be completed past the street end');
      expect(game.lastFailReason, LevelFailReason.closeCallMissed);
      expect(game.overlays.isActive('levelFailed'), isTrue);

      // RETRY is the recovery the panel promises (the #112 pattern):
      // the rung re-runs from below every zone, verdict cleared.
      game.restartLevel();
      for (var i = 0; i < 100 && !game.isGameActive; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(game.isGameActive, isTrue, reason: 'RETRY re-runs the rung');
      expect(game.lastFailReason, isNull);
      expect(game.overlays.isActive('levelFailed'), isFalse);
      expect(game.fareChain.nearMisses, 0,
          reason: 'the retry owes the shave again');
    });

    testWidgets('the HUD asks for the shave until the award lands',
        (tester) async {
      final game = (await tester.runAsync<TaxiGame>(() async {
        return mountLesson();
      }))!;

      await tester.pumpWidget(
        ChangeNotifierProvider<GameStateService>.value(
          value: saveAtEight,
          child: MaterialApp(home: Scaffold(body: HudOverlay(game: game))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.text('CLOSE CALL TO FINISH \u2014 SHAVE A CAR AT SPEED'),
        findsOneWidget,
        reason: 'the rung explains what its completion is waiting for',
      );

      game.fareChain.awardNearMiss();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.text('CLOSE CALL TO FINISH \u2014 SHAVE A CAR AT SPEED'),
        findsNothing,
        reason: 'the ask stands down once the shave is in',
      );
    });

    testWidgets('the HUD ask stands down behind the failure panel',
        (tester) async {
      final game = (await tester.runAsync<TaxiGame>(() async {
        return mountLesson();
      }))!;

      await tester.pumpWidget(
        ChangeNotifierProvider<GameStateService>.value(
          value: saveAtEight,
          child: MaterialApp(home: Scaffold(body: HudOverlay(game: game))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.text('CLOSE CALL TO FINISH \u2014 SHAVE A CAR AT SPEED'),
        findsOneWidget,
      );

      // The run settles without the shave: the failure panel owns the
      // screen, and the ask must not sit behind it — the pause button's
      // isShiftOver stand-down (issue #52) applied to this line too.
      game.onLevelFailed();
      expect(game.lessonCloseCallOwed, isTrue,
          reason: 'the shave is still owed; only the settled run hides it');
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        find.text('CLOSE CALL TO FINISH \u2014 SHAVE A CAR AT SPEED'),
        findsNothing,
        reason: 'a settled run has no lesson line, owed or not',
      );
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

  group('the completion path never reads the level probe (issue #229)', () {
    /// A mounted-able game whose loader is [loader], with the overlay
    /// stand-ins a headless game needs.
    TaxiGame probeGame(GameStateService state, LevelLoaderService loader) =>
        TaxiGame(levelLoader: loader, gameState: state)
          ..overlays
              .addEntry('levelComplete', (_, __) => const SizedBox.shrink())
          ..overlays
              .addEntry('levelFailed', (_, __) => const SizedBox.shrink())
          ..overlays
              .addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
          ..overlays
              .addEntry('shiftBanked', (_, __) => const SizedBox.shrink());

    /// Answers every existence probe `false` — a manifest that lost the
    /// level list — while the loads themselves work. The completion path
    /// must not consult it: inside the ladder a declared rung is missing
    /// only as a load failure, which surfaces.
    TaxiGame deadProbeGame(GameStateService state) =>
        probeGame(state, _DeadProbeLevelLoader());

    /// Rides the graduation rung to completion: every fare boarded, the
    /// mid-route bank choice resolved with PUSH ON.
    Future<void> rideGraduationToCompletion(TaxiGame game) async {
      final level = game.currentLevel;
      for (final pickup in level.pickupPoints) {
        game.player.position = Vector2(pickup.x, pickup.y + 30);
        game.update(1 / 60);
        await drain();
      }
      for (var i = 0; i < level.dropoffPoints.length; i++) {
        if (i == 1) game.pushOn();
        final dropoff = level.dropoffPoints[i];
        game.player.position = Vector2(dropoff.x, dropoff.y + 30);
        game.update(1 / 60);
        await drain();
      }
    }

    test('a dead probe cannot hide the next rung mid-ladder', () async {
      final game = await mountGame(deadProbeGame(await gameStateAtLevel(1)));
      expect(game.hasNextLevel, isTrue,
          reason: 'rung 2 is declared by the ladder, not by a probe');

      await tickAndSettle(game);
      final level = game.currentLevel;
      await rideTo(game, level.pickupPoints.first, level.dropoffPoints.first);

      expect(game.overlays.isActive('levelComplete'), isTrue);
      expect(game.gameState.currentLevel, 2);
      expect(game.gameState.tutorialComplete, isFalse);
      expect(game.isEndless, isFalse,
          reason: 'an inner rung must never silently hand off to Endless');

      // NEXT LEVEL advances through the real load, probe or no probe.
      expect(await game.startNextLevel(), isTrue);
      expect(game.currentLevelNumber, 2);
      expect(game.isEndless, isFalse);
    });

    test('a declared next rung that cannot be read surfaces from the advance',
        () async {
      final game = await mountGame(
        probeGame(await gameStateAtLevel(1), _RungOneOnlyLoader()),
      );
      await tickAndSettle(game);
      final level = game.currentLevel;
      await rideTo(game, level.pickupPoints.first, level.dropoffPoints.first);
      expect(game.overlays.isActive('levelComplete'), isTrue);

      // The load, not the probe, is the authority: rung 2 is declared,
      // so its failure throws instead of dead-ending the button or
      // starting a shift the save never earned.
      await expectLater(
        game.startNextLevel(),
        throwsA(isA<LevelLoadException>()),
      );
      expect(game.isEndless, isFalse);
    });

    testWidgets('a next rung that cannot load leaves the panel up with a '
        'message (issue #241)', (tester) async {
      final game = (await tester.runAsync<TaxiGame>(() async {
        final game = await mountGame(
          probeGame(await gameStateAtLevel(1), _RungOneOnlyLoader()),
        );
        await tickAndSettle(game);
        final level = game.currentLevel;
        await rideTo(game, level.pickupPoints.first, level.dropoffPoints.first);
        return game;
      }))!;
      expect(game.overlays.isActive('levelComplete'), isTrue);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LevelCompleteOverlay(game: game))),
      );
      await tester.pump();
      expect(find.text('NEXT LEVEL'), findsOneWidget);

      // The tap's load throws from inside startNextLevel. The panel must
      // survive the failed advance — it used to be torn down before the
      // load, leaving a frozen completed level and nothing to read — and
      // the handler must answer the throw with a human message instead
      // of letting it ride out of the button as an async error.
      await tester.tap(find.text('NEXT LEVEL'));
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'the load failure is answered in the panel, not thrown '
              'at the framework');
      expect(game.overlays.isActive('levelComplete'), isTrue,
          reason: 'only a load that landed may retire the panel');
      expect(find.text('LEVEL COMPLETE!'), findsOneWidget);
      expect(find.text('The next level could not be loaded.'), findsOneWidget);
      expect(game.isEndless, isFalse,
          reason: 'a failed advance must never land in Endless');
      expect(game.currentLevelNumber, 2,
          reason: 'the failed load stays on the rung it tried');
    });

    testWidgets('a doubled NEXT LEVEL tap starts one load, not two (issue '
        '#243)', (tester) async {
      final loader = _CountingLoader();
      final game = (await tester.runAsync<TaxiGame>(() async {
        final game = await mountGame(
          probeGame(await gameStateAtLevel(1), loader),
        );
        await tickAndSettle(game);
        final level = game.currentLevel;
        await rideTo(game, level.pickupPoints.first, level.dropoffPoints.first);
        return game;
      }))!;
      expect(loader.requested, [1],
          reason: 'precondition: the mount loaded rung 1 exactly once');

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LevelCompleteOverlay(game: game))),
      );
      await tester.pump();

      // Two taps inside one frame both reach the handler before the first
      // load's future settles. loadLevel advances the rung counter before
      // its first await, so an unlatched second call computes the rung
      // after next: two loads race and a designed rung is skipped. One
      // tap must be one load.
      await tester.tap(find.text('NEXT LEVEL'));
      await tester.tap(find.text('NEXT LEVEL'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(game.currentLevelNumber, 2,
          reason: 'the advance lands on the next rung, not the one after');
      expect(loader.requested, [1, 2],
          reason: 'one tap, one load — the latch swallows the same-frame '
              're-entry');
    });

    testWidgets('the final rung with a dead probe still reaches Endless',
        (tester) async {
      final game = (await tester.runAsync<TaxiGame>(() async {
        final game = await mountGame(deadProbeGame(
            await gameStateAtLevel(GameLevel.ladderLength)));
        await tickAndSettle(game);
        await rideGraduationToCompletion(game);
        return game;
      }))!;

      expect(game.overlays.isActive('levelComplete'), isTrue);
      expect(game.gameState.tutorialComplete, isTrue,
          reason: 'the save owns completion; the probe cannot deny it');
      expect(game.hasNextLevel, isFalse);
      expect(game.isEndless, isFalse,
          reason: 'still the ladder until the handoff button is tapped');

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LevelCompleteOverlay(game: game))),
      );
      await tester.pump();
      expect(find.text('TUTORIAL COMPLETE!'), findsOneWidget);
      expect(find.text('START SHIFT'), findsOneWidget);

      await tester.tap(find.text('START SHIFT'));
      await tester.pump();
      expect(game.isEndless, isTrue);
    });

    testWidgets('an inner rung with a dead probe never offers Endless',
        (tester) async {
      final game = (await tester.runAsync<TaxiGame>(() async {
        final game = await mountGame(deadProbeGame(await gameStateAtLevel(1)));
        await tickAndSettle(game);
        final level = game.currentLevel;
        await rideTo(game, level.pickupPoints.first, level.dropoffPoints.first);
        return game;
      }))!;

      expect(game.overlays.isActive('levelComplete'), isTrue);
      expect(game.gameState.tutorialComplete, isFalse);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LevelCompleteOverlay(game: game))),
      );
      await tester.pump();
      expect(find.text('LEVEL COMPLETE!'), findsOneWidget);
      expect(find.text('NEXT LEVEL'), findsOneWidget);
      expect(find.text('START SHIFT'), findsNothing,
          reason: 'a lying probe must not turn a mid-ladder rung into the '
              'tutorial\'s end');
      expect(game.isEndless, isFalse);
    });
  });

  group('the first fare is reachable (issue #266)', () {
    // Level 1's only pickup used to sit at the right kerb (315), where the
    // cab's reachable band (centre x 120..280) registered it only in its
    // outer 20 px: a natural centre-line first drive sailed past and the
    // level failed 80 px later. The pickup now sits in the right lane
    // (240), inside the straight-drive band, while the dropoff stays on
    // the right kerb and still asks for alignment.

    test('a natural straight drive from the start collects the first pickup',
        () async {
      final game = await mountGame(ladderGame());
      await tickAndSettle(game);
      expect(game.currentLevelNumber, 1);
      expect(game.currentLevel.pickupPoints, hasLength(1));

      // Full throttle, zero steering: the drive the control hint teaches
      // first. The pickup sits 250 px up the road; 240 frames is 4 s at
      // 60 fps, well inside the level's 4.5 s first traffic wave.
      game.player.startAccelerating();
      for (var i = 0; i < 240 && !game.player.hasPassenger; i++) {
        game.update(1 / 60);
        await drain();
      }

      expect(game.player.hasPassenger, isTrue,
          reason: 'a centre-line drive must register the first pickup');
      expect(game.isGameActive, isTrue,
          reason: 'the level must not fail a player still driving to it');
      expect(game.lastFailReason, isNull);
    });

    test('the pickup registers from the centre line, and the dropoff '
        'demands the kerb', () async {
      final game = await mountGame(ladderGame());
      await tickAndSettle(game);
      final pickup = game.currentLevel.pickupPoints.single;
      final dropoff = game.currentLevel.dropoffPoints.single;

      // A zone registers when the cab's scaled hitbox reaches its
      // detection circle: zone detection radius + half the hitbox width.
      // Both zones detect at 40 px (PickupZone / DropoffZone).
      final stats = game.player.stats;
      final hitboxHalf = stats.width * CollisionRules.playerHitboxScale / 2;
      final pickupReach = PickupZone.detectionRadius + hitboxHalf;
      final dropoffReach = DropoffZone.detectionRadius + hitboxHalf;
      const centreLine = TaxiGame.roadCenterX;
      final rightKerb =
          TaxiGame.roadCenterX + TaxiGame.roadWidth / 2 - stats.width / 2;

      // The first fare is inside the straight band with overlap to spare,
      // so the drive the hint teaches needs no correction.
      expect((pickup.x - centreLine).abs() + 5, lessThanOrEqualTo(pickupReach),
          reason: 'the first pickup must register from the centre line '
              'with at least 5 px of overlap');

      // The dropoff is out of the centre-line band but inside the
      // right-kerb one: the rung's alignment lesson.
      expect((dropoff.x - centreLine).abs(), greaterThan(dropoffReach),
          reason: 'the dropoff must not be collectable from the centre '
              'line — pulling over to the kerb is the lesson');
      expect((dropoff.x - rightKerb).abs(), lessThan(dropoffReach),
          reason: 'the dropoff must register for a kerb-aligned cab');
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
    /// Loads [levelNumber] into a mounted game whose save sits at that
    /// rung and has just completed it — the only state the panel is ever
    /// up in. The save transition is the real one ([GameStateService
    /// .completeLevel], the call the rung's finish makes), so the level-10
    /// panel reads a genuinely finished save and the handoff branch
    /// follows it (issue #229), inside [tester.runAsync]: mounting loads
    /// real sprite assets, and real IO can only complete in the test
    /// binding's real-async window (the pattern `bank_or_push_test.dart`
    /// uses). Everything after is synchronous — the panel reads only
    /// fields, so no ticks are needed.
    Future<TaxiGame> panelGame(WidgetTester tester, int levelNumber) async {
      return (await tester.runAsync<TaxiGame>(() async {
        final state = await gameStateAtLevel(levelNumber);
        final game = await mountGame(ladderGame(state));
        await game.loadLevel(levelNumber);
        state.completeLevel(levelNumber, 0);
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

    testWidgets('the title and payout stay one centred line at every iPhone '
        'width (issues #159, #201)', (tester) async {
      // "TUTORIAL COMPLETE!" is wider than the panel on every standard
      // iPhone (296 px of bold type in a 255-273 px panel at 375-393 pt),
      // and the bare Text had no scale-down box — it wrapped into two
      // flush-left lines while everything around it sat centred. #201
      // caught the payout line the same panel had missed: 'Banked:
      // +125 Coins' at 24 px wrapped on a 320 pt phone's ~200 px column,
      // and both its branches ride one box — the widget is either
      // branch's text, never two labels. Ahem advances a square per
      // glyph — roughly twice Roboto — so the unfixed Text wrapped at
      // every one of these widths: the check is strictly conservative,
      // failing on anything the real font could show (the garage
      // width-sweep reasoning, issue #156).
      addTearDown(tester.view.reset);
      final handoff = await panelGame(tester, GameLevel.ladderLength);
      final midLadder = await panelGame(tester, 1);
      // The handoff panel names a bank (issue #34); the mid-ladder one
      // falls to the flat reward branch — one game per branch.
      handoff.lastBankedScore = 125;
      final panels = <(TaxiGame, String)>[
        (handoff, 'TUTORIAL COMPLETE!'),
        (midLadder, 'LEVEL COMPLETE!'),
        (handoff, 'Banked: +125 Coins'),
        (midLadder, '+50 Coins'),
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
          find.textContaining('Pull over to the kerb'),
          findsOneWidget,
          reason: 'the panel must correct the miss, not just explain it '
              '(issue #266): pull to the kerb where fares wait');
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

    testWidgets('a missed close call names the lesson, not a crash',
        (tester) async {
      final game = await failureGame(tester);
      game.lastFailReason = LevelFailReason.closeCallMissed;
      await showPanel(tester, game);

      expect(find.text('CLOSE CALL MISSED!'), findsOneWidget);
      expect(
          find.textContaining('needs one close call at speed'), findsOneWidget,
          reason: 'the panel must say what the lesson wanted');
      expect(find.text('CRASH!'), findsNothing);
      expect(find.text('RETRY'), findsOneWidget,
          reason: 'the recovery the panel promises');
    });

    testWidgets('the failure title stays one centred line at every iPhone '
        'width (issue #187)', (tester) async {
      // The completion title's #159 sweep, applied to the failure panel's
      // own title: 'FARE MISSED!' is 384 px of bold type against the 200
      // px this panel's column offers on a 320 pt phone, and the bare
      // Text wrapped into two flush-left lines while the panel sat
      // centred. All three branches ride the same scale-down box now, so
      // all three are pinned — 'CLOSE CALL MISSED!' (issue #269) is the
      // longest of them. Ahem advances a square per glyph — roughly twice
      // Roboto — so the checks are strictly conservative (the garage
      // width-sweep reasoning, issue #156).
      addTearDown(tester.view.reset);
      final game = await failureGame(tester);

      for (final width in [320.0, 375.0, 390.0, 393.0]) {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1.0;

        for (final (reason, title) in [
          (LevelFailReason.fareMissed, 'FARE MISSED!'),
          (LevelFailReason.closeCallMissed, 'CLOSE CALL MISSED!'),
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

/// Every existence probe answers `false` — a manifest failure — while the
/// loads keep working (issue #229): the completion path must decide from
/// the ladder and the save, never from this.
class _DeadProbeLevelLoader extends LevelLoaderService {
  @override
  Future<bool> levelExists(int levelNumber) async => false;
}

/// A working loader that records every rung handed to it, so a doubled
/// NEXT LEVEL invocation's two loads would be visible as two rung
/// numbers (issue #243).
class _CountingLoader extends LevelLoaderService {
  final List<int> requested = <int>[];

  @override
  Future<GameLevel> loadLevel(int levelNumber) async {
    requested.add(levelNumber);
    return super.loadLevel(levelNumber);
  }
}

/// A dead probe plus a load failure for every rung but the first, so an
/// inner rung completes and its declared successor then fails to hand
/// over (issue #229).
class _RungOneOnlyLoader extends LevelLoaderService {
  @override
  Future<bool> levelExists(int levelNumber) async => false;

  @override
  Future<GameLevel> loadLevel(int levelNumber) async {
    if (levelNumber == 1) return super.loadLevel(levelNumber);
    throw LevelLoadException(
      levelNumber,
      'assets/levels/level_$levelNumber',
      StateError('unreadable'),
    );
  }
}
