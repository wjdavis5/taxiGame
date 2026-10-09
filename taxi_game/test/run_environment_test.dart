import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/components/dropoff_zone.dart';
import 'package:taxi_game/game/components/pickup_zone.dart';
import 'package:taxi_game/game/systems/difficulty_curve.dart';
import 'package:taxi_game/game/systems/endless_course.dart';
import 'package:taxi_game/game/systems/run_environment.dart';

/// The living world of an endless run (issue #24): road geometry, weather,
/// time of day, construction, and intersections — all pure functions of
/// (seed, distance), so the Daily Shift reproduces them exactly like its
/// fares.
void main() {
  group('RunEnvironment — determinism and purity', () {
    test('same seed reads the same world at every distance', () {
      final a = RunEnvironment(seed: 42);
      final b = RunEnvironment(seed: 42);

      for (var d = 0.0; d <= 300000; d += 997.0) {
        expect(b.roadAt(d).width, a.roadAt(d).width, reason: 'width at $d');
        expect(b.roadAt(d).profile, a.roadAt(d).profile,
            reason: 'profile at $d');
        expect(b.weatherAt(d).type, a.weatherAt(d).type,
            reason: 'weather at $d');
        expect(b.weatherAt(d).intensity, a.weatherAt(d).intensity,
            reason: 'weather at $d');
        expect(b.darknessAt(d), a.darknessAt(d), reason: 'darkness at $d');
        expect(b.difficultyModifierAt(d), a.difficultyModifierAt(d),
            reason: 'modifier at $d');
        expect(b.isIntersectionAt(d), a.isIntersectionAt(d),
            reason: 'junction at $d');
      }
    });

    test('querying far ahead changes nothing near (pure functions, no '
        'state)', () {
      final a = RunEnvironment(seed: 7);
      final b = RunEnvironment(seed: 7);

      // Read the far end first on b, then compare the near road.
      b.roadAt(780000);
      b.weatherAt(790000);

      for (var d = 0.0; d <= 20000; d += 250) {
        expect(b.roadAt(d).width, a.roadAt(d).width, reason: 'width $d');
        expect(b.weatherAt(d).intensity, a.weatherAt(d).intensity,
            reason: 'weather $d');
      }
    });

    test('different seeds draw different streets and skies', () {
      var widthDiffers = false;
      var weatherDiffers = false;
      for (var d = 9000.0; d <= 120000; d += 500) {
        final a = RunEnvironment(seed: 1);
        final b = RunEnvironment(seed: 2);
        if (a.roadAt(d).width != b.roadAt(d).width) widthDiffers = true;
        if (a.weatherAt(d).type != b.weatherAt(d).type) weatherDiffers = true;
      }
      expect(widthDiffers, isTrue, reason: 'roads differ between seeds');
      expect(weatherDiffers, isTrue, reason: 'weather differs between seeds');
    });
  });

  group('RunEnvironment — the calm open', () {
    test('the opening is the standard daylight street', () {
      final env = RunEnvironment(seed: 31337);
      for (var d = 0.0; d < RunEnvironment.calmOpenDistance; d += 250) {
        expect(env.roadAt(d).width, RoadProfile.standard.width,
            reason: 'width at $d');
        expect(env.roadAt(d).profile, RoadProfile.standard,
            reason: 'profile at $d');
        expect(env.weatherAt(d).type, WeatherType.clear,
            reason: 'weather at $d');
        expect(env.weatherAt(d).intensity, 0.0, reason: 'intensity at $d');
      }
      expect(env.darknessAt(0), 0.0, reason: 'the run departs in daylight');
    });

    test('no works and no junctions before the open ends', () {
      final env = RunEnvironment(seed: 11);
      for (var d = 0.0; d < RunEnvironment.calmOpenDistance; d += 100) {
        expect(env.constructionAt(d), isNull, reason: 'works at $d');
        expect(env.isIntersectionAt(d), isFalse, reason: 'junction at $d');
      }
    });
  });

  group('RunEnvironment — road geometry (width and lane count)', () {
    test('widths stay within the three profiles, tapers included', () {
      final env = RunEnvironment(seed: 5);
      for (var d = 0.0; d <= 400000; d += 60) {
        final width = env.roadAt(d).width;
        expect(width, inInclusiveRange(RoadProfile.narrow.width,
            RoadProfile.avenue.width), reason: 'width at $d');
      }
    });

    test('the road changes profile across a long run', () {
      final env = RunEnvironment(seed: 5);
      final widths = <double>{};
      final laneCounts = <int>{};
      for (var d = RunEnvironment.calmOpenDistance; d <= 300000; d += 500) {
        final road = env.roadAt(d);
        widths.add(road.width);
        laneCounts.add(road.laneCount);
      }
      expect(widths.length, greaterThan(2),
          reason: 'more than one width appears over 30 km');
      expect(laneCounts, contains(2), reason: 'two-lane streets exist');
      expect(laneCounts, contains(3), reason: 'three-lane avenues exist');
    });

    test('tapers are gradual: the width never jumps', () {
      final env = RunEnvironment(seed: 1234);
      var previous = env.roadAt(0).width;
      for (var d = 60.0; d <= 300000; d += 60) {
        final width = env.roadAt(d).width;
        // Worst-case taper: the full 116 px swing (narrow to avenue)
        // over the 600 px taper. Smoothstep peaks at 1.5× the mean
        // slope, so a 60 px step moves the kerb at most ~17.4 px — under
        // half a car, never a wall.
        expect((width - previous).abs(), lessThanOrEqualTo(18.0),
            reason: 'width step at $d');
        previous = width;
      }
    });

    test('lane layout: oncoming lanes sit left, same-direction at or '
        'right of centre', () {
      final env = RunEnvironment(seed: 77);
      for (var d = 0.0; d <= 300000; d += 500) {
        final road = env.roadAt(d);
        final xs = road.laneXs;
        expect(xs, hasLength(road.laneCount));
        for (var i = 0; i < xs.length; i++) {
          final oncoming = road.isLaneOncoming(i);
          if (oncoming) {
            expect(xs[i], lessThan(road.centerX), reason: 'lane $i at $d');
          } else {
            expect(xs[i], greaterThanOrEqualTo(road.centerX),
                reason: 'lane $i at $d');
          }
          // Every lane centre sits inside the drivable surface.
          expect(xs[i], inInclusiveRange(road.leftX, road.rightX),
              reason: 'lane $i inside the road at $d');
        }
        expect(road.oncomingLaneX, lessThan(road.centerX), reason: 'at $d');
        expect(road.sameDirectionLaneX, greaterThanOrEqualTo(road.centerX),
            reason: 'at $d');
      }
    });

    test('narrow streets still fit the widest traffic with a dodge gap',
        () {
      // The catalog caps traffic at 50 px wide (bus); the player at 50.
      // A 148 px street must leave real room between opposing lanes.
      expect(RoadProfile.narrow.width, greaterThan(2 * 50 + 40));
    });

    test('kerbs follow the road edge', () {
      final env = RunEnvironment(seed: 8);
      for (var d = 0.0; d <= 200000; d += 700) {
        final road = env.roadAt(d);
        expect(env.leftCurbXAt(d), closeTo(road.leftX - 15, 0.001),
            reason: 'left kerb at $d');
        expect(env.rightCurbXAt(d), closeTo(road.rightX + 15, 0.001),
            reason: 'right kerb at $d');
      }
    });
  });

  group('RunEnvironment — time of day', () {
    test('the run departs in daylight and reaches full night', () {
      final env = RunEnvironment(seed: 99);
      expect(env.darknessAt(0), 0.0);
      expect(env.timeOfDayAt(0), TimeOfDay.day);

      // Halfway into the first day-cycle: the night plateau.
      expect(env.darknessAt(RunEnvironment.dayLength / 2),
          RunEnvironment.nightDarkness);
      expect(env.timeOfDayAt(RunEnvironment.dayLength * 0.53),
          TimeOfDay.night, reason: 'night holds past the dusk ramp');

      // The night is deep but never a blackout.
      expect(RunEnvironment.nightDarkness, lessThan(1.0));
      expect(RunEnvironment.nightDarkness, greaterThanOrEqualTo(0.7));
    });

    test('darkness moves smoothly: no snaps the eye would read as a '
        'flicker', () {
      final env = RunEnvironment(seed: 21);
      var previous = env.darknessAt(0);
      for (var d = 30.0; d <= 200000; d += 30) {
        final darkness = env.darknessAt(d);
        // 30 px is a third of a second of driving; the sky may not jump.
        expect((darkness - previous).abs(), lessThanOrEqualTo(0.01),
            reason: 'darkness step at $d');
        previous = darkness;
      }
    });

    test('the day cycles: darkness is periodic over dayLength', () {
      final env = RunEnvironment(seed: 33);
      for (var d = 0.0; d <= RunEnvironment.dayLength; d += 1500) {
        expect(env.darknessAt(d + RunEnvironment.dayLength),
            closeTo(env.darknessAt(d), 1e-9), reason: 'day wrap at $d');
      }
    });

    test('the day arc passes through dusk, night, and dawn in order', () {
      final env = RunEnvironment(seed: 4);
      final phases = <TimeOfDay>[
        for (var d = 0.0; d < RunEnvironment.dayLength; d += 1000)
          env.timeOfDayAt(d),
      ];
      // First occurrence order across one full day.
      final seen = phases.toSet().toList();
      expect(seen, containsAllInOrder(
          [TimeOfDay.day, TimeOfDay.dusk, TimeOfDay.night, TimeOfDay.dawn]));
    });
  });

  group('RunEnvironment — weather', () {
    test('a long run meets rain and fog as well as clear skies', () {
      final env = RunEnvironment(seed: 42);
      final types = <WeatherType>{};
      for (var d = 0.0; d <= 200000; d += 200) {
        types.add(env.weatherAt(d).type);
      }
      expect(types, contains(WeatherType.clear));
      expect(types, contains(WeatherType.rain));
      expect(types, contains(WeatherType.fog));
    });

    test('intensity stays bounded and fades smoothly at fronts', () {
      final env = RunEnvironment(seed: 42);
      for (var d = 0.0; d <= 200000; d += 50) {
        final w = env.weatherAt(d);
        expect(w.intensity, inInclusiveRange(0.0, 1.0), reason: 'at $d');
      }
      var previous = env.rainIntensityAt(0) + env.fogIntensityAt(0);
      for (var d = 25.0; d <= 200000; d += 25) {
        final now = env.rainIntensityAt(d) + env.fogIntensityAt(d);
        expect((now - previous).abs(), lessThanOrEqualTo(0.05),
            reason: 'intensity step at $d');
        previous = now;
      }
    });

    test('rain steals grip; fog steals sight; clear keeps both', () {
      final env = RunEnvironment(seed: 42);
      var sawRain = false;
      var sawFog = false;
      for (var d = 0.0; d <= 200000; d += 100) {
        final grip = env.gripAt(d);
        final visibility = env.visibilityAt(d);
        expect(grip, inInclusiveRange(1.0 - RunEnvironment.rainGripLoss, 1.0),
            reason: 'grip at $d');
        expect(visibility,
            inInclusiveRange(1.0 - RunEnvironment.fogVisibilityLoss, 1.0),
            reason: 'visibility at $d');

        final rain = env.rainIntensityAt(d);
        final fog = env.fogIntensityAt(d);
        if (rain > 0.8) {
          sawRain = true;
          expect(grip, lessThan(0.85), reason: 'wet road loses grip at $d');
        }
        if (fog > 0.8) {
          sawFog = true;
          expect(visibility, lessThan(0.85),
              reason: 'fog cuts sight distance at $d');
        }
        if (rain <= 0 && fog <= 0) {
          expect(grip, 1.0, reason: 'dry grip at $d');
          expect(visibility, 1.0, reason: 'clear sight at $d');
        }
      }
      expect(sawRain, isTrue, reason: 'this seed meets heavy rain');
      expect(sawFog, isTrue, reason: 'this seed meets thick fog');
    });
  });

  group('RunEnvironment — the difficulty fold', () {
    test('clear daylight adds nothing: the bare curve is untouched', () {
      final env = RunEnvironment(seed: 6);
      for (var d = 0.0; d < RunEnvironment.calmOpenDistance; d += 200) {
        expect(env.difficultyModifierAt(d), 0.0, reason: 'at $d');
        final profile = env.trafficAt(d);
        final bare = DifficultyCurve.trafficForDistance(d);
        expect(profile.spawnInterval, bare.spawnInterval, reason: 'at $d');
        expect(profile.lanes.first.speedRange.min,
            bare.lanes.first.speedRange.min, reason: 'at $d');
      }
    });

    test('rain, fog, and night push the SAME curve harder', () {
      final env = RunEnvironment(seed: 42);
      var foul = 0;
      for (var d = RunEnvironment.calmOpenDistance; d <= 200000; d += 100) {
        final modifier = env.difficultyModifierAt(d);
        expect(modifier, inInclusiveRange(0.0, RunEnvironment.maxModifier),
            reason: 'modifier at $d');
        if (modifier < 0.05) continue;
        foul++;
        final withWeather = env.trafficAt(d);
        final bare = DifficultyCurve.trafficForDistance(d);
        // One system: every knob moves the way extra pressure moves it.
        expect(withWeather.spawnInterval, lessThan(bare.spawnInterval),
            reason: 'interval at $d');
        expect(
            withWeather.lanes.first.speedRange.max,
            greaterThanOrEqualTo(bare.lanes.first.speedRange.max),
            reason: 'speed at $d');
        expect(
            DifficultyCurve.farePressureFor(d,
                    environmentModifier: modifier)
                .clamp(0.0, 1.0),
            greaterThanOrEqualTo(DifficultyCurve.farePressureFor(d)),
            reason: 'meter at $d');
      }
      expect(foul, greaterThan(0), reason: 'this seed meets foul moments');
    });

    test('the environment profile keeps total spawn pressure constant '
        'across lane counts', () {
      final env = RunEnvironment(seed: 42);
      for (var d = 9000.0; d <= 150000; d += 1000) {
        final road = env.roadAt(d);
        final profile = env.trafficAt(d);
        expect(profile.lanes, hasLength(road.laneCount));

        // Per-side probability mass is split across that side's lanes,
        // never invented: the sum per side never exceeds the curve's
        // single-lane anchor.
        final bare = DifficultyCurve.trafficCoreFor(
            d, environmentModifier: env.difficultyModifierAt(d));
        var oncomingSum = 0.0;
        var sameDirSum = 0.0;
        for (final lane in profile.lanes) {
          if (lane.oncoming) {
            oncomingSum += lane.spawnProbability;
          } else {
            sameDirSum += lane.spawnProbability;
          }
        }
        expect(oncomingSum, closeTo(bare.oncomingProbability, 0.001),
            reason: 'oncoming mass at $d');
        expect(sameDirSum, closeTo(bare.sameDirectionProbability, 0.001),
            reason: 'same-direction mass at $d');
      }
    });
  });

  group('RunEnvironment — construction and intersections', () {
    test('work zones exist on a long run and are internally consistent',
        () {
      final env = RunEnvironment(seed: 1001);
      var zones = 0;
      for (var i = 2; i < 60; i++) {
        final zone = env.constructionForSegment(i);
        if (zone == null) continue;
        zones++;
        final length = zone.endDistance - zone.startDistance;
        expect(length, inInclusiveRange(500.0, 1100.0),
            reason: 'zone length in segment $i');
        // A zone never sits inside a junction or up against it.
        for (var d = zone.startDistance - 1.0;
            d <= zone.endDistance + 1.0;
            d += 10.0) {
          expect(env.isIntersectionAt(d), isFalse,
              reason: 'zone in segment $i near junction at $d');
        }
        expect(zone.boundaryFraction, greaterThan(0.0));
        expect(zone.boundaryFraction, lessThan(1.0));
      }
      expect(zones, greaterThan(0), reason: 'the city has roadworks');
    });

    test('the closed side is blocked for traffic; the open side is not',
        () {
      final env = RunEnvironment(seed: 1001);
      var checked = 0;
      for (var i = 2; i < 60; i++) {
        final zone = env.constructionForSegment(i);
        if (zone == null) continue;
        final mid = (zone.startDistance + zone.endDistance) / 2;
        final road = env.roadAt(mid);
        var sawOpen = false;
        for (final laneX in road.laneXs) {
          final fraction = (laneX - road.leftX) / road.width;
          final closedSide = zone.closedRight
              ? fraction > zone.boundaryFraction
              : fraction < zone.boundaryFraction;
          if (closedSide) {
            expect(env.isLaneBlockedAt(mid, laneX), isTrue,
                reason: 'closed lane $laneX at $mid');
          } else {
            expect(env.isLaneBlockedAt(mid, laneX), isFalse,
                reason: 'open lane $laneX at $mid');
            sawOpen = true;
          }
        }
        expect(sawOpen, isTrue,
            reason: 'a closure always leaves the other side open');
        checked++;
      }
      expect(checked, greaterThan(0));
    });

    test('intersections land at their fixed spacing, never in the calm '
        'open', () {
      final env = RunEnvironment(seed: 9);
      const spacing = RunEnvironment.intersectionSpacing;
      const halfBand = RunEnvironment.intersectionHalfBand;
      // The band is centred on the junction (issue #152): the same ±160 px
      // rectangle the renderer paints, so the no-spawn zone is the cross
      // street itself — not its lower half plus 160 px of plain road
      // above. Both edges of the painted band flip exactly there.
      expect(env.isIntersectionAt(spacing - halfBand - 1), isFalse);
      expect(env.isIntersectionAt(spacing - halfBand + 1), isTrue,
          reason: 'the painted band opens at spacing − halfBand');
      expect(env.isIntersectionAt(spacing - 1), isTrue,
          reason: 'the junction\'s lower half is inside the band — the '
              'old lookup started the band at the centre and let traffic '
              'spawn here');
      expect(env.isIntersectionAt(spacing + halfBand - 1), isTrue);
      expect(env.isIntersectionAt(spacing + halfBand + 1), isFalse,
          reason: 'plain road resumes past the junction\'s upper edge — '
              'the old lookup held 160 px of it empty');
      expect(env.isIntersectionAt(2 * spacing - halfBand + 10), isTrue);
      for (var d = 0.0; d < spacing - halfBand; d += 100) {
        expect(env.isIntersectionAt(d), isFalse, reason: 'at $d');
      }
    });
  });

  group('RunEnvironment — the road never degenerates (issue #30)', () {
    /// The road must be drivable at every distance a run can reach: finite
    /// edges and a width that always fits at least the narrow profile.
    /// Canvas silently skips non-finite paths, so a single bad sample here
    /// reads on screen as "the road is just blue" from that point on.
    RunEnvironment? env;

    void expectDrivable(double d) {
      final road = env!.roadAt(d);
      expect(road.width.isFinite, isTrue, reason: 'width at $d');
      expect(road.leftX.isFinite, isTrue, reason: 'leftX at $d');
      expect(road.rightX.isFinite, isTrue, reason: 'rightX at $d');
      expect(road.width,
          inInclusiveRange(RoadProfile.narrow.width, RoadProfile.avenue.width),
          reason: 'width at $d');
      expect(road.leftX, lessThanOrEqualTo(road.rightX),
          reason: 'edges ordered at $d');
      for (final x in road.laneXs) {
        expect(x.isFinite, isTrue, reason: 'lane x at $d');
        expect(x, inInclusiveRange(road.leftX, road.rightX),
            reason: 'lane inside the road at $d');
      }
    }

    /// Samples [from]..[to] at 1 px and checks both the geometry and that
    /// the width never jumps between samples (a step wider than the
    /// smoothstep's worst slope means the kerb teleports).
    void sweepFine(double from, double to) {
      var previous = env!.roadAt(from).width;
      for (var d = from; d <= to; d += 1.0) {
        expectDrivable(d);
        final width = env!.roadAt(d).width;
        expect((width - previous).abs(), lessThanOrEqualTo(0.5),
            reason: 'width step at $d');
        previous = width;
      }
    }

    /// Every boundary the geometry math can break on: segment starts (the
    /// taper begins), taper ends, cross streets, and each work zone's
    /// start and end line.
    void sweepBoundaries(double limit) {
      // Segment starts and taper ends.
      for (var i = 1;
          i <= (limit / RunEnvironment.geometrySegmentLength).ceil();
          i++) {
        sweepFine(i * RunEnvironment.geometrySegmentLength - 2.0,
            i * RunEnvironment.geometrySegmentLength + 2.0);
        sweepFine(i * RunEnvironment.geometrySegmentLength +
                RunEnvironment.taperLength -
                2.0,
            i * RunEnvironment.geometrySegmentLength +
                RunEnvironment.taperLength +
                2.0);
      }
      // Cross streets: the junction band and both approaches.
      for (var k = 1;
          k <= (limit / RunEnvironment.intersectionSpacing).floor();
          k++) {
        final center = k * RunEnvironment.intersectionSpacing;
        sweepFine(center - RunEnvironment.intersectionHalfBand - 2.0,
            center + RunEnvironment.intersectionHalfBand + 2.0);
      }
      // Work zones: every rolled zone in range, across its whole length.
      for (var i = 2;
          i <= (limit / RunEnvironment.geometrySegmentLength).floor();
          i++) {
        final zone = env!.constructionForSegment(i);
        if (zone == null) continue;
        sweepFine(zone.startDistance - 2.0, zone.endDistance + 2.0);
      }
    }

    for (final seed in const [1, 42, 999983, 20260927]) {
      test('sweep 0..500,000 px stays drivable (seed $seed)', () {
        env = RunEnvironment(seed: seed);
        for (var d = 0.0; d <= 500000; d += 37.0) {
          expectDrivable(d);
        }
        sweepBoundaries(500000);
      });
    }

    test('the width sweep never leaves the profile band on any seed', () {
      // One more pass across every seed's full range, asserting only the
      // bound — cheap enough to run at 1 px resolution, which is where an
      // off-by-one at a segment edge would show.
      for (final seed in const [31337, 7, 2026, 555]) {
        final e = RunEnvironment(seed: seed);
        for (var d = 0.0; d <= 500000; d += 1.0) {
          final width = e.roadAt(d).width;
          expect(width.isFinite, isTrue, reason: 'width at $d seed $seed');
          expect(
              width,
              inInclusiveRange(
                  RoadProfile.narrow.width, RoadProfile.avenue.width),
              reason: 'width at $d seed $seed');
        }
      }
    });
  });

  group('EndlessCourse on the living road', () {
    test('passengers wait on the kerbs the road actually has', () {
      final env = RunEnvironment(seed: 55);
      final course = EndlessCourse(seed: 55, environment: env);

      for (var i = 0; i < 400; i++) {
        final fare = course.fare(i);
        // The kerb is sampled at the fare's true distance (issue #30):
        // past the world fold, world y no longer reads as distance.
        // Vector2 stores float32, so the y the course sampled the kerb at
        // and the y read back here can differ by a hair — enough to move
        // a tapering kerb by ~0.002 px. Hence 0.01, not 0.001.
        final pickupRoad = env.roadAt(fare.pickupDistance);
        expect(
          fare.pickup.x,
          anyOf(
            closeTo(pickupRoad.leftX - RunEnvironment.curbOffset, 0.01),
            closeTo(pickupRoad.rightX + RunEnvironment.curbOffset, 0.01),
          ),
          reason: 'fare $i pickup sits on a real kerb',
        );
        final dropoffRoad = env.roadAt(fare.dropoffDistance);
        expect(
          fare.dropoff.x,
          anyOf(
            closeTo(dropoffRoad.leftX - RunEnvironment.curbOffset, 0.01),
            closeTo(dropoffRoad.rightX + RunEnvironment.curbOffset, 0.01),
          ),
          reason: 'fare $i dropoff sits on a real kerb',
        );
      }
    });

    test('the same seed still reproduces the same varied course', () {
      final a = EndlessCourse(seed: 64, environment: RunEnvironment(seed: 64));
      final b = EndlessCourse(seed: 64, environment: RunEnvironment(seed: 64));
      for (var i = 0; i < 200; i++) {
        expect(b.fare(i).pickup.x, closeTo(a.fare(i).pickup.x, 1e-9),
            reason: 'fare $i');
        expect(b.fare(i).dropoff.y, closeTo(a.fare(i).dropoff.y, 1e-9),
            reason: 'fare $i');
      }
    });

    test('fares never put a stop beyond the taxi clamp from the road',
        () {
      // The kerb sits [curbOffset] px past the road edge; the clamped
      // taxi's centre is half a car inside it. The zones' detection
      // radii must outrun the distance from the clamped taxi's hitbox to
      // the kerb on every width the environment draws, or a stop would
      // be undriveable-to. The radii are read from the shipped zone
      // classes (issue #226): a local copy of the 40 px constant let the
      // real radius shrink unseen.
      const clampToCurb = RunEnvironment.curbOffset + 50.0 / 2;
      // The zone circle only has to reach the clamp point: the player
      // hitbox (75% of the body) carries the rest of the contact.
      const gapToKerb = clampToCurb - 50.0 * 0.75 / 2;
      expect(gapToKerb, lessThan(PickupZone.detectionRadius),
          reason: 'a clamped taxi still touches a kerbside pickup');
      expect(gapToKerb, lessThan(DropoffZone.detectionRadius),
          reason: 'a clamped taxi still touches a kerbside dropoff');
    });
  });
}
