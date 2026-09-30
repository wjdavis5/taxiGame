import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:taxi_game/game/components/traffic_spawner.dart';
import 'package:taxi_game/game/components/traffic_vehicle.dart';
import 'package:taxi_game/game/systems/difficulty_curve.dart';
import 'package:taxi_game/game/systems/run_environment.dart';
import 'package:taxi_game/game/taxi_game.dart';
import 'package:taxi_game/models/traffic_pattern.dart';
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// Traffic and the road's width changes (issue #87).
///
/// Endless traffic takes its lane x from the road under the taxi but
/// materialises 500 px ahead, and its straight path never re-reads the
/// road — so wherever an avenue narrowed, cars appeared over the kerb and
/// drove the sidewalk for their whole life. The fix is two-sided: the lane
/// is re-laid on the road that exists at the *spawn* distance (fractions
/// survive a width change; px do not), and a spawn is skipped outright
/// when its widest-body footprint leaves the road anywhere over the span
/// its waypoints cover. These tests cover the containment helper exactly,
/// the fraction re-lay, and — flood-spawning at a real avenue→narrow
/// boundary — the live invariant that no car ever sits on the sidewalk.
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

  /// Mounts [game] headlessly (the pattern flame_test uses, plus the
  /// internal mount GameWidget performs) so component `onLoad` hooks run.
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

  /// One tick plus the mounts it queued, then a second tick so the queue
  /// is applied.
  Future<void> tickAndSettle(TaxiGame game) async {
    game.update(1 / 60);
    await drain();
    game.update(1 / 60);
    await drain();
  }

  /// First distance where an avenue segment gives way to a narrow one —
  /// the defect's native habitat. Seed 7 draws it at 28 000 px and seed 2
  /// at 52 000 px (verified this session); the scan keeps the tests honest
  /// should the profile rolls ever change.
  double? firstAvenueToNarrow(RunEnvironment env) {
    for (var k = 2; k < 60; k++) {
      if (env.profileForSegment(k - 1) == RoadProfile.avenue &&
          env.profileForSegment(k) == RoadProfile.narrow) {
        return k * RunEnvironment.geometrySegmentLength;
      }
    }
    return null;
  }

  /// The reference implementation of containment: sample the road finely
  /// over the whole span. The production helper must agree with this
  /// verdict exactly while doing far less work.
  bool bruteHolds(
    RunEnvironment env,
    double from,
    double to,
    double laneX,
    double halfWidth, {
    double step = 5,
  }) {
    final a = math.max(0.0, from);
    final b = math.max(a, to);
    for (var d = a; d <= b; d += step) {
      final road = env.roadAt(d);
      if (laneX - halfWidth < road.leftX || laneX + halfWidth > road.rightX) {
        return false;
      }
    }
    final end = env.roadAt(b);
    return laneX - halfWidth >= end.leftX && laneX + halfWidth <= end.rightX;
  }

  group('laneHoldsOnRoad (issue #87)', () {
    test('an avenue lane cannot cross into a narrow street, a native one can',
        () {
      final env = RunEnvironment(seed: 7);
      final boundary = firstAvenueToNarrow(env)!;
      expect(boundary, 28000, reason: 'seed 7 avenue→narrow at 28 000 px');

      final avenueRightLane = env.roadAt(boundary - 100).laneXs.last;
      expect(avenueRightLane, closeTo(288, 0.01));
      final narrowRightLane = env.roadAt(boundary + 1000).laneXs.last;
      expect(narrowRightLane, closeTo(237, 0.01));

      final busHalf = RunEnvironment.widestTrafficHalfWidth; // 25 px
      expect(busHalf, 25.0, reason: 'the bus is the widest body');

      // The avenue's right lane over a span crossing the boundary and
      // through the whole taper: its 5/6 fraction re-laid on the narrow
      // width overhangs the kerb — exactly the sidewalk car the issue
      // describes. (A span that stops only 100 px in still fits — the
      // taper needs ~230 px before a bus at the avenue's kerb lane
      // loses the road — which is the point of checking the full span.)
      expect(
        env.laneHoldsOnRoad(
            boundary - 100, boundary + 600, avenueRightLane, busHalf),
        isFalse,
        reason: 'an avenue lane x does not fit the narrow street',
      );

      // The narrow street's own lanes fit their own street, bus and all.
      expect(
        env.laneHoldsOnRoad(
            boundary - 100, boundary + 600, narrowRightLane, busHalf),
        isTrue,
      );

      // Inside the avenue alone the avenue lanes are fine.
      expect(
        env.laneHoldsOnRoad(
            boundary - 1000, boundary - 100, avenueRightLane, busHalf),
        isTrue,
      );
    });

    test('agrees exactly with fine sampling around the taper', () {
      final env = RunEnvironment(seed: 2);
      final boundary = firstAvenueToNarrow(env)!;
      expect(boundary, 52000, reason: 'seed 2 avenue→narrow at 52 000 px');

      // Lanes of both profiles plus a few arbitrary bands — the helper's
      // endpoint logic has to rule the same as walking the span at 5 px.
      final lanes = [
        ...env.roadAt(boundary - 100).laneXs,
        ...env.roadAt(boundary + 1000).laneXs,
        150.0,
        200.0,
        260.0,
      ];
      const spans = [
        (-2000.0, -1.0), // entirely behind the start line
        (-1500.0, 500.0), // clamped at zero, crossing no boundary
        (48000.0, 51500.0), // pure avenue
        (51800.0, 51950.0), // approach, span ends inside the taper
        (51900.0, 55000.0), // across the boundary, deep into the narrow
        (51900.0, 60000.0), // across two boundaries
      ];
      for (final (from, to) in spans) {
        for (final lane in lanes) {
          for (final halfWidth in [10.0, 20.0, 25.0]) {
            expect(
              env.laneHoldsOnRoad(from, to, lane, halfWidth),
              bruteHolds(env, from, to, lane, halfWidth),
              reason: 'from $from to $to lane $lane half $halfWidth',
            );
          }
        }
      }
    });

    test('the containment span matches the spawner waypoint steps', () {
      // Oncoming paths run three 500 px steps down-screen; same-direction
      // paths one 3000 px step up. Each end is padded by half the longest
      // body (the bus, 50 px) so a vehicle centred at either end is fully
      // on the road — the same clearance the level end keeps.
      expect(RunEnvironment.longestTrafficHalfLength, 50.0);
      final oncoming = RunEnvironment.trafficPathSpan(10000, oncoming: true);
      expect(oncoming.$1, 10000 - 1500 - 50);
      expect(oncoming.$2, 10000 + 50);
      final same = RunEnvironment.trafficPathSpan(10000, oncoming: false);
      expect(same.$1, 10000 - 50);
      expect(same.$2, 10000 + 3000 + 50);
    });
  });

  group('the lane re-lay (issue #87)', () {
    test('fractions survive the width change; px do not', () {
      final env = RunEnvironment(seed: 7);
      final boundary = firstAvenueToNarrow(env)!;

      // The taxi sits in the last avenue stretch; its rightmost lane.
      final taxiRoad = env.roadAt(boundary - 100);
      final laneX = taxiRoad.laneXs.last;
      final fraction = taxiRoad.fractionOf(laneX);
      expect(fraction, closeTo(5 / 6, 0.001),
          reason: 'the avenue layout is [1/6, 3/6, 5/6]');

      // Round-trip on one road is exact.
      expect(taxiRoad.xAtFraction(fraction), closeTo(laneX, 1e-9));

      // Re-laid 500 px past the boundary the lane keeps its fraction of a
      // narrower road — and the fraction is what fits, where the raw px
      // (288 + a bus half-width) already hangs over the tapering kerb.
      final spawnRoad = env.roadAt(boundary + 400);
      final relaid = spawnRoad.xAtFraction(fraction);
      expect(relaid, lessThan(laneX));
      expect(relaid - RunEnvironment.widestTrafficHalfWidth,
          greaterThanOrEqualTo(spawnRoad.leftX - 0.001));
      expect(laneX + RunEnvironment.widestTrafficHalfWidth,
          greaterThan(spawnRoad.rightX),
          reason: 'the old px would have put a bus over the kerb');
    });

    test('the re-laid lane keeps the taxi-road fractions, not just any x',
        () {
      // The fraction the spawner recovers is a *lane* fraction of the
      // profile the taxi's road carries — so a car re-laid on a narrower
      // street still sits on its lane's line, one of that profile's
      // fractions, never between lanes.
      final env = RunEnvironment(seed: 2);
      final boundary = firstAvenueToNarrow(env)!;
      final taxiRoad = env.roadAt(boundary - 100);
      for (final laneX in taxiRoad.laneXs) {
        final f = taxiRoad.fractionOf(laneX);
        expect(
          taxiRoad.profile.laneFractions.any((p) => (p - f).abs() < 0.001),
          isTrue,
          reason: 'lane $laneX resolves to a profile fraction',
        );
        // And the same fraction of a different width stays inside that
        // road's extents (containment beyond that is the skip's call).
        final narrow = env.roadAt(boundary + 700);
        final x = narrow.xAtFraction(f);
        expect(x, greaterThanOrEqualTo(narrow.leftX));
        expect(x, lessThanOrEqualTo(narrow.rightX));
      }
    });
  });

  group('a flood at an avenue→narrow boundary (issue #87)', () {
    // The simulated window is long (30 s of frames plus hundreds of
    // drains); a loaded CI runner can outlast dart's default 30 s budget —
    // the same reason the level-end flood tests raised theirs.
    test('no car ever drives on the sidewalk', () async {
      final game = await mountGame(endlessGame(7));
      final env = game.environment!;
      final boundary = firstAvenueToNarrow(env)!;
      expect(boundary, 28000);

      // Flood probability on the real profile: every wave rolls a spawn
      // in every lane, so the 30 s window is the densest traffic this
      // boundary can see. The interval is the only knob touched — lane
      // xs and speeds still come from trafficAt, exactly what the live
      // spawner consumes.
      game.trafficSpawner.clear();
      final flood = TrafficSpawner.distanceBased(
        profileOf: (d) {
          final base = env.trafficAt(d);
          return TrafficProfile(
            spawnInterval: 0.3,
            lanes: [
              for (final lane in base.lanes)
                TrafficLaneConfig(
                  laneX: lane.laneX,
                  speedRange: lane.speedRange,
                  spawnProbability: 1.0,
                  oncoming: lane.oncoming,
                ),
            ],
          );
        },
        distanceOf: () => game.runDistance,
        random: math.Random(4242),
      );
      game.trafficSpawner = flood;
      game.world.add(flood);
      await drain();

      // Park the taxi 450 px below the boundary: still on the avenue, so
      // the lanes under it are the avenue's, while every spawn lands
      // 500 px ahead — 50 px into the narrowing taper. This is the exact
      // geometry of the bug; the re-lay has to move the lanes onto the
      // road that exists there, and the skip has to turn away the
      // same-direction kerb lanes whose 3000 px paths cross the full
      // narrowing (probed at this seed: oncoming lanes at the 1/6 and
      // 5/6 lines hold, their spans never reaching the taper's end;
      // every same-direction lane but the centre line is skipped).
      game.player.position = Vector2(TaxiGame.roadCenterX, -(boundary - 450));
      await tickAndSettle(game);
      final taxiDistance = game.runDistance;
      expect(taxiDistance, closeTo(boundary - 450, 1));
      final taxiFractions =
          env.roadAt(taxiDistance).profile.laneFractions;

      var vehiclesSeen = 0;
      final laneFractionsSeen = <double>{};

      /// The whole invariant, per car: its body (full sprite width, the
      /// thing a player sees over the kerb) stays inside roadAt at every
      /// distance its path covers, its own half-length beyond each end
      /// waypoint included. 25 px sampling — finer than any taper moves.
      void expectOnRoad(TrafficVehicle v) {
        final shift = game.worldShift;
        var minDistance = double.infinity;
        var maxDistance = double.negativeInfinity;
        for (final waypoint in v.path) {
          final d = shift - waypoint.y;
          minDistance = math.min(minDistance, d);
          maxDistance = math.max(maxDistance, d);
        }
        final halfLength = v.vehicleSize.y / 2;
        final halfWidth = v.vehicleSize.x / 2;
        final from = minDistance - halfLength;
        final to = maxDistance + halfLength;
        for (var d = from; d <= to; d += 25) {
          final road = env.roadAt(d);
          expect(v.position.x - halfWidth,
              greaterThanOrEqualTo(road.leftX - 0.5),
              reason: 'vehicle at x ${v.position.x.toStringAsFixed(1)} '
                  '(${v.vehicleType.name}) leaves the road at distance '
                  '${d.toStringAsFixed(0)}');
          expect(v.position.x + halfWidth, lessThanOrEqualTo(road.rightX + 0.5),
              reason: 'vehicle at x ${v.position.x.toStringAsFixed(1)} '
                  '(${v.vehicleType.name}) leaves the road at distance '
                  '${d.toStringAsFixed(0)}');
        }

        // And the lane it actually took is one of the profile's lanes —
        // re-laid by fraction onto the road at its own spawn distance,
        // never an avenue x pasted onto a narrow street.
        final spawnDistance = shift - v.path.first.y;
        final f = env.roadAt(spawnDistance).fractionOf(v.position.x);
        laneFractionsSeen.add(f);
        expect(
          taxiFractions.any((p) => (p - f).abs() < 0.001),
          isTrue,
          reason: 'x ${v.position.x.toStringAsFixed(1)} at spawn distance '
              '${spawnDistance.toStringAsFixed(0)} is not on a lane of the '
              'taxi-road profile $taxiFractions',
        );
      }

      for (var i = 0; i < 1800; i++) {
        game.update(1 / 60);
        if (i % 6 == 5) await drain();
        if (i % 30 == 29) {
          final vehicles =
              game.world.children.whereType<TrafficVehicle>().toList();
          vehiclesSeen = math.max(vehiclesSeen, vehicles.length);
          for (final v in vehicles) {
            expectOnRoad(v);
          }
        }
      }

      // The window was not vacuous: the flood kept cars on the street
      // through the whole 30 s, on more than one lane line.
      expect(vehiclesSeen, greaterThan(3),
          reason: 'the flood must have spawned traffic for the invariant '
              'to mean anything');
      expect(laneFractionsSeen.length, greaterThan(1),
          reason: 'both surviving lane lines carried traffic (the kerb '
              'lanes cannot fit a bus on the narrow width — their spawns '
              'are the ones the skip turns away)');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
