import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/daily_shift.dart';
import 'package:taxi_game/game/systems/difficulty_curve.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/ghost_replay.dart';
import 'package:taxi_game/game/systems/run_environment.dart';
import 'package:taxi_game/models/fare_type.dart';
import 'package:taxi_game/models/ghost_trace.dart';

/// Golden seeds (issue #287): the course, the environment, the fare draw,
/// and the ghost trace are contracts with history — a stored ghost replays
/// its day's course, and the Daily Shift must deal the same city on every
/// device. The tests below freeze exact outputs at one golden seed, so any
/// change to a generator's draws, their order, or their arithmetic fails
/// loudly instead of silently rewriting history.
///
/// A deliberate generator change goes through the version constant each
/// generator exposes — [EndlessCourse.generationVersion],
/// [RunEnvironment.generationVersion], [GhostTrace.formatVersion] — pinned
/// in the first group. The workflow is: bump the constant, re-pin the
/// literals below from the new output, land both in one commit. A silent
/// output change fails the literals; a bump without re-pinned goldens fails
/// the version assertions. What no test here can catch is a re-pin with no
/// bump — the bump is the deliberate-change signal, enforced by review,
/// not by this file.
///
/// The literals are frozen values, not snapshots: a failure means the
/// generator changed, and the fix is a version bump plus re-pinned goldens
/// — never quietly editing a number to match. (The daily hash itself is
/// pinned in daily_shift_test.dart; the chain test below re-pins the seed
/// and the course it deals, so the two cannot drift apart.)
void main() {
  group('generator versions', () {
    test('the golden seeds cover the shipped generator versions', () {
      expect(EndlessCourse.generationVersion, 1,
          reason: 'course/fare output changed: bump the constant and '
              're-pin the course goldens in this file');
      expect(RunEnvironment.generationVersion, 1,
          reason: 'environment output changed: bump the constant and '
              're-pin the environment goldens in this file');
      expect(GhostTrace.formatVersion, 1,
          reason: 'ghost trace behavior changed: bump the constant and '
              're-pin the ghost goldens in this file');
    });
  });

  group('golden course (seed 0xC0FFEE)', () {
    // index: (pickup.x, pickup.y, dropoff.x, dropoff.y, reward, kind,
    //         pickupDistance, dropoffDistance).
    // Covers both kerbs, every fare kind, the junction-nudged pickup in
    // slot 32 (its whole drawn inset range sits inside the 45,000 px
    // junction), and the junction-nudged dropoffs in slots 25 (far edge)
    // and 57 (near edge, where the far edge pokes past the slot ceiling).
    const fares =
        <int, (double, double, double, double, int, FareType, double, double)>{
      0: (
        315.0,
        -173.26048278808594,
        85.0,
        -794.1467895507812,
        41,
        FareType.standard,
        173.26048163915374,
        794.1468051545351,
      ),
      1: (
        85.0,
        -1572.6376953125,
        315.0,
        -2137.4580078125,
        50,
        FareType.standard,
        1572.6377311303286,
        2137.4579010007956,
      ),
      2: (
        315.0,
        -3020.3818359375,
        315.0,
        -3588.420166015625,
        44,
        FareType.standard,
        3020.3818815155555,
        3588.4201873937027,
      ),
      3: (
        315.0,
        -4470.75927734375,
        315.0,
        -5320.83935546875,
        58,
        FareType.standard,
        4470.759412419722,
        5320.839510771906,
      ),
      5: (
        85.0,
        -7260.482421875,
        315.0,
        -8078.0751953125,
        183,
        FareType.vip,
        7260.482473151014,
        8078.075360420898,
      ),
      13: (
        85.0,
        -18449.984375,
        315.0,
        -19000.984375,
        78,
        FareType.awkward,
        18449.983915660505,
        19000.983915660505,
      ),
      14: (
        85.0,
        -19750.0,
        85.0,
        -20850.0,
        70,
        FareType.longHaul,
        19750.0,
        20850.0,
      ),
      25: (
        85.0,
        -35186.75390625,
        315.0,
        -36200.0,
        68,
        FareType.standard,
        35186.753310582666,
        36200.0,
      ),
      32: (
        315.0,
        -45200.0,
        315.0,
        -46050.0,
        55,
        FareType.standard,
        45200.0,
        46050.0,
      ),
      33: (
        85.0,
        -46431.59375,
        315.0,
        -47262.6171875,
        49,
        FareType.standard,
        46431.59276313395,
        47262.61573958697,
      ),
      57: (
        85.0,
        -79955.8046875,
        315.0,
        -80800.0,
        183,
        FareType.vip,
        79955.80382815372,
        80800.0,
      ),
      64: (
        315.0,
        -90200.0,
        315.0,
        -90850.0,
        159,
        FareType.vip,
        90200.0,
        90850.0,
      ),
    };

    test('fares are frozen at the golden seed', () {
      final course = EndlessCourse(seed: 0xC0FFEE);
      for (final entry in fares.entries) {
        final index = entry.key;
        final expected = entry.value;
        final fare = course.fare(index);
        expect(fare.index, index, reason: 'fare $index index');
        expect(fare.pickup.x, expected.$1, reason: 'fare $index pickup x');
        expect(fare.pickup.y, expected.$2, reason: 'fare $index pickup y');
        expect(fare.dropoff.x, expected.$3, reason: 'fare $index dropoff x');
        expect(fare.dropoff.y, expected.$4, reason: 'fare $index dropoff y');
        expect(fare.reward, expected.$5, reason: 'fare $index reward');
        expect(fare.fareType, expected.$6, reason: 'fare $index kind');
        expect(fare.pickupDistance, expected.$7,
            reason: 'fare $index pickup distance');
        expect(fare.dropoffDistance, expected.$8,
            reason: 'fare $index dropoff distance');
      }
    });

    test('relocated dropoffs are frozen at the golden seed', () {
      final course = EndlessCourse(seed: 0xC0FFEE);

      final first = course.relocatedDropoff(0);
      expect(first.x, 315.0, reason: 'fare 0 relocation x');
      expect(first.y, -1463.7314453125, reason: 'fare 0 relocation y');
      expect(course.relocatedDropoffDistance(0), 1463.731422963761,
          reason: 'fare 0 relocation distance');

      final chained = course.relocatedDropoff(14, attempt: 1);
      expect(chained.x, 85.0, reason: 'fare 14 attempt 1 relocation x');
      expect(chained.y, -21832.986328125,
          reason: 'fare 14 attempt 1 relocation y');
      expect(
          course.relocatedDropoffDistance(14, attempt: 1), 21832.985499934905,
          reason: 'fare 14 attempt 1 relocation distance');

      // Fare 18's hop lands inside the 27,000 px junction band, so the
      // containment runs the hop on to the band's far edge (27,200) —
      // the one pinned relocation that exercises the margin at
      // endless_course.dart's relocatedDropoffDistance.
      final inBand = course.relocatedDropoff(18);
      expect(inBand.x, 85.0, reason: 'fare 18 relocation x');
      expect(inBand.y, -27200.0, reason: 'fare 18 relocation y');
      expect(course.relocatedDropoffDistance(18), 27200.0,
          reason: 'fare 18 relocation cleared to the band far edge');
      final chainedAfterClear = course.relocatedDropoff(18, attempt: 1);
      expect(chainedAfterClear.x, 315.0,
          reason: 'fare 18 attempt 1 relocation x');
      expect(chainedAfterClear.y, -27849.203125,
          reason: 'fare 18 attempt 1 relocation y');
      expect(
          course.relocatedDropoffDistance(18, attempt: 1), 27849.202991873433,
          reason: 'fare 18 attempt 1 relocation distance');
    });

    test('the fare-kind draws over the first 130 slots are frozen', () {
      // The kind draw is the last draw of each slot (issue #25). Pinning
      // every index of every kind over 130 slots freezes the draw stream
      // around the share boundaries, so a share or draw-order change
      // flips an index here even when no individually pinned fare's own
      // kind happens to sit on the changed boundary.
      final course = EndlessCourse(seed: 0xC0FFEE);
      final byKind = <FareType, List<int>>{};
      for (var i = 0; i < 130; i++) {
        (byKind[course.fare(i).fareType] ??= []).add(i);
      }
      expect(byKind, {
        FareType.standard: [
          0,
          1,
          2,
          3,
          4,
          6,
          7,
          8,
          9,
          10,
          11,
          12,
          17,
          19,
          20,
          21,
          22,
          24,
          25,
          26,
          27,
          28,
          29,
          30,
          31,
          32,
          33,
          34,
          38,
          39,
          40,
          41,
          44,
          45,
          46,
          47,
          48,
          49,
          52,
          53,
          55,
          56,
          58,
          60,
          63,
          65,
          67,
          70,
          71,
          72,
          73,
          74,
          75,
          76,
          77,
          78,
          79,
          82,
          83,
          84,
          85,
          86,
          87,
          89,
          90,
          91,
          92,
          93,
          95,
          96,
          97,
          99,
          101,
          103,
          104,
          105,
          106,
          107,
          108,
          109,
          110,
          111,
          113,
          115,
          116,
          117,
          119,
          120,
          121,
          122,
          124,
          127,
        ],
        FareType.vip: [
          5,
          16,
          18,
          35,
          43,
          57,
          62,
          64,
          80,
          94,
          102,
          123,
          125,
          129,
        ],
        FareType.awkward: [13, 23, 36, 37, 51, 54, 81, 112, 114],
        FareType.longHaul: [
          14,
          15,
          42,
          50,
          59,
          61,
          66,
          68,
          69,
          88,
          98,
          100,
          118,
          126,
          128,
        ],
      });
    });
  });

  group('golden environment (seed 0xC0FFEE)', () {
    final env = RunEnvironment(seed: 0xC0FFEE);

    test('road profiles are frozen', () {
      expect(env.profileForSegment(9), RoadProfile.standard);
      expect(env.profileForSegment(4), RoadProfile.narrow);
      expect(env.profileForSegment(10), RoadProfile.avenue);
      expect(env.profileForSegment(11), RoadProfile.narrow);
    });

    test('the segment draws over the first 30 segments are frozen', () {
      // The full sequences, not sampled points: a share tweak (weather,
      // profile, or works) flips a segment here even when no individually
      // pinned distance happens to cross the changed boundary.
      expect(
        [for (var i = 2; i <= 30; i++) env.profileForSegment(i).name],
        [
          'standard',
          'standard',
          'narrow',
          'standard',
          'standard',
          'standard',
          'standard',
          'standard',
          'avenue',
          'narrow',
          'standard',
          'narrow',
          'standard',
          'standard',
          'narrow',
          'standard',
          'standard',
          'standard',
          'standard',
          'avenue',
          'standard',
          'avenue',
          'narrow',
          'narrow',
          'narrow',
          'narrow',
          'narrow',
          'standard',
          'standard',
        ],
      );
      expect(
        [
          for (var i = 2; i <= 30; i++)
            env.weatherAt(i * 4400.0 + 2200.0).type.name,
        ],
        [
          'clear',
          'clear',
          'clear',
          'clear',
          'clear',
          'rain',
          'fog',
          'clear',
          'fog',
          'clear',
          'clear',
          'clear',
          'rain',
          'fog',
          'rain',
          'rain',
          'fog',
          'rain',
          'fog',
          'clear',
          'clear',
          'clear',
          'fog',
          'rain',
          'rain',
          'clear',
          'fog',
          'rain',
          'clear',
        ],
      );
      expect(
        [
          for (var i = 2; i <= 30; i++)
            if (env.constructionForSegment(i) != null) i,
        ],
        [5, 6, 14, 15, 16, 19, 21, 23, 24, 25, 26],
      );
    });

    test('weather, its edge fade, and its grip/visibility folds are frozen',
        () {
      expect(env.weatherAt(33000).type, WeatherType.rain);
      expect(env.weatherAt(33000).intensity, 0.7401964056461647);
      expect(env.weatherAt(31000).intensity, 0.2960785622584659,
          reason: 'the leading fade scales the segment draw');
      expect(env.weatherAt(34950).intensity, 0.37009820282308237,
          reason: 'the trailing fade scales the segment draw');
      expect(env.weatherAt(37400).type, WeatherType.fog);
      expect(env.weatherAt(37400).intensity, 0.6882868465723506);
      expect(env.weatherAt(46200).intensity, 0.9298289567134369);
      expect(env.gripAt(33000), 0.7779410783061506);
      expect(env.visibilityAt(37400), 0.7590996036996773);
      expect(env.difficultyModifierAt(33000), 0.11821178433876987);
    });

    test('construction zones are frozen', () {
      final zone = env.constructionForSegment(5)!;
      expect(zone.startDistance, 20300.0);
      expect(zone.endDistance, 21373.934748694992);
      expect(zone.boundaryFraction, 0.5);
      expect(zone.closedRight, isFalse);

      final closedRight = env.constructionForSegment(6)!;
      expect(closedRight.startDistance, 24300.0);
      expect(closedRight.endDistance, 25251.309169478867);
      expect(closedRight.closedRight, isTrue);

      final twoOfThree = env.constructionForSegment(21)!;
      expect(twoOfThree.boundaryFraction, 0.6666666666666666);

      expect(env.constructionForSegment(7), isNull,
          reason: 'a segment that rolls no works stays null');
    });

    test('time of day and darkness are frozen', () {
      expect(env.darknessAt(24000), 0.2125925925925929);
      expect(env.darknessAt(36000), RunEnvironment.nightDarkness);
      expect(env.darknessAt(54000), 0.6074074074074071);
      expect(env.timeOfDayAt(21000), TimeOfDay.dusk);
      expect(env.timeOfDayAt(36000), TimeOfDay.night);
      expect(env.timeOfDayAt(54000), TimeOfDay.dawn);
    });

    test('the road taper and its kerbs are frozen', () {
      final road = env.roadAt(16400);
      expect(road.profile, RoadProfile.narrow);
      expect(road.width, 161.48148148148147);
      expect(env.leftCurbXAt(16400), 104.25925925925927);
      expect(env.rightCurbXAt(16400), 295.74074074074076);
    });

    test('the traffic profile is frozen', () {
      final traffic = env.trafficAt(20000);
      expect(traffic.spawnInterval, 3.1426860010388746);
      expect(traffic.lanes.length, 2);
      expect(traffic.lanes[0].laneX, 163.0);
      expect(traffic.lanes[0].spawnProbability, 0.4813548843956227);
      expect(traffic.lanes[1].laneX, 237.0);
      expect(traffic.lanes[1].spawnProbability, 0.3648680767232933);
      // The speed output — the field the verifier demonstrated could
      // drift silently (a _rampedSpeedMean tweak moved it while every
      // other pin held). Both lanes share the core's speedRange.
      expect(traffic.lanes[0].speedRange.min, 106.3737063778858);
      expect(traffic.lanes[0].speedRange.max, 159.57352431143153);
      expect(traffic.lanes[1].speedRange.min, 106.3737063778858);
      expect(traffic.lanes[1].speedRange.max, 159.57352431143153);
      final core = DifficultyCurve.trafficCoreFor(20000,
          environmentModifier: env.difficultyModifierAt(20000));
      expect(core.meanSpeed, 132.97361534465867);
      expect(core.halfSpread, 26.599908966772873);
    });
  });

  group('golden daily course (2026-09-26)', () {
    test('the date seed and the course it deals are frozen', () {
      final seed = DailyShift.seedForDateKey('2026-09-26');
      expect(seed, 831957206,
          reason: 'the daily hash is load-bearing and must never change');

      final course = EndlessCourse(seed: seed);
      // index: (pickup.x, pickup.y, dropoff.x, dropoff.y, reward, kind).
      const expected = <int, (double, double, double, double, int, FareType)>{
        0: (
          85.0,
          -161.29502868652344,
          85.0,
          -989.9982299804688,
          51,
          FareType.standard,
        ),
        1: (
          85.0,
          -1606.5115966796875,
          85.0,
          -2281.992431640625,
          44,
          FareType.standard,
        ),
        2: (
          85.0,
          -3055.41943359375,
          315.0,
          -3606.41943359375,
          59,
          FareType.awkward,
        ),
        3: (
          315.0,
          -4412.26806640625,
          315.0,
          -5009.80517578125,
          54,
          FareType.standard,
        ),
      };
      for (final entry in expected.entries) {
        final index = entry.key;
        final fare = course.fare(index);
        expect(fare.pickup.x, entry.value.$1, reason: 'fare $index pickup x');
        expect(fare.pickup.y, entry.value.$2, reason: 'fare $index pickup y');
        expect(fare.dropoff.x, entry.value.$3, reason: 'fare $index dropoff x');
        expect(fare.dropoff.y, entry.value.$4, reason: 'fare $index dropoff y');
        expect(fare.reward, entry.value.$5, reason: 'fare $index reward');
        expect(fare.fareType, entry.value.$6, reason: 'fare $index kind');
      }
    });
  });

  group('golden ghost behavior', () {
    const trace = GhostTrace(
      dateKey: '2026-09-26',
      score: 480,
      banked: true,
      vehicleId: 'sedan_blue',
      samples: [200, 0, 205, -60, 210, -120],
    );

    test('the recorder samples the driven-time grid exactly', () {
      final recorder = GhostRecorder();
      for (var k = 0; k < 12; k++) {
        recorder.tick(0.05, 200 + k.toDouble(), -7.0 * k);
      }
      expect(recorder.takeSamples(), [200, 0, 203, -21, 208, -56]);
    });

    test('playback interpolates and clamps exactly', () {
      final playback = GhostPlayback(trace);
      expect(playback.positionAt(0).x, 200.0);
      expect(playback.positionAt(0).y, 0.0);
      expect(playback.positionAt(0.1).x, 202.5);
      expect(playback.positionAt(0.1).y, -30.0);
      expect(playback.positionAt(0.3).x, 207.5);
      expect(playback.positionAt(0.3).y, -90.0);
      expect(playback.positionAt(0.5).x, 210.0);
      expect(playback.positionAt(0.5).y, -120.0);
    });

    test('the trace JSON shape is frozen', () {
      expect(
        jsonEncode(trace.toJson()),
        '{"dateKey":"2026-09-26","score":480,"banked":true,'
        '"vehicleId":"sedan_blue","samples":[200,0,205,-60,210,-120],'
        '"samplePeriodSeconds":0.2}',
      );
    });
  });
}
