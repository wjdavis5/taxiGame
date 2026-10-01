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

/// Traffic and the road's width and lane-count changes (issues #87,
/// #95, #107).
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
/// waypoints cover. #107 closed the remaining gap — the fixes covered
/// where cars spawn, not where they drive: a car born on the avenue's
/// middle lane still drove that fixed x onto the two-lane street's
/// centre divider past the taper, because the kerbs-only gate waved x
/// 200 through every road in the game. Now the path is a merge
/// schedule: the spawn lane held, and across each taper a merge onto
/// the nearest same-role lane centre of the road past it. These tests
/// cover the containment helper exactly, the spawn-road lane set, the
/// merge schedule's own invariant — every point outside a taper on a
/// lane centre of the road at that distance — and, flood-spawning at
/// real boundaries, the live invariants that no car ever sits on the
/// sidewalk or between lanes.
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

  /// The issue's invariant, walked finely over a pure merge schedule:
  /// the body (of [halfWidth] — the walker judges the schedule for the
  /// bodies the gate accepts it for) stays on the road over the whole
  /// padded span, and outside a taper every point *of the path itself*
  /// sits on a lane centre of the road at that distance (issue #107).
  /// The lane-centre claim is scoped to the schedule's own span: the
  /// body pads past the ends are overhang, not driving, and a car born
  /// inside a taper carries its blended-lane x a hair off the settled
  /// road behind it — the gate's behind-the-spawn check judges that
  /// sliver's containment instead.
  void expectScheduleHoldsInvariant(
    RunEnvironment env,
    List<(double, double)> waypoints, {
    required bool oncoming,
    double halfWidth = 25,
  }) {
    final (paddedFrom, paddedTo) = RunEnvironment.trafficPathSpan(
        waypoints.first.$1, oncoming: oncoming);
    final lo = math.min(waypoints.first.$1, waypoints.last.$1);
    final hi = math.max(waypoints.first.$1, waypoints.last.$1);
    for (var d = paddedFrom; d <= paddedTo; d += 5) {
      final road = env.roadAt(d);
      final x = xAtDistance(waypoints, d);
      expect(x - halfWidth, greaterThanOrEqualTo(road.leftX - 0.5),
          reason: 'the body leaves the road at distance '
              '${d.toStringAsFixed(0)} (x ${x.toStringAsFixed(1)})');
      expect(x + halfWidth, lessThanOrEqualTo(road.rightX + 0.5),
          reason: 'the body leaves the road at distance '
              '${d.toStringAsFixed(0)} (x ${x.toStringAsFixed(1)})');
      if (!insideTaper(d) && d >= lo && d <= hi) {
        expect(
          road.laneXs.any((lane) => (lane - x).abs() < 0.001),
          isTrue,
          reason: 'x ${x.toStringAsFixed(1)} at distance '
              '${d.toStringAsFixed(0)} is not on a lane of the road there '
              '(lanes ${road.laneXs}) — between lanes, or on the divider',
        );
      }
    }
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

  group('the merge schedule (issue #107)', () {
    test('an avenue middle-lane car merges off the two-lane divider', () {
      // The issue's exact defect: #95 hands the spawner the spawn road's
      // own lanes, but the car born on the avenue's middle lane (x 200)
      // then drives that fixed x through the narrowing — straight onto
      // the two-lane street's centre divider, which the kerbs-only gate
      // waves through because x 200 with any body fits every kerb in
      // the game. The schedule must hold the lane to the taper, then
      // merge onto the road past it.
      final env = RunEnvironment(seed: 7);
      final boundary = firstAvenueToNarrow(env)!;
      final spawn = boundary - 300;
      final laneX = env.roadAt(spawn).laneXs[1];
      expect(laneX, closeTo(200, 0.01),
          reason: 'precondition: the avenue middle lane sits at x 200');

      final waypoints =
          env.trafficMergeWaypoints(spawn, laneX, oncoming: false);
      final taperEnd = boundary + RunEnvironment.taperLength;
      final narrowSame = env.roadAt(taperEnd).sameDirectionLaneX;
      expect(narrowSame, closeTo(237, 0.01));

      // The spawn lane held to the boundary, the far lane reached
      // exactly at the taper's end, and the extent unchanged from the
      // straight paths (3000 px up-screen).
      expect(waypoints.first, (spawn, laneX));
      expect(waypoints, contains((boundary, laneX)));
      expect(waypoints, contains((taperEnd, narrowSame)));
      expect(waypoints.last.$1, closeTo(spawn + 3000, 1e-9));

      // And the defect itself: past the taper, no point of the path
      // sits at x 200 — the divider is gone from the car's life.
      for (var d = taperEnd; d <= spawn + 3000; d += 5) {
        expect((xAtDistance(waypoints, d) - 200).abs(), greaterThan(1),
            reason: 'a car past the avenue\'s end rode the two-lane '
                'divider at distance ${d.toStringAsFixed(0)}');
      }
    });

    test('an avenue kerb-lane bus survives a narrowing by merging', () {
      // The rescue the merge buys: x 288 with a bus's 25 px half-width
      // overhangs the narrow kerb past the taper, so the fixed-x gate
      // had to turn the spawn away — the merge carries it through
      // instead, on the narrow road's own lane. The gate is not looser;
      // the path is better.
      final env = RunEnvironment(seed: 7);
      final boundary = firstAvenueToNarrow(env)!;
      final spawn = boundary - 200;
      final kerbLaneX = env.roadAt(spawn).laneXs.last;
      expect(kerbLaneX, closeTo(288, 0.01));

      final waypoints =
          env.trafficMergeWaypoints(spawn, kerbLaneX, oncoming: false);
      expect(env.mergePathHoldsOnRoad(waypoints, 25, oncoming: false), isTrue,
          reason: 'the merge carries the widest body through the '
              'narrowing');

      // The old question — does x 288 fit the whole span — still
      // answers no, and a fixed-x path shape still fails the per-leg
      // gate: the gate guards, the schedule rescues.
      final (spanFrom, spanTo) =
          RunEnvironment.trafficPathSpan(spawn, oncoming: false);
      expect(env.laneHoldsOnRoad(spanFrom, spanTo, kerbLaneX, 25), isFalse,
          reason: 'precondition: the fixed-x path the old gate judged '
              'genuinely does not fit');
      expect(
        env.mergePathHoldsOnRoad(
          [(spawn, kerbLaneX), (spawn + 3000, kerbLaneX)],
          25,
          oncoming: false,
        ),
        isFalse,
        reason: 'a constant-x leg that overhangs is still turned away',
      );
    });

    test('the oncoming narrow→avenue face merges down onto the avenue', () {
      // The other driving direction over the #87 boundary: same
      // avenue→narrow taper (the avenue below, the narrow above), an
      // oncoming car born on the narrow street's left lane (x 163)
      // above it. Driving down it must land on the avenue's own
      // oncoming lane (112) by the boundary — its fixed x is not even
      // contained down there (163 − 25 < the avenue's left kerb? no:
      // the narrow's lane overhangs nothing on the wider avenue, but it
      // sits between the avenue's 1/6 and 3/6 lanes, off every lane
      // centre for the whole lower street).
      final env = RunEnvironment(seed: 7);
      final boundary = firstAvenueToNarrow(env)!;
      final spawn = boundary + 700; // settled narrow road above the taper
      final laneX = env.roadAt(spawn).oncomingLaneX;
      expect(laneX, closeTo(163, 0.01));
      expect(env.roadAt(spawn).profile, RoadProfile.narrow,
          reason: 'precondition: the car is born on the narrow street');

      final waypoints =
          env.trafficMergeWaypoints(spawn, laneX, oncoming: true);
      final avenueOncoming = env.roadAt(boundary - 1).oncomingLaneX;
      expect(avenueOncoming, closeTo(112, 0.01));

      // Held to the taper's near edge (its top, for a downward drive),
      // on the avenue's lane at the boundary itself, extent 1500 px
      // down-screen.
      expect(waypoints.first, (spawn, laneX));
      expect(
          waypoints, contains((boundary + RunEnvironment.taperLength, laneX)));
      expect(waypoints, contains((boundary, avenueOncoming)));
      expect(waypoints.last.$1, closeTo(spawn - 1500, 1e-9));
      expectScheduleHoldsInvariant(env, waypoints, oncoming: true);
    });

    test('every boundary face, both directions, holds the invariant', () {
      // The structural sweep: for every geometry change the seed draws,
      // every spawn offset around it (settled approach, taper interior,
      // either side), and every lane of the spawn road, the schedule
      // keeps the widest body on the road everywhere and sits on a lane
      // centre of the local road at every off-taper point — and the
      // per-leg gate agrees every such path fits.
      for (final seed in [2, 7, 11]) {
        final env = RunEnvironment(seed: seed);
        final boundaries = <double>[];
        for (var k = 2; k < 40; k++) {
          if (env.profileForSegment(k) != env.profileForSegment(k - 1)) {
            boundaries.add(k * RunEnvironment.geometrySegmentLength);
          }
        }
        expect(boundaries, isNotEmpty,
            reason: 'seed $seed draws some geometry variety');
        for (final boundary in boundaries) {
          for (final offset in [
            -2600.0, -1400.0, -650.0, -300.0, -40.0, 0.0,
            40.0, 300.0, 650.0, 1400.0, 2600.0,
          ]) {
            final spawn = boundary + offset;
            final road = env.roadAt(spawn);
            for (var i = 0; i < road.laneCount; i++) {
              final oncoming = road.isLaneOncoming(i);
              final waypoints = env.trafficMergeWaypoints(
                spawn,
                road.laneXs[i],
                oncoming: oncoming,
              );
              // Driving order: anchors strictly monotone in the driving
              // direction, starting at the spawn and ending at the
              // classic extent.
              final extent = oncoming ? spawn - 1500 : spawn + 3000;
              expect(waypoints.first.$1, closeTo(spawn, 1e-9));
              expect(waypoints.last.$1, closeTo(extent, 1e-9),
                  reason: 'the merge never changes how far a path drives');
              for (var i2 = 1; i2 < waypoints.length; i2++) {
                final step = waypoints[i2].$1 - waypoints[i2 - 1].$1;
                // A zero step is the born-on-the-line sideways snap; a
                // step the wrong way round would mean a car driving
                // backwards along its own path.
                expect(step, oncoming ? lessThanOrEqualTo(0) : greaterThanOrEqualTo(0),
                    reason: 'anchors must advance (or snap sideways) in '
                        'driving order');
                expect(
                    waypoints[i2].$1 == waypoints[i2 - 1].$1 &&
                            (waypoints[i2].$2 - waypoints[i2 - 1].$2).abs() <
                                1e-9,
                    isFalse,
                    reason: 'no duplicate anchors');
              }
              // Per body (every half-width the type table rolls: bus
              // 25, truck 22.5, suv 21, sedan 20, sports 19): whenever
              // the per-leg gate accepts the schedule, the invariant
              // must hold for that body — and something must always be
              // accepted, because the schedule itself is sound and only
              // a genuinely overhanging body (a bus's pad sliver at a
              // taper it was born inside) is ever turned away.
              var anyAccepted = false;
              for (final halfWidth in [25.0, 22.5, 21.0, 20.0, 19.0]) {
                if (!env.mergePathHoldsOnRoad(waypoints, halfWidth,
                    oncoming: oncoming)) {
                  continue;
                }
                anyAccepted = true;
                expectScheduleHoldsInvariant(env, waypoints,
                    oncoming: oncoming, halfWidth: halfWidth);
              }
              expect(anyAccepted, isTrue,
                  reason: 'seed $seed boundary '
                      '${boundary.toStringAsFixed(0)} offset $offset lane '
                      '$i: at least the car-class bodies must fit every '
                      'schedule the helper builds');
            }
          }
        }
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

      // The window was not vacuous, and the traffic that survived lives
      // on the roads' own lanes (issue #107): the same-direction cars —
      // turned away wholesale by the fixed-x gate, whose taper-entry x
      // (≈265) overhangs the narrow kerb over the whole 3 050 px span —
      // now merge across the taper onto the narrow street's own 0.75
      // lane and drive on; the oncoming cars merge down onto the
      // avenue's left lane (1/6) instead of driving the spawn-road x out
      // into the wide. And no sampled car ever sits at a two-lane road's
      // 0.5 — the divider the avenue's middle lane used to ride —
      // because the per-car walk asserts every off-taper path point is
      // a lane centre of the road there.
      expect(vehiclesSeen, greaterThan(3),
          reason: 'the flood must have spawned traffic for the invariant '
              'to mean anything');
      expect(laneFractionsSeen, contains(closeTo(0.75, 0.001)),
          reason: 'same-direction traffic survives past the avenue\'s '
              'end now — it merges onto the narrow road\'s own lane');
      expect(laneFractionsSeen, contains(closeTo(1 / 6, 0.001)),
          reason: 'oncoming traffic merges down onto the avenue\'s own '
              'left lane');
      expect(laneFractionsSeen, isNot(contains(closeTo(0.5, 0.001))),
          reason: 'no car ever took a two-lane road\'s centre line — '
              'the one the avenue\'s middle lane used to ride');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('a flood before a standard→narrow boundary (issue #87)', () {
    // The economy-regression face: the standard lane x (250) overhangs
    // the narrow kerb by exactly one pixel for the bus and fits for
    // every other body — so an approach like this is where "gate every
    // spawn on the widest body" emptied 2.5 km of same-direction
    // traffic the difficulty curve meant to place, lengthened every
    // simulated chain, and flipped the economy instrument's
    // new-below-median ordering. The gate still asks about the body the
    // spawn rolled — but since #107 the bus no longer dies here: it
    // merges onto the narrow road's own lane like everything else, and
    // the per-car walk proves every body that spawns rides through
    // inside the kerbs and on a lane centre past the taper.
    test('the lane carries every body through the narrowing — by merging',
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

      // Not vacuous, and the same-direction lane carried traffic: the
      // 0.75 line is the one the widest-body gate used to empty here,
      // and the fraction reads 0.75 on both roads — the standard's lane
      // at 250 before the taper, the narrow's own at 237 past it, which
      // is the merge. The per-car walk already proved every sampled
      // body — the bus included, whose fixed x 250 overhung the narrow
      // kerb by exactly one pixel — rides inside the kerbs and on a
      // lane centre at every off-taper point of its path.
      expect(vehiclesSeen, greaterThan(3),
          reason: 'the flood must have spawned traffic for the invariant '
              'to mean anything');
      expect(laneFractionsSeen, contains(closeTo(0.75, 0.001)),
          reason: 'the same-direction lane line at fraction 0.75 carried '
              'traffic through the narrowing approach — the widest-body '
              'gate emptied exactly this stretch');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}

/// The whole invariant, per car (issues #95 and #107): its body (full
/// sprite width, the thing a player sees over the kerb) stays inside
/// roadAt at every distance its path covers, its own half-length beyond
/// each end waypoint included — sampled along the waypoint polyline at
/// 25 px, finer than any taper moves. And outside a taper, every point
/// of that polyline sits on a lane centre of the road *right there*:
/// the spawn road's lanes matter only at the spawn, and past a taper
/// the car must be on the new road's lanes — exactly what merging
/// provides and what fixed-x driving (#95's gap, #107's defect) could
/// not. The live position is checked against the same kerbs (a
/// half-pixel for the steering lag between waypoints); the strict
/// lane-centre check runs on the polyline, where it holds exactly.
/// Returns the nearest lane fraction of the road under the car, for the
/// caller's census.
double expectOnRoadAndOnALane(
  TaxiGame game,
  RunEnvironment env,
  TrafficVehicle v,
) {
  final shift = game.worldShift;
  final halfLength = v.vehicleSize.y / 2;
  final halfWidth = v.vehicleSize.x / 2;

  // The live position, against the road it stands on now.
  final nowDistance = shift - v.position.y;
  final nowRoad = env.roadAt(nowDistance);
  expect(v.position.x - halfWidth,
      greaterThanOrEqualTo(nowRoad.leftX - 0.5),
      reason: 'vehicle at x ${v.position.x.toStringAsFixed(1)} '
          '(${v.vehicleType.name}) leaves the road at distance '
          '${nowDistance.toStringAsFixed(0)}');
  expect(v.position.x + halfWidth,
      lessThanOrEqualTo(nowRoad.rightX + 0.5),
      reason: 'vehicle at x ${v.position.x.toStringAsFixed(1)} '
          '(${v.vehicleType.name}) leaves the road at distance '
          '${nowDistance.toStringAsFixed(0)}');

  // The whole path, point by point — the polyline through the spawner's
  // waypoints, whose off-taper legs are exactly the schedule's holds.
  final schedule = <(double, double)>[
    for (final waypoint in v.path) (shift - waypoint.y, waypoint.x),
  ];
  var minDistance = double.infinity;
  var maxDistance = double.negativeInfinity;
  for (final (d, _) in schedule) {
    minDistance = math.min(minDistance, d);
    maxDistance = math.max(maxDistance, d);
  }
  for (var d = minDistance - halfLength; d <= maxDistance + halfLength;
      d += 25) {
    final road = env.roadAt(d);
    final x = xAtDistance(schedule, d);
    expect(x - halfWidth, greaterThanOrEqualTo(road.leftX - 0.5),
        reason: 'the ${v.vehicleType.name}\'s path leaves the road at '
            'distance ${d.toStringAsFixed(0)} (x ${x.toStringAsFixed(1)})');
    expect(x + halfWidth, lessThanOrEqualTo(road.rightX + 0.5),
        reason: 'the ${v.vehicleType.name}\'s path leaves the road at '
            'distance ${d.toStringAsFixed(0)} (x ${x.toStringAsFixed(1)})');
    if (!insideTaper(d)) {
      expect(
        road.laneXs.any((lane) => (lane - x).abs() < 0.001),
        isTrue,
        reason: 'path x ${x.toStringAsFixed(1)} at distance '
            '${d.toStringAsFixed(0)} is not on a lane of the road there '
            '(lanes ${road.laneXs}) — between lanes, or on the divider',
      );
    }
  }

  return nearestLaneFraction(nowRoad, v.position.x);
}

/// Whether [distance] sits inside a road-geometry taper — the stretch
/// where two cross-sections blend and neither road's lane centres are
/// expected to hold. Exactly where #107's merges live.
bool insideTaper(double distance) {
  if (distance <= 0) return false;
  if ((distance / RunEnvironment.geometrySegmentLength).floor() < 1) {
    return false;
  }
  return distance % RunEnvironment.geometrySegmentLength <
      RunEnvironment.taperLength;
}

/// The x a merge schedule holds at [distance] — the same piecewise
/// linear interpolation the run simulator's _SimVehicle performs
/// (issue #107), duplicated here so tests can walk every point of a
/// path without mounting a game.
double xAtDistance(List<(double, double)> waypoints, double distance) {
  // The schedule is monotone in distance (anchors are in driving
  // order, either direction). Outside its span the nearest end's x
  // holds: a body overhangs its path's end without the car driving
  // any further — falling through to the last segment instead would
  // read the overhang past the *start* as the far end's lane.
  final firstD = waypoints.first.$1;
  final lastD = waypoints.last.$1;
  final lo = math.min(firstD, lastD);
  final hi = math.max(firstD, lastD);
  if (distance <= lo || distance >= hi) {
    return (distance - firstD).abs() <= (distance - lastD).abs()
        ? waypoints.first.$2
        : waypoints.last.$2;
  }
  var (d, laneX) = waypoints.first;
  for (var i = 1; i < waypoints.length; i++) {
    final (nextD, nextX) = waypoints[i];
    if ((distance - d) * (distance - nextD) <= 0) {
      final span = nextD - d;
      final t = span.abs() < 1e-9
          ? 0.0
          : ((distance - d) / span).clamp(0.0, 1.0).toDouble();
      return laneX + (nextX - laneX) * t;
    }
    d = nextD;
    laneX = nextX;
  }
  return laneX; // unreachable: a monotone schedule covers (lo, hi)
}

/// The fraction of [road]'s nearest lane centre to [x] — the census
/// bucket for a live car, which can lag its path's polyline by the
/// waypoint capture radius (issue #107).
double nearestLaneFraction(RoadGeometry road, double x) {
  var best = road.laneXs.first;
  for (final lane in road.laneXs) {
    if ((lane - x).abs() < (best - x).abs()) best = lane;
  }
  return road.fractionOf(best);
}
