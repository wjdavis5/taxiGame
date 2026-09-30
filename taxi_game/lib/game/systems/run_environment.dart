import 'dart:math' as math;

import '../../models/traffic_pattern.dart';
import 'difficulty_curve.dart';

/// Where the sun is on its day-long arc.
enum TimeOfDay { day, dusk, night, dawn }

/// What the sky is doing.
enum WeatherType { clear, rain, fog }

/// The road's cross-section at one distance: how wide the drivable surface
/// is and how its lanes are laid out.
class RoadGeometry {
  const RoadGeometry({
    required this.centerX,
    required this.width,
    required this.profile,
  });

  /// World x of the road's centre line. Every geometry keeps the same
  /// centre — only the width and lane count change — so the camera never
  /// swings sideways mid-run.
  final double centerX;

  /// Drivable road width, in px, after any taper has been applied.
  final double width;

  /// The lane layout the width is divided by. During a taper the width is
  /// interpolated between two segments but the lane layout is already the
  /// incoming segment's — a new lane opens as the road widens, exactly the
  /// way a real taper reads.
  final RoadProfile profile;

  double get leftX => centerX - width / 2;
  double get rightX => centerX + width / 2;

  /// The lane-fraction of a world x on this road — the inverse of
  /// [xAtFraction]. Fractions, not px, are what survive a width change:
  /// the spawner re-lays a lane onto the road that exists at the spawn
  /// distance by asking the taxi's road for the fraction and the spawn
  /// road for the x back (issue #87 — lane px from the taxi's road put
  /// cars on the sidewalk wherever an avenue narrowed).
  double fractionOf(double x) => (x - leftX) / width;

  /// The world x at lane-fraction [f] of this road (0 = left edge, 1 =
  /// right edge) — how [laneXs] lays a profile's lanes onto the width.
  double xAtFraction(double f) => leftX + f * width;

  /// World x of every lane centre, left to right.
  List<double> get laneXs => profile.laneFractions
      .map(xAtFraction)
      .toList(growable: false);

  int get laneCount => profile.laneCount;

  /// Lane [i] carries oncoming traffic when its centre sits left of the
  /// road's middle. A lane centred exactly on the middle flows with the
  /// player (the same rule [TrafficLaneConfig]'s JSON default uses).
  bool isLaneOncoming(int i) => profile.laneFractions[i] < 0.5;

  /// The lane centre an oncoming dodger targets — the first oncoming lane.
  double get oncomingLaneX {
    final xs = laneXs;
    for (var i = 0; i < xs.length; i++) {
      if (isLaneOncoming(i)) return xs[i];
    }
    return xs.first;
  }

  /// The lane centre an overtaker targets — the first same-direction lane.
  double get sameDirectionLaneX {
    final xs = laneXs;
    for (var i = 0; i < xs.length; i++) {
      if (!isLaneOncoming(i)) return xs[i];
    }
    return xs.last;
  }
}

/// One stretch of road's fixed cross-section. Widths bound how hard the
/// road can get: the narrow profile still fits two lanes of traffic with a
/// dodging gap, and the avenue's extra lane spreads the same traffic
/// thinner — width and lane count are difficulty pressure and relief,
/// folded into the run's rhythm like everything else.
enum RoadProfile {
  standard(200.0, [0.25, 0.75]),
  narrow(148.0, [0.25, 0.75]),
  avenue(264.0, [1 / 6, 3 / 6, 5 / 6]);

  const RoadProfile(this.width, this.laneFractions);

  final double width;

  /// Lane centres as fractions of the drivable width (0 = left edge).
  final List<double> laneFractions;

  int get laneCount => laneFractions.length;
}

/// A stretch of weather: its type and its faded-in intensity.
class WeatherState {
  const WeatherState({required this.type, required this.intensity});

  final WeatherType type;

  /// 0..1, already including the fade at the segment's edges.
  final double intensity;
}

/// A stretch where one side of the road is closed by a cone line. The
/// cones are the physical barrier; traffic never spawns into the closed
/// lanes for the zone's duration.
class ConstructionZone {
  const ConstructionZone({
    required this.startDistance,
    required this.endDistance,
    required this.boundaryFraction,
    required this.closedRight,
  });

  /// Distance (px into the run) where the cone line starts and ends.
  final double startDistance;
  final double endDistance;

  /// Lane boundary being closed, as a fraction of the road width from its
  /// left edge. Lanes on the closed side of this line are out of service.
  final double boundaryFraction;

