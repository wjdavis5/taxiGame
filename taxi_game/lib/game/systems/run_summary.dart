/// The settled record of an endless shift that has ended (issue #15) —
/// the numbers the run-summary panel shows. Snapshotted the instant the
/// shift ends, so the panel reads final numbers even though the game
/// object it hangs off keeps living (the retry starts a new shift that
/// resets everything these fields were read from).
///
/// Pure data — no Flame state — so the formatting and the fields are unit
/// testable, matching [FareChain] and [LivesTracker].
class RunSummary {
  const RunSummary({
    required this.outcome,
    required this.score,
    required this.bestChain,
    required this.faresDelivered,
    required this.distancePx,
    required this.coinsEarned,
    required this.isPersonalBest,
    required this.previousBest,
  });

  /// How the shift ended: paid out at a bank, or wrecked on the third
  /// crash. Drives the panel's title, colour, and forfeit line.
  final ShiftOutcome outcome;

  /// The run's final fare-chain score. For a banked shift this is exactly
  /// what the bank paid out; for a wrecked one it is what died unbanked.
  final int score;

  /// The highest the chain multiplier reached — the run's best chain.
  final int bestChain;

  /// Fares delivered over the whole shift.
  final int faresDelivered;

  /// How far the taxi drove, in world px — raw material for
  /// [distanceLabel].
  final double distancePx;

  /// Coins actually credited to the wallet during the run: each delivered
  /// fare's base reward, plus the banked payout for a banked shift.
  final int coinsEarned;

  /// True when [score] beat the personal best as it stood before this
  /// shift — this run set a new one.
  final bool isPersonalBest;

  /// The personal best before this shift ran, so the summary can show the
  /// number that was (or wasn't) beaten.
  final int previousBest;

  /// World px to metres — the same scale the HUD's distance badge uses.
  static const double pixelsPerMetre = 10.0;

  /// The distance in race-telemetry units: metres under a kilometre,
  /// kilometres above.
  String get distanceLabel {
    final metres = distancePx / pixelsPerMetre;
    return metres >= 1000
        ? '${(metres / 1000).toStringAsFixed(1)} km'
        : '${metres.round()} m';
  }
}

/// How an endless shift ended.
enum ShiftOutcome {
  /// The player banked at a dropoff: the score paid out 1:1 in coins.
  banked,

  /// The third crash ended the shift: the score died unbanked.
  wrecked,
}
