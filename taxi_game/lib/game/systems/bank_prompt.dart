import 'dart:math' as math;

/// What became of an offered bank-or-push choice (issue #13).
enum BankDecision {
  /// The player banked the score and ended the shift.
  banked,

  /// The player pushed on — either by choice or by letting the window run
  /// out. Riding on at the increased multiplier is the default, so the
  /// game never stops dead and a loss stays self-inflicted: banking is
  /// always a deliberate act.
  pushed,
}

/// The timed bank-or-push choice offered at every endless dropoff
/// (issue #13).
///
/// The prompt lives beside the running game, not on top of it: while it is
/// up the street keeps moving and countdowns keep ticking, and the player
/// can keep driving straight through it. The one exception is the primer —
/// a save's first-ever offer (TaxiGame owns the freeze), the single offer
/// that stops traffic so the choice can be read; every other offer rides
/// the live street for the window's full length, which is why the HUD's
/// ghost-gap readout stays up through it wherever the screen fits both
/// (issue #139). If [windowSeconds] pass without a choice the prompt
/// resolves to [BankDecision.pushed] — push is the default, so failing to
/// bank is a decision too.
///
/// Each resolution method returns the decision exactly once, so the game
/// can apply its consequences (pay out, step the multiplier) exactly once.
/// Pure logic — no Flame state — so the timing rules are unit testable.
class BankPrompt {
  /// How long the choice stays open, in seconds. Long enough to read the
  /// two options, short enough not to break flow.
  static const double windowSeconds = 5.0;

  bool _active = false;
  double _remainingSeconds = 0.0;

  /// True while the choice is on screen and the clock is running.
  bool get isActive => _active;

  /// Seconds left to choose.
  double get remainingSeconds => _remainingSeconds;

  /// Fraction (0..1) of the window still left — raw material for a bar.
  double get fractionRemaining =>
      windowSeconds <= 0 ? 0.0 : (_remainingSeconds / windowSeconds).clamp(0, 1);

  /// Offers the choice after a completed dropoff. Offering while a prompt
  /// is already up (a second fare delivered in quick succession) restarts
  /// the window — the freshest dropoff owns the decision.
  void offer() {
    _active = true;
    _remainingSeconds = windowSeconds;
  }

  /// Ticks the countdown while the game runs. Returns
  /// [BankDecision.pushed] exactly once if the window closes without a
  /// choice; null every other tick.
  BankDecision? update(double dt) {
    if (!_active) return null;

    _remainingSeconds = math.max(0.0, _remainingSeconds - dt);
    if (_remainingSeconds > 0.0) return null;

    _active = false;
    return BankDecision.pushed;
  }

  /// The player chose to bank. Returns [BankDecision.banked] exactly once;
  /// null when nothing was on offer.
  BankDecision? bank() => _resolve(BankDecision.banked);

  /// The player chose to push on. Returns [BankDecision.pushed] exactly
  /// once; null when nothing was on offer.
  BankDecision? push() => _resolve(BankDecision.pushed);

  /// Tears the prompt down without a decision — a crash or a restart
  /// supersedes it. No consequence is owed.
  void dismiss() {
    _active = false;
    _remainingSeconds = 0.0;
  }

  BankDecision? _resolve(BankDecision decision) {
    if (!_active) return null;
    _active = false;
    _remainingSeconds = 0.0;
    return decision;
  }
}