  /// Whether the lanes right of [boundaryFraction] are the closed ones.
  final bool closedRight;

  /// Whether this zone covers [distance].
  bool contains(double distance) =>
      distance >= startDistance && distance < endDistance;

  /// Whether this zone overlaps [[from], [to]).
  bool overlaps(double from, double to) =>
      startDistance < to && endDistance > from;
}

/// The living world of an endless run (issue #24): road geometry, weather,
/// time of day, construction, and intersections, all as pure functions of
/// (seed, distance).
///
/// Everything the road does is deterministic from the run's seed, so the
/// Daily Shift (issue #19) reproduces its weather and its streets exactly
/// like its fares, and a ghost race replays them. Nothing here is state:
/// querying 40 km in and then 100 px in gives the same answers as a fresh
/// instance, which is what makes the system unit testable.
///
/// Variety is folded into issue #18's ramp rather than running beside it:
///
///  - the opening [calmOpenDistance] is always the standard daylight
///    street, so onboarding stays learnable (the same principle as the
///    relief wave's fade-in);
///  - foul weather and night ride the lived pressure through
///    [difficultyModifierAt], which [trafficAt] feeds straight into
///    [DifficultyCurve.trafficCoreFor] — there is no second difficulty
///    system, only the one curve breathing harder when the world is meaner;
///  - rain steals lateral grip and fog steals sight distance — physical
///    costs, not extra score pressure — and both are read by the live car
///    and by the run-length simulator, so the tuning harness measures them.
class RunEnvironment {
  RunEnvironment({required this.seed});

  /// The run seed. Same seed, same city, same sky.
  final int seed;

  // --- Cadence ------------------------------------------------------------

  /// Length of one road-geometry segment. Fixed (not drawn per index) so
  /// segment lookups are O(1) index math, like [RoadChunkManager]'s
  /// chunks.
  static const double geometrySegmentLength = 4000.0;

  /// How long a width change takes: the taper at the start of each
  /// geometry segment. Gentle enough that a narrowing road squeezes the
  /// taxi toward its centre instead of walling it.
  static const double taperLength = 600.0;

  /// Length of one weather segment.
  static const double weatherSegmentLength = 4400.0;

  /// Weather fades in and out over this much of each segment's edges, so
  /// grip and visibility change smoothly and two weather fronts never
  /// hard-cut against each other.
  static const double weatherFadeLength = 500.0;

  /// One full day of driving, in px. The median shift (2-4 km) departs in
  /// daylight and drives into dusk or night; a long run sees the dawn.
  static const double dayLength = 60000.0;

  /// How dark full night gets, 0..1. Under 1 so the street stays readable
  /// — this is a night shift, not a blackout.
  static const double nightDarkness = 0.82;

  /// Cross streets cross the road at this spacing.
  static const double intersectionSpacing = 9000.0;

  /// Half the height of an intersection band, in px: the cross street's
  /// carriageway is twice this wide.
  static const double intersectionHalfBand = 160.0;

  /// Px a passenger waits beyond the road edge — the same kerb offset the
  /// hand-made levels and [EndlessCourse]'s default curbs use (road edge
  /// 100, curb 85 on the standard road).
  static const double curbOffset = 15.0;

  /// The run opens on the standard daylight street: geometry and weather
  /// segments before this distance are always standard and clear, no
  /// works are ever rolled before it, and the first cross street lands at
  /// [intersectionSpacing]. Mirrors the relief wave's own fade-in — the
  /// opening kilometres teach, the city varies after.
  static const double calmOpenDistance =
      2 * geometrySegmentLength; // 8000 px

  // --- Difficulty fold ----------------------------------------------------

  /// Pressure added by rain at full intensity, as a fraction.
  static const double rainPressure = 0.06;

  /// Pressure added by fog at full intensity. Foul air costs more than
  /// wet road: it hides the traffic you are dodging.
  static const double fogPressure = 0.07;

  /// Pressure added by full night. Headlights keep the road visible, but
  /// the world beyond them does not exist.
  static const double nightPressure = 0.09;

  /// Hard cap on the combined environment modifier, so a midnight storm
  /// rides the curve without snapping it shut.
  static const double maxModifier = 0.25;

  /// Lateral grip lost at full rain intensity, as a fraction of the car's
  /// steering speed. Wet streets are the felt half of rain; the meter the
  /// player cannot see is the [rainPressure] half.
  static const double rainGripLoss = 0.30;

