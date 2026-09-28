import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:provider/provider.dart';

/// Haptic feedback for the game (issue #5), on top of `HapticFeedback`.
///
/// On a one-thumb game whose only input is hold-and-steer, the buzz
/// carries a disproportionate share of the feel, so every impact the
/// player causes or suffers is confirmed in the hand: a crash lands
/// heavy, a fare boarding or paying lands medium, a coin award or a
/// button press lands light.
///
/// **Every platform call is swallowed on failure.** The service must
/// never crash the game — under `flutter test` there is no vibration
/// plugin at all, and on a device a failed buzz must cost nothing but
/// the feel. Tests observe the service through [attemptedBuzzes], which
/// records the impacts vibration was *attempted* for after the
/// enabled-gate has run.
class HapticsService {
  bool _enabled = true;

  /// Whether vibration currently fires. Synced from the save's
  /// `Settings.vibrationEnabled` at startup and on every settings toggle
  /// by the composition root in `main.dart` — the same live wiring the
  /// audio flags (issue #4) ride.
  @visibleForTesting
  bool get enabled => _enabled;

  /// Set vibration enabled/disabled. The gate is checked at fire time, so
  /// a toggle mid-shift takes effect on the very next impact.
  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// The impacts vibration was attempted for, since construction
  /// (issue #5). Gated calls never register — tests assert against this
  /// to check the enabled-gate without a platform plugin. The key names
  /// the event and its intensity class.
  @visibleForTesting
  final Map<String, int> attemptedBuzzes = <String, int>{};

  // --- semantic impacts -------------------------------------------------------

  /// A judged crash: the heaviest buzz the phone has.
  void crash() => _fire('crash_heavy', HapticFeedback.heavyImpact);

  /// A passenger boarded: a solid, shortened thud.
  void pickup() => _fire('pickup_medium', HapticFeedback.mediumImpact);

  /// A fare paid: the twin of [pickup].
  void dropoff() => _fire('dropoff_medium', HapticFeedback.mediumImpact);

  /// A coin award (the level-completion payout): a light tick.
  void coinAward() => _fire('coin_light', HapticFeedback.lightImpact);

  /// A UI button press: the lightest tick, so menus feel respond without
  /// drowning the gameplay impacts.
  void buttonPress() => _fire('button_light', HapticFeedback.lightImpact);

  void _fire(String name, Future<void> Function() buzz) {
    if (!_enabled) return;
    attemptedBuzzes.update(name, (n) => n + 1, ifAbsent: () => 1);
    unawaited(() async {
      try {
        await buzz();
      } catch (_) {}
    }());
  }
}

/// Best-effort read of the [HapticsService] above [context]: null when no
/// provider is there (headless widget tests, the screenshot entry point).
/// UI buzzes are dressing — a missing provider must never break a button.
HapticsService? hapticsOf(BuildContext context) {
  try {
    return context.read<HapticsService>();
  } on ProviderNotFoundException {
    return null;
  }
}
