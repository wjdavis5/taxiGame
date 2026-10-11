import '../game/systems/run_environment.dart';
import '../game/systems/run_summary.dart';

/// The City License board (issue #278): the post-tutorial challenge board.
///
/// After the ten-rung ladder and the garage's fleet, progression used to
/// exhaust — nothing named a replayable objective. This board is a fixed,
/// hand-authored set of named objectives over the systems the game already
/// has: banking, close calls, fare kinds (issue #279's contracts), weather
/// (issue #24's environment), and vehicle tradeoffs (issue #9's handling
/// axes). Every entry is a real rule a finished shift can meet, every entry
/// can be attempted again after it is met, and completion lives in the save.
///
/// Pure logic — no service, no storage, no widget — so each rule is unit
/// testable and the board cannot drift from what the run record carries.
/// Nothing here is fetched: the weather a rule measures is computed from
/// the run's own seed, the same way the run itself drew it.
enum LicenseFamily {
  banking('BANKING'),
  closeCalls('CLOSE CALLS'),
  fareKinds('FARE KINDS'),
  weather('WEATHER'),
  vehicle('VEHICLE');

  const LicenseFamily(this.label);

  /// The section header the board renders for this family.
  final String label;
}

/// One ended shift, as the license rules read it (issue #278).
///
/// Built from the settled [RunRecord] plus the record's own seed and
/// vehicle — the two facts the weather and vehicle families need and the
/// old record did not carry. Everything else is a value the record already
/// held: the score and how the shift ended, the close-call count, the
/// fares delivered, and the per-kind contract answers (issue #279).
class LicenseRun {
  LicenseRun({
    required this.score,
    required this.banked,
    required this.livesLost,
    required this.nearMisses,
    required this.acceptedByKind,
    required this.vehicleId,
    required this.seed,
    required this.distancePx,
  });

  final int score;
  final bool banked;
  final int livesLost;
  final int nearMisses;

  /// Boarded fares by kind name — [FareType]'s stable names, the keys
  /// [RunRecord.acceptedByKind] stores (issue #279).
  final Map<String, int> acceptedByKind;

  final String vehicleId;

  /// The run's seed: the course, its sky, and its weather are pure
  /// functions of it (issue #24), so a finished run's weather exposure is
  /// recoverable from this and [distancePx] alone.
  final int seed;

  final double distancePx;

  /// How many fares of [fareKind] were boarded.
  int acceptedOf(String fareKind) => acceptedByKind[fareKind] ?? 0;

  /// The sampling step for weather exposure. 100 px = 10 m, so a measured
  /// stretch is accurate to one step either way — plenty for a 300 m bar.
  static const double weatherSampleStepPx = 100.0;

  /// A weather sample only counts as "in" its weather past this intensity:
  /// the segment fades at 0 intensity, and a light drizzle at the edge of
  /// a front is not the rain run the board names.
  static const double weatherMinIntensity = 0.3;

  double? _rainMetres;
  double? _fogMetres;
  double? _nightMetres;

  /// Metres of the driven span that sat in rain, sampled from the run's
  /// own environment — the same [RunEnvironment] the live world read.
  double get rainMetres => _rainMetres ??= _metresWhere(
        (env, d) => env.weatherAt(d).rainIntensity >= weatherMinIntensity,
      );

  /// Metres of the driven span that sat in fog.
  double get fogMetres => _fogMetres ??= _metresWhere(
        (env, d) => env.weatherAt(d).fogIntensity >= weatherMinIntensity,
      );

  /// Metres of the driven span that sat after dark, by the game's own
  /// time-of-day vocabulary ([TimeOfDay.night]).
  double get nightMetres => _nightMetres ??= _metresWhere(
        (env, d) => env.timeOfDayAt(d) == TimeOfDay.night,
      );

  double _metresWhere(
    bool Function(RunEnvironment env, double distance) test,
  ) {
    final env = RunEnvironment(seed: seed);
    var samples = 0;
    for (var d = 0.0; d < distancePx; d += weatherSampleStepPx) {
      if (test(env, d)) samples++;
    }
    return samples * weatherSampleStepPx / RunSummary.pixelsPerMetre;
  }
}

/// The board's entries (issue #278). Each value is one named objective:
/// its family, the title and ask the board renders, and the rule a shift
/// must satisfy to complete it.
///
/// The bar is the [threshold] field, and the rule switch reads that same
/// field, so the number on the card and the number enforced are one fact:
/// the tests pin every [brief] to name its [threshold] as a standalone
/// number token, so a re-tuned rule whose card still quotes the old number
/// — a truncation like 300 to 30 included — fails them.
enum LicenseRule {
  // Banking: the two ways a bank is a decision — clean, or big.
  cleanBank(LicenseFamily.banking, 'CLEAN BANK',
      'BANK A SHIFT WITH 0 CRASHES', threshold: 0),
  bigBank(LicenseFamily.banking, 'BIG BANK', 'BANK 4000+ IN ONE SHIFT',
      threshold: 4000),