  /// Sight distance lost at full fog, as a fraction of normal.
  static const double fogVisibilityLoss = 0.35;

  // --- Geometry -----------------------------------------------------------

  /// The road's cross-section at [distance] px into the run.
  ///
  /// A segment's width tapers in from the previous segment's over the
  /// first [taperLength] px, then holds. Behind the start line (negative
  /// distance) the road is the standard street.
  RoadGeometry roadAt(double distance) {
    final d = math.max(0.0, distance);
    final index = (d / geometrySegmentLength).floor();
    final profile = profileForSegment(index);
    final width = _widthAt(d, index, profile);
    return RoadGeometry(
      centerX: roadCenterX,
      width: width,
      profile: profile,
    );
  }

  double _widthAt(double d, int index, RoadProfile profile) {
    if (index <= 0) return RoadProfile.standard.width;
    final previous = profileForSegment(index - 1);
    final intoTaper = d - index * geometrySegmentLength;
    if (intoTaper >= taperLength) return profile.width;
    final t = _smoothstep(intoTaper / taperLength);
    return previous.width + (profile.width - previous.width) * t;
  }

  /// The fixed cross-section rolled for geometry segment [index]. Pure:
  /// the same index always rolls the same profile. Segments inside the
  /// calm open are always standard.
  RoadProfile profileForSegment(int index) {
    if (index < 2) return RoadProfile.standard;
    final r = hash01(seed, 0x6E0A, index);
    // Variety grows with the ramp: early segments mostly stay standard,
    // deep runs narrow and widen constantly.
    final ramp =
        DifficultyCurve.rampFractionFor(index * geometrySegmentLength);
    final narrowShare = 0.10 + 0.15 * ramp;
    final avenueShare = 0.10 + 0.15 * ramp;
    if (r < narrowShare) return RoadProfile.narrow;
    if (r < narrowShare + avenueShare) return RoadProfile.avenue;
    return RoadProfile.standard;
  }

  // --- Kerbs --------------------------------------------------------------

  /// Where a passenger waits on the left kerb at [distance].
  double leftCurbXAt(double distance) => roadAt(distance).leftX - curbOffset;

  /// Where a passenger waits on the right kerb at [distance].
  double rightCurbXAt(double distance) =>
      roadAt(distance).rightX + curbOffset;

  // --- Traffic containment (issue #87) -------------------------------------

  /// Half the width of the widest traffic body any lane can spawn — the
  /// bus. A lane has to fit this band before any spawn is allowed there,
  /// because the vehicle type is rolled only after the lane check.
  static final double widestTrafficHalfWidth = TrafficVehicleType.values
      .map((type) => type.size.x)
      .reduce(math.max) / 2;

  /// Half the length of the longest traffic body any lane can spawn —
  /// the pad that keeps a vehicle centred at either end of its path
  /// fully on the road, the same clearance the level course's end keeps
  /// from its barrier.
  static final double longestTrafficHalfLength = TrafficVehicleType.values
      .map((type) => type.size.y)
      .reduce(math.max) / 2;

  /// The distance span a straight traffic path spawning at
  /// [spawnDistance] covers: oncoming lanes run 1500 px down-screen and
  /// same-direction lanes 3000 px up (the spawner's waypoint steps), each
  /// end padded by half the longest body. The span whose every distance
  /// [laneHoldsOnRoad] must clear before a spawn is allowed — one
  /// authority shared by the live spawner and the run simulator, so the
  /// two can never disagree about which road a car has to fit.
  static (double, double) trafficPathSpan(
    double spawnDistance, {
    required bool oncoming,
  }) {
    final pad = longestTrafficHalfLength;
    return oncoming
        ? (spawnDistance - 1500 - pad, spawnDistance + pad)
        : (spawnDistance - pad, spawnDistance + 3000 + pad);
  }

