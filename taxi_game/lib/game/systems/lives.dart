import 'dart:math' as math;

/// The shift's failure budget (issue #14): three lives, one spent per
/// crash. An endless run absorbs the first two crashes — each one costs a
/// life and breaks the fare chain — and the third ends the shift with
/// everything unbanked forfeit. The budget is what makes a long unbanked
/// run a gamble instead of a coin flip on a single mistake.
///
/// Pure logic — no Flame state — so the budget's rules are unit testable,
/// matching [FareChain] and [BankPrompt].
class LivesTracker {
  /// Lives a shift starts with. Three strikes.
  static const int maxLives = 3;

  int _remaining = maxLives;

  /// Lives left in the current shift.
  int get remaining => _remaining;

  /// True when the budget is spent and the shift is over.
  bool get isExhausted => _remaining <= 0;

  /// True when the life in play is the last one: the next crash ends the
  /// shift. The HUD could read [remaining] for this, but the rule reads
  /// better where it is used.
  bool get isLastLife => _remaining == 1;

  /// Spends one life and returns how many are left. Floors at zero so a
  /// double ruling in one frame cannot drive it negative.
  int spend() {
    _remaining = math.max(0, _remaining - 1);
    return _remaining;
  }

  /// Refills the budget for a fresh shift. [lives] is the budget to refill
  /// to — the gauntlet's one-life weeks (issue #288) start a run on a
  /// smaller budget — defaulting to the standard [maxLives].
  void reset({int lives = maxLives}) {
    _remaining = math.max(1, lives);
  }
}