  // Close calls: the near-miss economy (issue #23) as a named bar.
  tightThread(LicenseFamily.closeCalls, 'TIGHT THREAD',
      'CLEAR 8 CLOSE CALLS IN ONE SHIFT', threshold: 8),
  needleThread(LicenseFamily.closeCalls, 'NEEDLE THREAD',
      'CLEAR 15 CLOSE CALLS IN ONE SHIFT', threshold: 15),

  // Fare kinds: the merged contract vocabulary (issue #279). The counts
  // are boardings — an accepted contract is the decision the offer bar
  // asks, and the counts are what the record stores.
  vipRun(LicenseFamily.fareKinds, 'VIP RUN',
      'TAKE 2 VIP FARES IN ONE SHIFT', threshold: 2, fareKind: 'vip'),
  longHaulRun(LicenseFamily.fareKinds, 'LONG HAULER',
      'TAKE 2 LONG-HAUL FARES IN ONE SHIFT',
      threshold: 2, fareKind: 'longHaul'),
  farSideRun(LicenseFamily.fareKinds, 'FAR SIDE',
      'TAKE 3 FAR-SIDE FARES IN ONE SHIFT',
      threshold: 3, fareKind: 'awkward'),

  // Weather: the environment's own axes (issue #24), measured over the
  // span the shift actually drove.
  rainRun(LicenseFamily.weather, 'RAIN RUN', 'DRIVE 300 M IN THE RAIN',
      threshold: 300),
  fogRun(LicenseFamily.weather, 'FOG RUN', 'DRIVE 300 M IN FOG',
      threshold: 300),
  nightRun(LicenseFamily.weather, 'NIGHT SHIFT', 'DRIVE 300 M AFTER DARK',
      threshold: 300),

  // Vehicle tradeoffs: a car's handling character turned into a bar
  // (issue #9). The compact threads gaps; the Executive banks.
  compactThread(LicenseFamily.vehicle, 'COMPACT PRECISION',
      'CLEAR 8 CLOSE CALLS IN THE CITY COMPACT',
      threshold: 8, requiredVehicleId: 'compact_red'),
  executiveBank(LicenseFamily.vehicle, 'EXECUTIVE DISCIPLINE',
      'BANK 3000+ IN THE EXECUTIVE',
      threshold: 3000, requiredVehicleId: 'luxury_white');

  const LicenseRule(
    this.family,
    this.title,
    this.brief, {
    required this.threshold,
    this.requiredVehicleId,
    this.fareKind,
  });

  /// The stable id the save stores and the next-goal seam pins — the
  /// enum name, never a display string.
  String get id => name;

  final LicenseFamily family;

  /// Uppercase display name ('CLEAN BANK', 'VIP RUN').
  final String title;

  /// The ask, in the board's voice ('BANK 4000+ IN ONE SHIFT'). It names
  /// [threshold], and the tests hold it to that as a standalone number:
  /// containment alone would let a 300 m card pass a 30 m rule.
  final String brief;

  /// The bar this rule enforces, in the rule's own unit — crashes, coins,
  /// close calls, boarded fares, or metres. [isMet] reads this field, so
  /// the card's number is never a second copy of the rule.
  final int threshold;

  /// The car this objective must be driven in, for the vehicle family.
  final String? requiredVehicleId;

  /// The boarded fare kind this objective counts, for the fare-kinds
  /// family, named as [RunRecord.acceptedByKind] keys it.
  final String? fareKind;

  /// Whether a finished [run] completes this objective.
  bool isMet(LicenseRun run) => switch (this) {
        cleanBank => run.banked && run.livesLost <= threshold,
        bigBank => run.banked && run.score >= threshold,
        tightThread => run.nearMisses >= threshold,
        needleThread => run.nearMisses >= threshold,
        vipRun => run.acceptedOf(fareKind!) >= threshold,
        longHaulRun => run.acceptedOf(fareKind!) >= threshold,
        farSideRun => run.acceptedOf(fareKind!) >= threshold,
        rainRun => run.rainMetres >= threshold,
        fogRun => run.fogMetres >= threshold,
        nightRun => run.nightMetres >= threshold,
        compactThread =>
          run.vehicleId == requiredVehicleId && run.nearMisses >= threshold,
        executiveBank =>
          run.vehicleId == requiredVehicleId && run.banked && run.score >= threshold,
      };
}

/// The board itself (issue #278): the fixed list, the rules a run just
/// completed, and the next open objective for the next-goal seam.
class CityLicense {
  CityLicense._();

  /// Every objective, in board order — family sections in the order the
  /// families are declared.
  static const List<LicenseRule> board = LicenseRule.values;

  /// The objectives [run] completes. Completion is a fact about the run,
  /// never about the board: a completed objective still appears here on
  /// every later run that meets it again, which is what makes the board
  /// replayable rather than consumable.
  static List<LicenseRule> completedBy(LicenseRun run) =>
      [for (final rule in board) if (rule.isMet(run)) rule];

  /// The first objective in board order not present in [completedIds], or
  /// null once every one is complete.
  static LicenseRule? nextOpen(Set<String> completedIds) {
    for (final rule in board) {
      if (!completedIds.contains(rule.id)) return rule;
    }
    return null;
  }
}