  /// Whether the body band [laneX − [halfWidth], laneX + [halfWidth]]
  /// stays fully on the road at every distance in [[from], [to]] — the
  /// question a fixed-x traffic path has to answer once, at spawn,
  /// because nothing re-reads the road as the car drives (issue #87).
  ///
  /// Exact, not sampled: the band holds at a distance iff the width
  /// there clears a fixed bar (each edge condition is width ≥ a
  /// constant, since every geometry shares one centre), and width(d) is
  /// monotone within each taper and constant between tapers — so the
  /// tightest points of the whole span are its two ends plus the ends
  /// of every taper it reaches.
  bool laneHoldsOnRoad(
    double from,
    double to,
    double laneX,
    double halfWidth,
  ) {
    bool holdsAt(double d) {
      final road = roadAt(d);
      return laneX - halfWidth >= road.leftX &&
          laneX + halfWidth <= road.rightX;
    }

    final a = math.max(0.0, from); // behind the start line: standard road
    final b = math.max(a, to);
    if (!holdsAt(a) || !holdsAt(b)) return false;

    // Every taper end inside the span. Segment i's taper runs
    // [segmentStart, segmentStart + taperLength]; between tapers the
    // width is constant, so each stretch's narrowest point is one of its
    // endpoints — named here, or [a]/[b] above.
    final first = (a / geometrySegmentLength).floor();
    final last = (b / geometrySegmentLength).floor();
    for (var i = first; i <= last; i++) {
      final segmentStart = i * geometrySegmentLength;
      for (final d in [segmentStart, segmentStart + taperLength]) {
        if (d > a && d < b && !holdsAt(d)) return false;
      }
    }
    return true;
  }

  // --- Weather ------------------------------------------------------------

  /// The weather at [distance], with its segment-edge fade applied.
  WeatherState weatherAt(double distance) {
    final d = math.max(0.0, distance);
    final index = (d / weatherSegmentLength).floor();
    final type = _weatherTypeForIndex(index);
    final base = _weatherIntensityForIndex(index, type);
    // Fade in over the segment's leading edge and out over its trailing
    // edge, so every front arrives and leaves smoothly.
    final into = d - index * weatherSegmentLength;
    final leftIn = into / weatherFadeLength;
    final rightIn = ((index + 1) * weatherSegmentLength - d) /
        weatherFadeLength;
    final fade = leftIn.clamp(0.0, 1.0).toDouble() *
        rightIn.clamp(0.0, 1.0).toDouble();
    return WeatherState(type: type, intensity: base * fade);
  }

  WeatherType _weatherTypeForIndex(int index) {
    if (index < 2) return WeatherType.clear; // the calm open
    final r = hash01(seed, 0x57EA, index);
    // Foul weather becomes more common as the run deepens — folded into
    // the same ramp as the traffic it rides on.
    final ramp =
        DifficultyCurve.rampFractionFor(index * weatherSegmentLength);
    final rainShare = 0.22 + 0.10 * ramp;
    final fogShare = 0.14 + 0.08 * ramp;
    if (r < rainShare) return WeatherType.rain;
    if (r < rainShare + fogShare) return WeatherType.fog;
    return WeatherType.clear;
  }

  double _weatherIntensityForIndex(int index, WeatherType type) {
    if (type == WeatherType.clear) return 0.0;
    return 0.55 + 0.45 * hash01(seed, 0x1CE, index);
  }

  /// Rain wetness at [distance], 0..1. Zero when it is not raining.
  double rainIntensityAt(double distance) {
    final w = weatherAt(distance);
    return w.type == WeatherType.rain ? w.intensity : 0.0;
  }

  /// Fog density at [distance], 0..1. Zero when the air is clear.
  double fogIntensityAt(double distance) {
    final w = weatherAt(distance);
    return w.type == WeatherType.fog ? w.intensity : 0.0;
  }

  /// Lateral grip at [distance], as a fraction of the car's steering
  /// speed: 1.0 on dry ground, 1 − [rainGripLoss] kept in a storm.
  double gripAt(double distance) =>
      1.0 - rainGripLoss * rainIntensityAt(distance);

  /// How far a driver can see at [distance], as a fraction of normal sight
  /// distance: 1.0 in clear air, 1 − [fogVisibilityLoss] in the thick.
  double visibilityAt(double distance) =>
      1.0 - fogVisibilityLoss * fogIntensityAt(distance);

  // --- Time of day --------------------------------------------------------

