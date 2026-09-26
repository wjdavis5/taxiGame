import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/run_length_simulator.dart';

/// The Monte-Carlo run-length estimate behind issue #18's tuning.
///
/// The game is fully offline — no analytics — and issue #17's on-device
/// stats screen has no real history yet, so the difficulty curve is tuned
/// against this headless simulator instead: the same difficulty curve, the
/// same vehicle stats and collision rules the live game runs, driven by a
/// reflex driver with human reaction lag, a small error rate, and the fare
/// stops that keep a real player from crawling. See the simulator's doc
/// comment for what it models and what it deliberately omits.
///
/// **The deliberate target band: a median shift of 2-4 km** (20,000-40,000
/// px) — the middle bucket of the stats screen's run-length distribution,
/// roughly three to six minutes of driving. Around it, the fairness
/// profile: the opening kilometre is nearly death-free (an early death
/// should be a mistake, not luck), pressure builds through the middle
/// kilometres, roughly one shift in six stretches past 4 km (strong play,
/// and the wave's relief lulls, are rewarded), and nobody outruns the
/// curve forever. When TestFlight players eventually fill the on-device
/// history, the real median is the ground truth this estimate is
/// re-checked against — the numbers here are the pre-device prior, not a
/// substitute for it.
void main() {
  // 101 seeds: odd, so the median is an actual run; large enough that the
  // batch proportions are stable well inside every threshold below. The
  // full batch simulates in well under a second.
  const firstSeed = 1000;
  const runCount = 101;

  late RunLengthEstimate estimate;

  setUpAll(() {
    final runs = <SimulatedRun>[
      for (var seed = firstSeed; seed < firstSeed + runCount; seed++)
        RunLengthSimulator(seed: seed).run(),
    ];
    estimate = RunLengthEstimate.compute(runs);
  });

  group('the simulated median shift', () {
    test('lands in the deliberately chosen 2-4 km target band', () {
      final medianKm = estimate.medianDistancePx / 10000;
      expect(medianKm, greaterThanOrEqualTo(2.0),
          reason: 'median $medianKm km: shifts must have room to breathe');
      expect(medianKm, lessThanOrEqualTo(4.0),
          reason: 'median $medianKm km: the curve must bite within a '
              'session, not eventually');
    });
  });

  group('death feels earned at every distance', () {
    test('the opening kilometre is nearly death-free', () {
      // An early death must be a mistake, not luck. The sim driver errs
      // and still almost never dies here.
      expect(estimate.deathFractionWithin(10000), lessThanOrEqualTo(0.05));
    });

    test('pressure builds through the middle kilometres', () {
      expect(estimate.survivalFractionBeyond(20000), greaterThanOrEqualTo(0.85),
          reason: 'a 2 km shift must be the ordinary case');
      expect(estimate.survivalFractionBeyond(30000), greaterThanOrEqualTo(0.55),
          reason: 'most shifts should reach 3 km before the curve bites '
              'hard');
    });

    test('strong play is rewarded, and nobody outruns the curve forever',
        () {
      final past4km = estimate.survivalFractionBeyond(40000);
      expect(past4km, greaterThanOrEqualTo(0.08),
          reason: 'roughly one shift in six should stretch past 4 km');
      expect(past4km, lessThanOrEqualTo(0.40),
          reason: '4 km must stay an achievement, not the default');
      expect(estimate.survivalFractionBeyond(50000), lessThanOrEqualTo(0.05),
          reason: 'a fixed-skill driver cannot outrun the curve forever');
    });

    test('deaths are progressive: no premature wall on the road', () {
      // The deep game is allowed to be near-certain — the curve must bite
      // within a session — but nothing before it may wall a competent
      // driver: inside the target band the death rate per kilometre stays
      // survivable, and only the far side of the band approaches
      // certainty. (Windows with fewer than 8 alive are too thin to judge
      // a rate by; a single death swings them wildly.)
      for (final window in estimate.hazardWindows(windowPx: 10000)) {
        if (window.aliveAtStart < 8) continue;
        final km = window.startPx ~/ 10000;
        if (km < 2) {
          expect(window.deathRate, lessThanOrEqualTo(0.35),
              reason: 'death rate in the $km-${km + 1} km window — the '
                  'opening must stay forgiving');
        } else if (km < 3) {
          expect(window.deathRate, lessThanOrEqualTo(0.60),
              reason: 'death rate in the $km-${km + 1} km window — mid-band '
                  'pressure squeezes without snapping shut');
        } else if (km < 4) {
          expect(window.deathRate, lessThanOrEqualTo(0.85),
              reason: 'death rate in the $km-${km + 1} km window');
        }
      }
    });
  });

  group('the harness itself', () {
    test('is deterministic: same seed, same shift', () {
      const seed = 4242;
      final a = RunLengthSimulator(seed: seed).run();
      final b = RunLengthSimulator(seed: seed).run();
      expect(b.distancePx, a.distancePx);
      expect(b.drivenSeconds, a.drivenSeconds);
      expect(b.crashDistancesPx, a.crashDistancesPx);
      expect(b.survived, a.survived);
    });

    test('different seeds give different shifts', () {
      final a = RunLengthSimulator(seed: 7).run();
      final b = RunLengthSimulator(seed: 8).run();
      final differs = a.distancePx != b.distancePx ||
          a.crashDistancesPx.length != b.crashDistancesPx.length;
      expect(differs, isTrue);
    });

    test('every recorded crash lands inside its run', () {
      for (final run in estimate.runs) {
        for (final crash in run.crashDistancesPx) {
          expect(crash, lessThanOrEqualTo(run.distancePx + 1e-6));
          expect(crash, greaterThanOrEqualTo(0.0));
        }
        // A non-surviving run died to exactly three crashes; the failure
        // budget is the whole death mechanic.
        if (!run.survived) {
          expect(run.crashDistancesPx, hasLength(3));
        }
      }
    });

    test('RunLengthEstimate computes the median of its input', () {
      final odd = RunLengthEstimate.compute([
        for (var i = 0; i < 5; i++)
          SimulatedRun(
            seed: i,
            distancePx: (5 - i) * 1000.0,
            drivenSeconds: 1,
            crashDistancesPx: const [],
            survived: false,
          ),
      ]);
      expect(odd.medianDistancePx, 3000.0);

      final even = RunLengthEstimate.compute([
        for (var i = 0; i < 4; i++)
          SimulatedRun(
            seed: i,
            distancePx: (i + 1) * 1000.0,
            drivenSeconds: 1,
            crashDistancesPx: const [],
            survived: false,
          ),
      ]);
      expect(even.medianDistancePx, 2500.0);
    });
  });
}
