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
import 'package:taxi_game/services/game_state_service.dart';
import 'package:taxi_game/services/level_loader_service.dart';
import 'package:taxi_game/services/storage_service.dart';

/// Traffic and the road's width and lane-count changes (issues #87, #95).
///
/// Endless traffic materialises 500 px ahead of the taxi on a straight
/// path that never re-reads the road. Two defects came from that: lane
/// px taken from the road under the taxi put cars over the kerb wherever
/// an avenue narrowed (#87), and the fraction re-lay that fixed it put
/// the avenue's middle lane exactly on a two-lane street's centre
/// divider when the lane *count* changed too (#95). The fix is
/// two-sided: the spawner takes its whole lane set — xs, roles, count,
/// per-side split — from the road at the spawn distance (the difficulty
/// core stays at the taxi's distance), and a spawn is skipped outright
/// when the body it rolled leaves the road anywhere over the span its
/// waypoints cover. These tests cover the containment helper exactly,
/// the spawn-road lane set, and — flood-spawning at real
/// avenue→narrow boundaries — the live invariants that no car ever sits
/// on the sidewalk or between lanes.
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

  /// First distance where a standard segment gives way to a narrow one —
  /// the native habitat of the per-body gate's other face: the standard
  /// lane x (250) overhangs the narrow kerb by exactly one pixel for the
  /// bus and for nothing else, so the approach is where gating every
  /// spawn on the widest body empties lanes the rolled bodies fit.
  double? firstStandardToNarrow(RunEnvironment env) {
    for (var k = 2; k < 60; k++) {
      if (env.profileForSegment(k - 1) == RoadProfile.standard &&
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

      // The bus's half width, 25 px — the widest body on the road and
      // the natural probe for the helper; the gate itself asks per
      // rolled body (a sedan's 20 px fits streets the bus cannot).
      const busHalf = 25.0;

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

  group('the lane set follows the spawn road (issues #87 and #95)', () {
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

      // The same fraction of a narrower width is the coordinate that
      // survives a width change — the math issue #87's fix rode. The raw
      // px does not: 288 plus a bus half-width already hangs over the
      // tapering kerb 400 px past the boundary, where the fraction does
      // not. (The spawner no longer carries fractions across a layout
      // change at all — that is #95 below — but the width invariant is
      // what made fractions look safe, and it is only half the truth.)
      final spawnRoad = env.roadAt(boundary + 400);
      final relaid = spawnRoad.xAtFraction(fraction);
      expect(relaid, lessThan(laneX));
      const busHalf = 25.0; // the widest body — the worst case to fit
      expect(relaid - busHalf, greaterThanOrEqualTo(spawnRoad.leftX - 0.001));
      expect(laneX + busHalf, greaterThan(spawnRoad.rightX),
          reason: 'the old px would have put a bus over the kerb');
    });

    test('a two-lane spawn road offers only its own lanes — none on the '
        'divider (issue #95)', () {
      // The defect's arithmetic: the taxi is on an avenue (three lanes,
      // middle fraction 1/2), the road 500+ px ahead is two-lane. The
      // old re-lay mapped the avenue's middle lane to
      // xAtFraction(1/2) — exactly the x where the two-lane road draws
      // its dashed centre divider — and the containment gate (kerbs
      // only) waved it through, so the car straddled the line for its
      // whole fixed-x life. The lane set must instead be the spawn
      // road's own: two lanes, on its own lane xs, never the centre.
      final env = RunEnvironment(seed: 7);
      final boundary = firstAvenueToNarrow(env)!;
      final taxiDistance = boundary - 100;
      expect(env.roadAt(taxiDistance).profile.laneCount, 3,
          reason: 'precondition: the taxi is on the avenue');

      final spawnDistance = boundary + 400; // past the taper's middle
      final spawnRoad = env.roadAt(spawnDistance);
      expect(spawnRoad.profile.laneCount, 2,
          reason: 'precondition: the spawn road carries two lanes');
      final divider = spawnRoad.xAtFraction(0.5);

      final lanes =
          env.trafficAt(taxiDistance, geometryDistance: spawnDistance).lanes;
      expect(lanes, hasLength(2),
          reason: 'the wave rolls the spawn road\'s lane count');
      for (final lane in lanes) {
        expect(
          spawnRoad.laneXs.any((x) => (x - lane.laneX).abs() < 0.001),
          isTrue,
          reason: 'lane x ${lane.laneX.toStringAsFixed(1)} is one of the '
              'spawn road\'s own lane xs ${spawnRoad.laneXs}',
        );
        expect((lane.laneX - divider).abs(), greaterThan(5),
            reason: 'no lane may straddle the centre divider at '
                '${divider.toStringAsFixed(1)}');
      }
      // And the avenue's middle lane — the one the re-lay used to carry
      // onto the divider — is not represented at all.
      expect(
        lanes.any((l) =>
            (spawnRoad.fractionOf(l.laneX) - 0.5).abs() < 0.001),
        isFalse,
        reason: 'a two-lane road has no lane at fraction 1/2',
      );
    });

    test('the difficulty core stays at the taxi\'s distance (issue #95)',
        () {
      // Same spawn road, two different taxi distances: the lane xs,
      // roles, and count come from the geometry road, while the interval
      // and speeds follow the taxi's own distance — pressure is where
      // the player is, lanes are where the cars stand.
      final env = RunEnvironment(seed: 7);
      const geometryDistance = 5000.0; // calm open: always standard
      final early = env.trafficAt(4000, geometryDistance: geometryDistance);
      final late = env.trafficAt(50000, geometryDistance: geometryDistance);

      final geometryRoad = env.roadAt(geometryDistance);
      for (final profile in [early, late]) {
        expect(profile.lanes, hasLength(geometryRoad.laneCount));
        for (final lane in profile.lanes) {
          expect(
            geometryRoad.laneXs.any((x) => (x - lane.laneX).abs() < 0.001),
            isTrue,
            reason: 'lane xs come from the geometry road',
          );
        }
      }
      expect(early.lanes.first.oncoming, late.lanes.first.oncoming,
          reason: 'lane roles come from the geometry road');

      // The core is the plain (no geometry override) profile's own.
      expect(early.spawnInterval,
          env.trafficAt(4000).spawnInterval);
      expect(late.spawnInterval, env.trafficAt(50000).spawnInterval);
      expect(late.spawnInterval, lessThan(early.spawnInterval),
          reason: 'the deep-run pressure still tightens the interval');
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

      // Flood cadence on the real profile: the interval is the only knob
      // that still reaches the spawner's wave loop — the lane list comes
      // straight from the environment at the spawn distance now (issue
      // #95), so a probability injection through profileOf would no
      // longer reach the lanes. Density rides the road's real
      // probabilities at this deep-run distance, plenty for the
      // invariant to bite.
      game.trafficSpawner.clear();
      final flood = TrafficSpawner.distanceBased(
        profileOf: (d) => TrafficProfile(
          spawnInterval: 0.3,
          lanes: env.trafficAt(d).lanes,
        ),
        distanceOf: () => game.runDistance,
        random: math.Random(4242),
      );
      game.trafficSpawner = flood;
      game.world.add(flood);
      await drain();

      // Park the taxi 450 px below the boundary: still on the avenue, so
      // the difficulty core under it is the avenue's, while every spawn
      // lands 500 px ahead — 50 px into the narrowing taper, whose lane
      // layout is already the narrow street's two lanes. This is the
      // exact geometry of the bug: the wave must roll the *spawn* road's
      // lanes (never the avenue's middle lane re-laid onto the divider),
      // and the skip has to turn away whatever body does not fit the
      // narrowing over the span its path covers.
      game.player.position = Vector2(TaxiGame.roadCenterX, -(boundary - 450));
      await tickAndSettle(game);
      final taxiDistance = game.runDistance;
      expect(taxiDistance, closeTo(boundary - 450, 1));
      expect(env.roadAt(taxiDistance).profile.laneCount, 3,
          reason: 'precondition: the taxi is still on the avenue');
      expect(env.roadAt(taxiDistance + 500).profile.laneCount, 2,
          reason: 'precondition: the spawn road is the narrow street');

      var vehiclesSeen = 0;
      final laneFractionsSeen = <double>{};

      for (var i = 0; i < 1800; i++) {
        game.update(1 / 60);
        if (i % 6 == 5) await drain();
        if (i % 30 == 29) {
          final vehicles =
              game.world.children.whereType<TrafficVehicle>().toList();
          vehiclesSeen = math.max(vehiclesSeen, vehicles.length);
          for (final v in vehicles) {
            laneFractionsSeen.add(expectOnRoadAndOnALane(game, env, v));
          }
        }
      }

      // The window was not vacuous, and the traffic that survived sits
      // on the spawn road's own lanes — never the centre line. Only the
      // oncoming lane can carry cars here: its span runs down-screen and
      // never reaches the taper's end, while the same-direction lane's
      // x at the taper's still-wide road (≈265) overhangs the narrow
      // kerb over its 3 050 px path, so the containment gate turns every
      // body on it away — the gate doing exactly its job. (The old
      // probability-1.0 test kept its second lane alive through the bug
      // itself: the avenue middle lane re-laid onto x 200 fit the
      // narrowing precisely because it straddled the centre.)
      expect(vehiclesSeen, greaterThan(3),
          reason: 'the flood must have spawned traffic for the invariant '
              'to mean anything');
      expect(laneFractionsSeen, contains(closeTo(0.25, 0.001)),
          reason: 'the oncoming lane — the one lane whose span holds the '
              'narrowing — carried traffic');
      expect(laneFractionsSeen, isNot(contains(closeTo(0.5, 0.001))),
          reason: 'no car ever took the centre line the old re-lay '
              'landed the avenue\'s middle lane on');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('a flood before a standard→narrow boundary (issue #87)', () {
    // The economy-regression face of the gate: the standard lane x
    // (250) overhangs the narrow kerb by exactly one pixel for the bus
    // and fits for every other body — so an approach like this is where
    // "gate every spawn on the widest body" emptied 2.5 km of
    // same-direction traffic the difficulty curve meant to place,
    // lengthened every simulated chain, and flipped the economy
    // instrument's new-below-median ordering. The gate must ask about
    // the body the spawn rolled, not the worst body on the road.
    test('the lane carries every body that fits — only the bus is turned away',
        () async {
      // A clean window: the first standard→narrow boundary whose spawn
      // point (1.5 km short of it, the taxi parked 2 km short) sits on
      // no cross street and inside no cone line. The scan is
      // deterministic, so the seed it lands on is stable.
      int? seed;
      double? boundary;
      RunEnvironment? scanned;
      for (var s = 1; s <= 60; s++) {
        final env = RunEnvironment(seed: s);
        final b = firstStandardToNarrow(env);
        if (b == null) continue;
        final laneX = env.roadAt(b - 1500).xAtFraction(0.75);
        if (env.isIntersectionAt(b - 1500)) continue;
        if (env.isLaneBlockedAt(b - 1500, laneX)) continue;
        seed = s;
        boundary = b;
        scanned = env;
        break;
      }
      expect(boundary, isNotNull,
          reason: 'some seed in 1..60 draws a clean standard→narrow '
              'approach');
      final env = scanned!;

      final game = await mountGame(endlessGame(seed!));
      expect(game.environment!.seed, env.seed);

      game.trafficSpawner.clear();
      final flood = TrafficSpawner.distanceBased(
        profileOf: (d) => TrafficProfile(
          spawnInterval: 0.3,
          lanes: env.trafficAt(d).lanes,
        ),
        distanceOf: () => game.runDistance,
        random: math.Random(90210),
      );
      game.trafficSpawner = flood;
      game.world.add(flood);
      await drain();

      // Park the taxi 2 000 px below the boundary, dead centre of the
      // standard road (x 200 — between the lanes at 150/250, so no
      // parked body ever touches the flood). Every spawn lands 1 500 px
      // short of the taper: flat standard road, lane x 250, whose
      // 3 050 px same-direction span crosses the whole narrowing. Under
      // the widest-body gate not one car would appear in this lane for
      // the entire window; under the per-body gate everything but the
      // bus spawns here — and drives through the narrowing on screen.
      game.player.position = Vector2(TaxiGame.roadCenterX, -(boundary! - 2000));
      await tickAndSettle(game);
      final taxiDistance = game.runDistance;
      expect(taxiDistance, closeTo(boundary - 2000, 1));

      var vehiclesSeen = 0;
      final laneFractionsSeen = <double>{};
      final typesOnTheKerbLine = <String>{};

      for (var i = 0; i < 1800; i++) {
        game.update(1 / 60);
        if (i % 6 == 5) await drain();
        if (i % 30 == 29) {
          final vehicles =
              game.world.children.whereType<TrafficVehicle>().toList();
          vehiclesSeen = math.max(vehiclesSeen, vehicles.length);
          for (final v in vehicles) {
            final f = expectOnRoadAndOnALane(game, env, v);
            laneFractionsSeen.add(f);
            if ((f - 0.75).abs() < 0.001) {
              typesOnTheKerbLine.add(v.vehicleType.name);
            }
          }
        }
      }

      // Not vacuous, and the same-direction lane carried traffic: the
      // 0.75 line is the one the widest-body gate used to empty here.
      expect(vehiclesSeen, greaterThan(3),
          reason: 'the flood must have spawned traffic for the invariant '
              'to mean anything');
      expect(laneFractionsSeen, contains(closeTo(0.75, 0.001)),
          reason: 'the same-direction lane line at fraction 0.75 carried '
              'traffic through the narrowing approach — the widest-body '
              'gate emptied exactly this stretch');
      // And the bus never appeared on it: its 25 px half-width is the
      // one body that overhangs the narrow kerb (275 > 274).
      expect(typesOnTheKerbLine, isNot(contains('bus')),
          reason: 'a bus at x 250 overhangs the narrow kerb by 1 px — '
              'the gate must still turn it away');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

/// The whole invariant, per car: its body (full sprite width, the thing
/// a player sees over the kerb) stays inside roadAt at every distance
/// its path covers, its own half-length beyond each end waypoint
/// included. 25 px sampling — finer than any taper moves. Returns the
/// lane fraction the car took on its own spawn road, for the caller's
/// lane-line census, and asserts the car's x is one of that road's lane
/// xs — never an avenue x pasted onto a narrow street, and never the
/// centre divider between a two-lane road's lanes (issue #95).
double expectOnRoadAndOnALane(
  TaxiGame game,
  RunEnvironment env,
  TrafficVehicle v,
) {
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

  final spawnDistance = shift - v.path.first.y;
  final spawnRoad = env.roadAt(spawnDistance);
  final f = spawnRoad.fractionOf(v.position.x);
  expect(
    spawnRoad.laneXs.any((x) => (x - v.position.x).abs() < 0.001),
    isTrue,
    reason: 'x ${v.position.x.toStringAsFixed(1)} at spawn distance '
        '${spawnDistance.toStringAsFixed(0)} is not on a lane of the '
        'spawn road (lanes ${spawnRoad.laneXs}) — between lanes, or on '
        'the divider',
  );
  return f;
}