  /// How dark it is at [distance], 0..1: 0 in daylight, [nightDarkness]
  /// at midnight. Continuous, and periodic over [dayLength] so the road
  /// cycles through days forever.
  double darknessAt(double distance) {
    final t = (math.max(0.0, distance) / dayLength) % 1.0;
    // Keyframes over one day: bright morning, dusk rolling in, the long
    // night, then dawn. Smoothstep between keys keeps every transition
    // gradual — the sky never snaps.
    const keys = <double>[0.00, 0.35, 0.50, 0.85, 1.00];
    const values = <double>[0.0, 0.0, nightDarkness, nightDarkness, 0.0];
    for (var i = 0; i < keys.length - 1; i++) {
      if (t <= keys[i + 1]) {
        final span = keys[i + 1] - keys[i];
        final f = span <= 0 ? 0.0 : (t - keys[i]) / span;
        return values[i] + (values[i + 1] - values[i]) * _smoothstep(f);
      }
    }
    return 0.0;
  }

  /// Where the sun is at [distance].
  TimeOfDay timeOfDayAt(double distance) {
    final t = (math.max(0.0, distance) / dayLength) % 1.0;
    if (t < 0.35) return TimeOfDay.day;
    if (t < 0.52) return TimeOfDay.dusk;
    if (t < 0.85) return TimeOfDay.night;
    return TimeOfDay.dawn;
  }

  // --- Difficulty fold ----------------------------------------------------

  /// How much harder the world at [distance] makes the difficulty curve
  /// breathe, as a fraction added to the lived pressure. Wet, foggy, and
  /// dark moments ride issue #18's wave *harder* — one system, one ramp,
  /// no parallel difficulty.
  double difficultyModifierAt(double distance) {
    final m = rainPressure * rainIntensityAt(distance) +
        fogPressure * fogIntensityAt(distance) +
        nightPressure * darknessAt(distance);
    return math.min(maxModifier, m);
  }

  /// The traffic profile in effect at [distance]: the difficulty curve's
  /// anchors, laid out over the road geometry that actually exists there,
  /// with the environment's modifier folded in. The spawner consumes this
  /// exactly like a level pattern.
  TrafficProfile trafficAt(double distance) {
    final core = DifficultyCurve.trafficCoreFor(
      distance,
      environmentModifier: difficultyModifierAt(distance),
    );

    final road = roadAt(distance);
    final xs = road.laneXs;

    // Count each side once so the road's total expected spawn rate
    // matches the curve's no matter how many lanes carry it: a wide
    // avenue spreads its traffic thinner (easier dodging — wide roads are
    // relief), a narrow street concentrates it (pressure).
    var nOncoming = 0;
    var nSameDir = 0;
    for (var i = 0; i < xs.length; i++) {
      road.isLaneOncoming(i) ? nOncoming++ : nSameDir++;
    }

    final speedRange = SpeedRange(
      min: core.meanSpeed - core.halfSpread,
      max: core.meanSpeed + core.halfSpread,
    );

    final lanes = <TrafficLaneConfig>[];
    for (var i = 0; i < xs.length; i++) {
      final oncoming = road.isLaneOncoming(i);
      final share = oncoming
          ? core.oncomingProbability / math.max(1, nOncoming)
          : core.sameDirectionProbability / math.max(1, nSameDir);
      lanes.add(TrafficLaneConfig(
        laneX: xs[i],
        speedRange: speedRange,
        spawnProbability: share,
        oncoming: oncoming,
      ));
    }

    return TrafficProfile(
      spawnInterval: core.spawnInterval,
      lanes: lanes,
    );
  }

  // --- Construction -------------------------------------------------------

  /// The construction zone covering [distance], if any.
  ConstructionZone? constructionAt(double distance) {
    final zone = constructionForSegment(
        (math.max(0.0, distance) / geometrySegmentLength).floor());
    if (zone != null && zone.contains(distance)) return zone;
    return null;
  }

  /// Every zone overlapping the distance range
  /// [[fromDistance], [toDistance]] — what a road chunk needs to place its
  /// cone lines. Ordered by segment index.
  List<ConstructionZone> constructionInRange(
      double fromDistance, double toDistance) {
    final zones = <ConstructionZone>[];
    final first =
        (math.max(0.0, fromDistance) / geometrySegmentLength).floor();
    final last =
        (math.max(0.0, toDistance) / geometrySegmentLength).floor();
    for (var i = first; i <= last; i++) {
      final zone = constructionForSegment(i);
      if (zone != null && zone.overlaps(fromDistance, toDistance)) {
        zones.add(zone);
      }
    }
    return zones;
  }

