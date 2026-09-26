import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_game/game/components/dropoff_zone.dart';
import 'package:taxi_game/game/components/pickup_zone.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/fare_chain.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/fare_type.dart';
import 'package:taxi_game/models/passenger_data.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';
import 'package:taxi_game/ui/widgets/hud_overlay.dart';

/// Passenger and fare variety (issue #25): four kinds of fare — standard,
/// VIP, long-haul, awkward — drawn deterministically from the run's seed,
/// legible at the kerb, and declinable, so every pickup is a decision.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FareType tuning', () {
    test('the VIP is the only get-rich-quick fare', () {
      expect(FareType.vip.rewardMultiplier, 3.0);
      expect(FareType.vip.rewardMultiplier, greaterThan(FareType.standard.rewardMultiplier));
      expect(FareType.vip.rewardMultiplier, greaterThan(FareType.awkward.rewardMultiplier));
      expect(FareType.awkward.rewardMultiplier, greaterThan(FareType.standard.rewardMultiplier),
          reason: 'the crossing pays a premium');
    });

    test('the VIP clock is much tighter; the long-haul clock is untouched',
        () {
      expect(FareType.vip.timeScale, lessThan(FareType.awkward.timeScale));
      expect(FareType.awkward.timeScale, lessThan(1.0),
          reason: 'the far-side crossing runs under pressure');
      expect(FareType.vip.timeScale, lessThan(0.7),
          reason: 'much tighter means much tighter');
      expect(FareType.longHaul.timeScale, 1.0,
          reason: 'the long-haul is long, not rushed — its clock scales '
              'with its ride like any standard fare');
    });

    test('only the long-haul boosts the chain', () {
      expect(FareType.longHaul.chainStepBonus, greaterThan(0));
      expect(FareType.standard.chainStepBonus, 0);
      expect(FareType.vip.chainStepBonus, 0,
          reason: 'the VIP is paid in coins, not chain');
      expect(FareType.awkward.chainStepBonus, 0);
    });

    test('the draw is deterministic given the same generator seed', () {
      final a = FareType.draw(math.Random(2026));
      final b = FareType.draw(math.Random(2026));
      expect(a, b);

      // And the full sequence replays identically.
      final seqA = [
        for (var i = 0; i < 50; i++) FareType.draw(math.Random(i)),
      ];
      final seqB = [
        for (var i = 0; i < 50; i++) FareType.draw(math.Random(i)),
      ];
      expect(seqA, seqB);
    });

    test('the mix honours its weights: seven standard, three specials',
        () {
      const draws = 4000;
      final counts = {for (final t in FareType.values) t: 0};
      final random = math.Random(99);
      for (var i = 0; i < draws; i++) {
        final type = FareType.draw(random);
        counts[type] = counts[type]! + 1;
      }

      for (final special in [FareType.vip, FareType.longHaul, FareType.awkward]) {
        final share = counts[special]! / draws;
        expect(share, greaterThan(0.05), reason: '$special share');
        expect(share, lessThan(0.15), reason: '$special share');
      }
      expect(counts[FareType.standard]! / draws, greaterThan(0.6),
          reason: 'standard rides stay the baseline of the street');
    });
  });

  group('the seeded course draws its variety', () {
    test('same seed, same fares and kinds, in any query order', () {
      final a = EndlessCourse(seed: 314);
      final b = EndlessCourse(seed: 314);

      const count = 300;
      final backwards = [
        for (var i = count - 1; i >= 0; i--) b.fare(i),
      ];
      for (var i = 0; i < count; i++) {
        final fa = a.fare(i);
        final fb = backwards[count - 1 - i];
        expect(fa.fareType, fb.fareType, reason: 'fare $i kind');
        expect(fa.pickup, fb.pickup, reason: 'fare $i pickup');
        expect(fa.dropoff, fb.dropoff, reason: 'fare $i dropoff');
        expect(fa.reward, fb.reward, reason: 'fare $i reward');
      }
    });

    test('every kind keeps the course invariants it promises', () {
      final course = EndlessCourse(seed: 2718);

      var sawLongHaul = false;
      var sawAwkward = false;
      var sawVip = false;

      for (var i = 0; i < 2000; i++) {
        final fare = course.fare(i);
        switch (fare.fareType) {
          case FareType.longHaul:
            sawLongHaul = true;
            // The distant dropoff: earliest pickup, the whole slot of
            // ride, tail margin respected. (closeTo, not equals: the
            // world's Vector2s store float32, and deep slots read
            // geometry a few thousandths off its true values.)
            expect(
              fare.pickup.y,
              closeTo(
                  -(i * EndlessCourse.slotLength) - EndlessCourse.minPickupInset,
                  0.01),
              reason: 'fare $i long-haul pickup inset',
            );
            expect(fare.rideLength,
                closeTo(EndlessCourse.longHaulRideLength, 0.01),
                reason: 'fare $i long-haul ride');
            expect(fare.rideLength,
                greaterThan(EndlessCourse.maxRideLength + EndlessCourse.rideGrowthMax),
                reason: 'the long-haul is visibly further than any standard ride');
          case FareType.awkward:
            sawAwkward = true;
            // The far-side crossing: opposite kerbs, shortest ride.
            expect(fare.dropoff.x, isNot(fare.pickup.x),
                reason: 'fare $i dropoff across the road');
            expect(
              {EndlessCourse.leftCurbX, EndlessCourse.rightCurbX},
              containsAll([fare.pickup.x, fare.dropoff.x]),
              reason: 'fare $i still parks on the kerbs',
            );
            expect(fare.rideLength, closeTo(EndlessCourse.awkwardRideLength, 0.01),
                reason: 'fare $i awkward ride is the shortest drawn');
          case FareType.vip:
            sawVip = true;
            // The VIP buys payout and clock, not geometry: a standard
            // ride the player can judge at a glance.
            expect(fare.rideLength,
                greaterThanOrEqualTo(EndlessCourse.minRideLength),
                reason: 'fare $i vip ride');
            expect(
              fare.rideLength,
              lessThanOrEqualTo(
                  EndlessCourse.maxRideLength + EndlessCourse.rideGrowthMax),
              reason: 'fare $i vip ride');
          case FareType.standard:
            break;
          }
        // Every fare still climbs the road, whatever its kind.
        expect(fare.dropoff.y, lessThan(fare.pickup.y),
            reason: 'fare $i dropoff above pickup');
      }

      expect(sawLongHaul, isTrue, reason: 'long-hauls appear on a course');
      expect(sawAwkward, isTrue, reason: 'awkward fares appear on a course');
      expect(sawVip, isTrue, reason: 'VIPs appear on a course');
    });

    test('special kinds scale the reward band, never break it', () {
      final course = EndlessCourse(seed: 161);

      for (var i = 0; i < 2000; i++) {
        final fare = course.fare(i);
        final base = 20 + (fare.rideLength / 30).round();
        final expected = base * fare.fareType.rewardMultiplier;
        // The slot bonus (0-15 coins) scales with the kind's multiplier,
        // so the slop does too.
        expect(fare.reward, closeTo(expected, 16 * fare.fareType.rewardMultiplier),
            reason: 'fare $i reward scales by ${fare.fareType.name}');

        // The VIP is always the money shot: triple the base is past the
        // whole standard band's ceiling.
        if (fare.fareType == FareType.vip) {
          expect(fare.reward, greaterThan(70),
              reason: 'a VIP out-pays any standard fare');
        }
      }
    });
  });

  group('the chain prices the kinds', () {
    PassengerData fareOfType(FareType type, String id,
            {double pickupY = 400, double dropoffY = -300}) =>
        PassengerData(
          id: id,
          pickupLocation: Vector2(85, pickupY),
          dropoffLocation: Vector2(85, dropoffY),
          reward: 50,
          fareType: type,
        );

    test('a VIP meter runs far tighter than the same standard ride', () {
      for (final distance in [550.0, 700.0, 975.0]) {
        final standard = FareChain.secondsForRide(distance);
        final vip = FareChain.secondsForRide(distance, fareType: FareType.vip);
        final awkward =
            FareChain.secondsForRide(distance, fareType: FareType.awkward);
        final longHaul =
            FareChain.secondsForRide(distance, fareType: FareType.longHaul);

        expect(vip, lessThan(awkward), reason: 'ride $distance');
        expect(awkward, lessThan(standard), reason: 'ride $distance');
        expect(longHaul, standard,
            reason: 'the long-haul clock is the standard clock at ride '
                '$distance — its ride is what is long');
      }
    });

    test('no kind of fare is ever unwinnable at a realistic cruise', () {
      // The winnability bar: every budget must at least cover its ride at
      // ~110 px/s — the documented realistic deep-traffic cruise — at any
      // pressure. The VIP carries no loading allowance at all (that is
      // the gamble), but the road must still be drivable fast enough.
      const cruise = 110.0;
      for (final distance in [550.0, 700.0, 975.0, 1100.0]) {
        for (final pressure in [0.0, 0.5, 1.0]) {
          for (final type in FareType.values) {
            expect(
              FareChain.secondsForRide(distance,
                  pressure: pressure, fareType: type),
              greaterThanOrEqualTo(distance / cruise),
              reason: '${type.name} ride $distance at pressure $pressure',
            );
          }
        }
      }
    });

    test('startFare sizes the meter by the passenger\'s kind', () {
      final chain = FareChain();
      final vip = fareOfType(FareType.vip, 'vip');
      final standard = fareOfType(FareType.standard, 'plain');

      chain.startFare(vip);
      expect(chain.timerFor(vip)!.totalSeconds,
          closeTo(FareChain.secondsForRide(700, fareType: FareType.vip), 1e-9));

      chain.startFare(standard);
      expect(chain.timerFor(standard)!.totalSeconds,
          closeTo(FareChain.secondsForRide(700), 1e-9),
          reason: 'standard fares keep the original budgets');
    });

    test('a delivered long-haul jumps the chain three steps at once', () {
      final chain = FareChain();
      final longHaul = fareOfType(FareType.longHaul, 'long');
      chain.startFare(longHaul);

      expect(chain.completeFare(longHaul, fareValue: 60),
          FareSettlement.onTime);
      expect(chain.multiplier,
          1 + FareChain.multiplierStep + FareType.longHaul.chainStepBonus);
      expect(chain.multiplier, 4);
      expect(chain.bestMultiplier, 4);
    });

    test('a VIP delivery steps the chain like a standard fare', () {
      final chain = FareChain();
      final vip = fareOfType(FareType.vip, 'vip');
      chain.startFare(vip);

      chain.completeFare(vip, fareValue: 150);
      expect(chain.multiplier, 2, reason: 'the VIP is paid in coins');
    });

    test('a late long-haul forfeits the boost with the rest of the chain',
        () {
      final chain = FareChain();
      final longHaul = fareOfType(FareType.longHaul, 'long');
      chain.startFare(longHaul);
      chain.update(FareChain.secondsForRide(700) + 5);

      expect(chain.completeFare(longHaul, fareValue: 60),
          FareSettlement.late);
      expect(chain.multiplier, 1,
          reason: 'missing the window loses the whole boost');
    });
  });

  group('variety on the street', () {
    late GameStateService gameState;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.init();
      gameState = GameStateService(storage);
      await gameState.loadSaveData();
    });

    /// Mounts [game] headlessly so component `onLoad` hooks and collision
    /// callbacks run — the pattern the endless-run tests use.
    Future<TaxiGame> mountGame(TaxiGame game) async {
      game.onGameResize(Vector2(400, 800));
      await game.onLoad();
      // ignore: invalid_use_of_internal_member
      game.mount();
      await game.ready();
      return game;
    }

    TaxiGame endlessGame(int seed) => TaxiGame(
          levelLoader: LevelLoaderService(),
          gameState: gameState,
          endlessSeed: seed,
        )
          ..overlays.addEntry('levelFailed', (_, __) => const SizedBox.shrink())
          ..overlays.addEntry('shiftWrecked', (_, __) => const SizedBox.shrink())
          ..overlays.addEntry('bankOrPush', (_, __) => const SizedBox.shrink())
          ..overlays.addEntry('shiftBanked', (_, __) => const SizedBox.shrink());

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

    test('the course\'s kinds reach the street, labelled', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      final fare = game.course!.fare(0);
      final pickupZones =
          game.world.children.whereType<PickupZone>().toList();
      expect(pickupZones, hasLength(1));
      expect(pickupZones.single.passenger.fareType, fare.fareType,
          reason: 'the spawned passenger wears the course\'s kind');

      final dropoffZones =
          game.world.children.whereType<DropoffZone>().toList();
      expect(dropoffZones, hasLength(1));

      // Special fares name themselves under both markers; standard fares
      // stay unlabelled.
      if (fare.fareType.isStandard) {
        expect(pickupZones.single.children.whereType<TextComponent>(),
            isEmpty);
        expect(dropoffZones.single.children.whereType<TextComponent>(),
            isEmpty);
      } else {
        final label = pickupZones.single.children.whereType<TextComponent>();
        expect(label, hasLength(1), reason: 'pickup carries the kind label');
        expect(label.single.text, fare.fareType.zoneLabel);
        expect(
          dropoffZones.single.children.whereType<TextComponent>(),
          hasLength(1),
          reason: 'dropoff carries the kind label too',
        );
      }
    });

    test('a waiting fare can be declined off the street', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);
      final coinsBefore = gameState.totalCoins;

      final offer = game.currentFareOffer;
      expect(offer, isNotNull,
          reason: 'the first fare waits on screen at the start line');
      expect(game.fareController!.offerOnScreen, same(offer));

      // Decline it: the offer comes off the street, unpaid and unpenalised.
      expect(game.declineCurrentOffer(), isTrue);

      expect(game.fareController!.faresDeclined, 1);
      expect(game.fareController!.faresMissed, 0,
          reason: 'a decline is a decision, not a miss');
      expect(gameState.totalCoins, coinsBefore, reason: 'nothing was paid');
      expect(game.fareChain.isCarryingFare, isFalse,
          reason: 'no meter ever started');
      expect(game.player.hasPassenger, isFalse);
      expect(game.currentFareOffer, isNull,
          reason: 'fare 1 is far above the offer window');

      // Let the removals flush, then confirm the zones are really gone.
      game.update(1 / 60);
      await drain();
      final ids = game.world.children
          .whereType<PickupZone>()
          .map((z) => z.passenger.id)
          .toSet();
      expect(ids, isNot(contains(offer!.id)));
    });

    test('a fare already aboard cannot be declined', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      final offer = game.currentFareOffer!;
      final fare = game.course!.fare(0);
      game.player.position = Vector2(fare.pickup.x, fare.pickup.y + 30);
      game.update(1 / 60);
      expect(game.player.hasPassenger, isTrue, reason: 'passenger boarded');

      // The same passenger, now aboard, is no longer offerable: the
      // guard refuses, and the game reports nothing to decline — the
      // next fare is far above the offer window.
      expect(game.fareController!.declineOffer(offer), isFalse);
      expect(game.fareController!.faresDeclined, 0);
      expect(game.currentFareOffer, isNull);
      expect(game.declineCurrentOffer(), isFalse);
    });

    test('declining keeps counting decisions apart from misses', () async {
      final game = await mountGame(endlessGame(42));
      await tickAndSettle(game);

      expect(game.declineCurrentOffer(), isTrue);
      expect(game.fareController!.faresDeclined, 1);
      expect(game.fareController!.faresMissed, 0);

      // Driving past the *next* fare still counts as a miss, not a
      // decline — the two ledgers stay honest.
      game.player.position = Vector2(200, game.course!.fare(1).pickup.y);
      await tickAndSettle(game);
      game.player.position = Vector2(200, game.course!.fare(1).pickup.y - 4000);
      await tickAndSettle(game);
      game.update(1 / 60);
      await drain();

      expect(game.fareController!.faresDeclined, 1,
          reason: 'driving past is not declining');
      expect(game.fareController!.faresMissed, greaterThanOrEqualTo(1));
    });

    test('the tutorial ladder stays all-standard', () async {
      final game = await mountGame(TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      ));

      // Level mode has no offer to decline: a level's pickups are
      // mandatory objectives, so there is no decision to offer.
      expect(game.isEndless, isFalse);
      expect(game.currentFareOffer, isNull);
      expect(game.declineCurrentOffer(), isFalse);

      // And every fare the ladder builds is the everyday ride.
      expect(game.passengers, isNotEmpty);
      for (final passenger in game.passengers) {
        expect(passenger.fareType, FareType.standard,
            reason: '${passenger.id} is a tutorial fare');
      }
    });

    testWidgets('the offer bar names the fare and skips it on tap',
        (tester) async {
      late TaxiGame game;
      // Mounting and the first settle tick run in the real async zone —
      // drain()'s zero-duration futures never complete in the tester's
      // fake-async zone without a pump.
      await tester.runAsync(() async {
        game = await mountGame(endlessGame(42));
        await tickAndSettle(game);
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<GameStateService>.value(
          value: gameState,
          child: MaterialApp(
            home: Scaffold(body: HudOverlay(game: game)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      // The offer bar shows the waiting fare's pitch and the decline.
      final offer = game.currentFareOffer!;
      expect(find.text(offer.fareType.offerBlurb(offer.reward)),
          findsOneWidget);
      expect(find.byKey(const ValueKey('decline_fare_button')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('decline_fare_button')));
      await tester.pump(const Duration(milliseconds: 150));

      // The bar is gone with the fare, and the fare really was declined.
      expect(find.byKey(const ValueKey('decline_fare_button')), findsNothing);
      expect(game.fareController!.faresDeclined, 1);
      expect(game.currentFareOffer, isNull);
    });

    testWidgets('level mode shows no offer bar', (tester) async {
      final game = TaxiGame(
        levelLoader: LevelLoaderService(),
        gameState: gameState,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<GameStateService>.value(
          value: gameState,
          child: MaterialApp(
            home: Scaffold(body: HudOverlay(game: game)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byKey(const ValueKey('decline_fare_button')), findsNothing,
          reason: 'a level\'s pickups are mandatory — nothing to decline');
    });
  });
}
