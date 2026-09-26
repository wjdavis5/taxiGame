import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Tuning constants and pure math for impact juice (issue #7): screen
/// shake, hit-stop, and speed-line intensity. No Flame component logic
/// lives here so every number can be unit tested.
class ImpactFx {
  ImpactFx._();

  /// Closing speed (px/s) at which crash shake reaches full magnitude.
  /// Head-on contacts close at 200–300 px/s while brushed overtakes stay
  /// under the 110 px/s crash threshold (see [CollisionRules]).
  static const double fullShakeClosingSpeed = 260.0;

  /// Shake magnitude (px) for a crash at [fullShakeClosingSpeed] or above.
  static const double crashShakeMagnitude = 13.0;

  /// Shake magnitude (px) for a scrape — a small jolt so a graze still
  /// reads as metal-on-metal without drowning out the crash feedback.
  static const double scrapeShakeMagnitude = 3.0;

  /// How long a crash shake decays, in seconds.
  static const double crashShakeDuration = 0.35;

  /// How long a scrape shake decays, in seconds.
  static const double scrapeShakeDuration = 0.18;

  /// The crash hit-stop: the world freezes for this long at the moment of
  /// impact so the hit lands before the failure overlay explains it.
  static const double crashHitStopDuration = 0.10;

  /// Forward speed (px/s) at which speed lines start to appear. The fleet
  /// tops out between 132 and 188 px/s (`VehicleStats.topSpeed`, issue #9),
  /// so a slow car at full throttle only reaches partial intensity while a
  /// fast one pins the effect — the windshield itself reads the handling.
  static const double speedLinesStartSpeed = 95.0;

  /// Forward speed (px/s) at which speed lines reach full intensity. Faster
  /// cars (and only faster cars) get there at full throttle.
  static const double speedLinesFullSpeed = 150.0;

  /// Shake magnitude (px) for a crash closing at [closingSpeed] px/s:
  /// scaled linearly from zero up to [crashShakeMagnitude] at
  /// [fullShakeClosingSpeed], clamped beyond it — bigger impacts shake
  /// harder (issue #7 "scaled to impact speed").
  static double crashShakeMagnitudeFor(double closingSpeed) {
    final t = (closingSpeed / fullShakeClosingSpeed).clamp(0.0, 1.0);
    return crashShakeMagnitude * t;
  }

  /// 0..1 speed-line intensity for a forward [speed] in px/s: zero at or
  /// below [speedLinesStartSpeed], one at or above [speedLinesFullSpeed].
  static double speedLineIntensityFor(double speed) {
    const span = speedLinesFullSpeed - speedLinesStartSpeed;
    final t = (speed - speedLinesStartSpeed) / span;
    return t.clamp(0.0, 1.0);
  }
}

/// Particle palettes for the one-shot bursts, one per feedback kind, so
/// every scoring or failing event has a colour it cannot be confused with.
class ImpactFxPalettes {
  ImpactFxPalettes._();

  /// A passenger boarded: green, the pickup zone's colour.
  static const List<Color> pickup = [
    Color(0xFF4CAF50),
    Color(0xFF81C784),
    Color(0xFFC8E6C9),
    Color(0xFFFFFFFF),
  ];

  /// A fare delivered: blue like the dropoff zone with gold flecks for the
  /// money changing hands.
  static const List<Color> dropoff = [
    Color(0xFF2196F3),
    Color(0xFF64B5F6),
    Color(0xFFFFD54F),
    Color(0xFFFFFFFF),
  ];

  /// A crash: hot sparks — orange, amber, white.
  static const List<Color> crash = [
    Color(0xFFFF7043),
    Color(0xFFFFCA28),
    Color(0xFFFFE082),
    Color(0xFFFFFFFF),
  ];

  /// A scrape: a brief shower of yellow sparks.
  static const List<Color> scrape = [
    Color(0xFFFFD54F),
    Color(0xFFFFE082),
    Color(0xFFFFFFFF),
  ];
}

/// Decaying random screen-shake envelope.
///
/// [trigger] starts (or restarts) a shake of a given magnitude; every
/// [update] returns the camera offset to apply for that frame, shrinking
/// linearly to zero over the shake's duration. The random source is
/// injectable so tests can make offsets deterministic.
class ShakeEnvelope {
  ShakeEnvelope({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;

  double _magnitude = 0;
  double _duration = 0;
  double _age = 0;

  /// Magnitude the current shake started with (px); 0 when idle.
  double get magnitude => _magnitude;

  /// True while the shake has not yet decayed to zero.
  bool get isActive => _magnitude > 0 && _age < _duration;

  /// Starts a shake of [magnitude] px decaying over [duration] seconds.
  /// A shake already in progress is replaced.
  void trigger(
    double magnitude, {
    double duration = ImpactFx.crashShakeDuration,
  }) {
    if (magnitude <= 0) return;
    _magnitude = magnitude;
    _duration = duration;
    _age = 0;
  }

  /// Returns the envelope to its idle state.
  void reset() {
    _magnitude = 0;
    _duration = 0;
    _age = 0;
  }

  /// Advances the envelope and returns the offset (px) to apply this
  /// frame. Zero once the shake has fully decayed.
  Vector2 update(double dt) {
    if (!isActive) {
      reset();
      return Vector2.zero();
    }
    _age += dt;
    final remaining = (1 - _age / _duration).clamp(0.0, 1.0);
    final strength = _magnitude * remaining;
    if (strength <= 0) {
      reset();
      return Vector2.zero();
    }
    final angle = _random.nextDouble() * 2 * math.pi;
    final length = strength * _random.nextDouble();
    return Vector2(math.cos(angle) * length, math.sin(angle) * length);
  }
}

/// A brief full-world freeze at a crash: the frame holds still for a beat
/// so the impact lands before anything else moves.
class HitStop {
  /// Seconds of freeze left; 0 when inactive.
  double remaining = 0;

  bool get isActive => remaining > 0;

  /// Begins (or restarts) the freeze.
  void trigger([double duration = ImpactFx.crashHitStopDuration]) {
    remaining = duration;
  }

  /// Returns the freeze to its inactive state.
  void reset() {
    remaining = 0;
  }

  /// Burns [dt] seconds off the freeze.
  void update(double dt) {
    if (remaining > 0) {
      remaining = math.max(0.0, remaining - dt);
    }
  }
}