  /// The zone built in geometry segment [index], if that segment rolls
  /// one. Pure: the same index always builds the same zone.
  ConstructionZone? constructionForSegment(int index) {
    if (index < 2) return null; // the calm open
    final ramp =
        DifficultyCurve.rampFractionFor(index * geometrySegmentLength);
    if (hash01(seed, 0xC0E, index) >= 0.20 + 0.30 * ramp) return null;

    final layout = profileForSegment(index);
    final segmentStart = index * geometrySegmentLength;

    // Cones sit along one lane boundary; the lanes beyond it (the closed
    // side) are out of service. Never the outermost boundary — the kerb
    // side stays open for the passenger that may be waiting there.
    final roll = hash01(seed, 0xB0A, index);
    final boundaryIndex = 1 + (roll * (layout.laneCount - 1)).floor();
    final closedRight = hash01(seed, 0x51DE, index) < 0.5;

    var start = segmentStart + 300.0;
    var end = start +
        600.0 +
        500.0 * hash01(seed, 0x2E1, index); // 600-1100 px of cones
    end = math.min(end, segmentStart + geometrySegmentLength - 250.0);

    // Keep the works clear of the nearest cross street: the junction
    // stays fully open, and a cone line never ends mid-intersection.
    final nearest = (segmentStart + geometrySegmentLength / 2)
        .roundToNearestIntersection;
    const clearOf = intersectionHalfBand + 220.0;
    final nearStart = (nearest - start).abs() < clearOf;
    final nearEnd = (nearest - end).abs() < clearOf;
    final spansIt = nearest > start && nearest < end;
    if (nearStart || nearEnd || spansIt) {
      final beforeEnd = nearest - clearOf;
      if (beforeEnd - start >= 500.0) {
        end = beforeEnd;
      } else {
        return null;
      }
    }

    return ConstructionZone(
      startDistance: start,
      endDistance: end,
      boundaryFraction: boundaryIndex / layout.laneCount,
      closedRight: closedRight,
    );
  }

  /// Whether the lane whose centre is [laneX] is closed by cones at
  /// [distance] — what the spawner consults so traffic never materialises
  /// inside a work zone.
  bool isLaneBlockedAt(double distance, double laneX) {
    final zone = constructionAt(distance);
    if (zone == null) return false;
    final road = roadAt(distance);
    final fraction = (laneX - road.leftX) / road.width;
    return zone.closedRight
        ? fraction > zone.boundaryFraction + 0.05
        : fraction < zone.boundaryFraction - 0.05;
  }

  // --- Intersections ------------------------------------------------------

  /// Whether [distance] sits inside an intersection band: a cross street
  /// crossing the road. Traffic never spawns inside one — the junction is
  /// working for its living — so every crossing reads as a brief clear
  /// patch of city. The first junction lands one full spacing out; the
  /// start line does not sit in a phantom one.
  bool isIntersectionAt(double distance) {
    final d = math.max(0.0, distance);
    if (d < intersectionSpacing) return false;
    return d % intersectionSpacing < intersectionHalfBand * 2;
  }

  // --- Determinism --------------------------------------------------------

  /// SplitMix64-style mixing, as [EndlessCourse] uses: (seed, salt, index)
  /// triples land on independent, uniformly spread draws. Dart VM ints are
  /// 64-bit and wrap on overflow, so this is fully deterministic.
  static int _mix64(int x) {
    x = (x ^ (x >> 30)) * 0xBF58476D1CE4E5B9;
    x = (x ^ (x >> 27)) * 0x94D049BB133111EB;
    return x ^ (x >> 31);
  }

  /// One uniform draw in [0, 1) for the (seed, salt, index) triple.
  static double hash01(int seed, int salt, int index) =>
      (_mix64(seed * 0x9E3779B97F4A7C15 + salt * 0x100000001B3 + index) &
              0x7FFFFFFFFFFFFFFF) /
      0x7FFFFFFFFFFFFFFF;

  static double _smoothstep(double t) {
    final c = t.clamp(0.0, 1.0).toDouble();
    return c * c * (3 - 2 * c);
  }

  /// The road's fixed centre line — the same x [TaxiGame] and
  /// [DifficultyCurve] anchor everything to. Kept local so this file stays
  /// importable from pure logic without dragging the game in.
  static const double roadCenterX = 200.0;
}

/// Distance helpers for the segment math above.
extension _IntersectionDistance on double {
  /// The centre of the intersection band nearest this distance.
  double get roundToNearestIntersection =>
      (this / RunEnvironment.intersectionSpacing).round() *
      RunEnvironment.intersectionSpacing;
}
