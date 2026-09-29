import 'dart:math' as math;

import 'package:flame/components.dart';

/// How a player–traffic contact is judged (issue #6).
///
/// The pre-#6 rule failed the level on *any* contact at *any* speed. The
/// fair rule judges the physics of the touch: how fast the two vehicles
/// were closing along the impact axis. A gentle, glancing touch is a
/// scrape; a fast approach is a crash.
enum ContactSeverity {
  /// Low-speed glancing contact: the player is slowed, nothing is lost.
  scrape,

  /// A real collision: the run ends.
  crash,
}

/// Everything needed to explain a single player–traffic contact after the
/// fact ("a recorded crash can be explained frame by frame").
class CrashReport {
  CrashReport({
    required this.severity,
    required this.vehicleKind,
    required this.playerSpeed,
    required this.trafficSpeed,
    required this.closingSpeed,
    required this.closingSpeedAlongImpact,
    required this.playerPosition,
    required this.trafficPosition,
    required this.contactPoint,
  });

  /// Whether this contact was judged a scrape or a crash.
  final ContactSeverity severity;

  /// Which traffic vehicle took part ('sedan', 'bus', ...).
  final String vehicleKind;

  /// |player velocity| in px/s at the moment of contact.
  final double playerSpeed;

  /// |traffic velocity| in px/s at the moment of contact.
  final double trafficSpeed;

  /// |player velocity − traffic velocity| in px/s.
  final double closingSpeed;

  /// The component of the closing velocity along the impact axis
  /// (traffic centre → player centre). This is the number the severity
  /// rule is judged on.
  final double closingSpeedAlongImpact;

  final Vector2 playerPosition;
  final Vector2 trafficPosition;
  final Vector2 contactPoint;

  /// The one-line, player-facing version of the contact: what was hit and
  /// how hard, in words. The overlays show this; [explanation] stays the
  /// telemetry version for logs — a kid on the CRASH! screen needs "you
  /// hit the bus flat out", not px/s and world coordinates.
  String get headline {
    // Player top speed is 150 px/s (see CollisionRules above), so the
    // words sit on that scale: flat out, merely fast, or barely moving.
    final speedWord = playerSpeed >= 130
        ? 'flat out'
        : playerSpeed >= 70
            ? 'at speed'
            : '';
    final how = speedWord.isEmpty ? '' : ' $speedWord';
    switch (severity) {
      case ContactSeverity.crash:
        return 'You hit the $vehicleKind$how.';
      case ContactSeverity.scrape:
        return 'You scraped the $vehicleKind — slower now, nothing lost.';
    }
  }

  /// One-line, self-contained explanation of the contact.
  String get explanation {
    final axis = closingSpeedAlongImpact.toStringAsFixed(1);
    final total = closingSpeed.toStringAsFixed(1);
    final mine = playerSpeed.toStringAsFixed(1);
    final theirs = trafficSpeed.toStringAsFixed(1);
    final at =
        '(${contactPoint.x.toStringAsFixed(1)}, ${contactPoint.y.toStringAsFixed(1)})';
    switch (severity) {
      case ContactSeverity.crash:
        return 'Crashed into a $vehicleKind — $axis px/s along the impact '
            'axis (≥ ${CollisionRules.scrapeSpeedThreshold.toStringAsFixed(0)} '
            'crash threshold), $total px/s total closing speed '
            '(taxi $mine, $vehicleKind $theirs), contact at $at.';
      case ContactSeverity.scrape:
        return 'Scraped a $vehicleKind — $axis px/s along the impact axis, '
            'under the ${CollisionRules.scrapeSpeedThreshold.toStringAsFixed(0)} '
            'px/s crash threshold; taxi slowed to '
            '${(CollisionRules.scrapeSpeedKeep * 100).toStringAsFixed(0)}%. '
            'Contact at $at.';
    }
  }
}

/// Result of the danger telegraph check for one traffic vehicle.
class DangerAssessment {
  const DangerAssessment({
    required this.isDangerous,
    required this.timeToImpact,
    required this.closingSpeed,
  });

  /// Assessment of a vehicle that is not currently a threat.
  const DangerAssessment.safe()
      : isDangerous = false,
        timeToImpact = double.infinity,
        closingSpeed = 0;

  /// True when the player is on course to hit this vehicle within
  /// [CollisionRules.warningLeadTime].
  final bool isDangerous;

  /// Seconds until impact if both vehicles keep their current velocity.
  /// [double.infinity] when they are not closing.
  final double timeToImpact;

  /// |player velocity − traffic velocity| in px/s.
  final double closingSpeed;
}

/// Pure collision-fairness rules for player–traffic contacts (issue #6).
///
/// No Flame component logic lives here so every number can be unit tested.
class CollisionRules {
  CollisionRules._();

  /// Player hitbox, as a fraction of the logical vehicle box. Tightened
  /// from 0.90 in the player's favour: the drawn art no longer kills.
  static const double playerHitboxScale = 0.75;

  /// Traffic hitbox, as a fraction of the logical vehicle box. Tightened
  /// from 0.85 in the player's favour.
  static const double trafficHitboxScale = 0.80;

  /// Closing speed (px/s) along the impact axis at or above which a
  /// contact is a crash instead of a scrape. Player top speed is 150;
  /// overtaking same-direction traffic closes at 70–130 px/s, so ordinary
  /// overtakes that brush a car stay scrapes while head-on contacts
  /// (typically 200–300 px/s closing) are always crashes.
  static const double scrapeSpeedThreshold = 110.0;

  /// Fraction of velocity the player keeps after a scrape.
  static const double scrapeSpeedKeep = 0.35;

  /// How far (px) the player is pushed out of overlap after a scrape, along
  /// the impact axis, away from the traffic vehicle.
  static const double scrapePushback = 3.0;

  /// A traffic vehicle shows its warning state when impact would occur
  /// within this many seconds at current velocities.
  static const double warningLeadTime = 1.1;

  /// Unit vector pointing from [trafficPosition] to [playerPosition] — the
  /// axis the closing speed is measured along. Falls back to a head-on
  /// axis when the two centres coincide.
  static Vector2 impactAxis(Vector2 playerPosition, Vector2 trafficPosition) {
    final axis = playerPosition - trafficPosition;
    final length = axis.length;
    if (length < 0.001) return Vector2(0, -1);
    return axis / length;
  }

  /// How fast the player is moving *into* the traffic vehicle, in px/s.
  /// Positive numbers only: 0 when the vehicles are separating.
  static double approachSpeed({
    required Vector2 playerVelocity,
    required Vector2 trafficVelocity,
    required Vector2 impactAxis,
  }) {
    final relative = playerVelocity - trafficVelocity;
    return math.max(0.0, -relative.dot(impactAxis));
  }

  /// The severity ruling for a contact closing at [approachSpeed] px/s.
  static ContactSeverity severityFor(double approachSpeed) =>
      approachSpeed >= scrapeSpeedThreshold
          ? ContactSeverity.crash
          : ContactSeverity.scrape;

  /// Judges whether a traffic vehicle must telegraph danger right now.
  ///
  /// Dangerous when all of the following hold:
  ///  - the vehicle is ahead of the player (up the screen; the player only
  ///    travels toward decreasing y and traffic spawns ahead),
  ///  - their boxes overlap horizontally at the current x positions,
  ///  - they are closing, and would touch within [warningLeadTime].
  static DangerAssessment assessDanger({
    required Vector2 playerPosition,
    required Vector2 playerVelocity,
    required Vector2 playerSize,
    required Vector2 vehiclePosition,
    required Vector2 vehicleVelocity,
    required Vector2 vehicleSize,
  }) {
    final separation = playerPosition - vehiclePosition;

    // Only warn about vehicles ahead of the player (vehicle above on
    // screen, i.e. smaller y). Anything the player already passed is not
    // the danger to telegraph.
    if (separation.y <= 0) return const DangerAssessment.safe();

    // Horizontally aligned enough that the boxes can meet.
    final alignmentWindow = (playerSize.x + vehicleSize.x) / 2;
    if (separation.x.abs() >= alignmentWindow) {
      return const DangerAssessment.safe();
    }

    final relative = playerVelocity - vehicleVelocity;
    final closingSpeed = relative.length;

    // Gap shrinks only while the relative y velocity is negative (the
    // player moving up relative to the vehicle).
    final gapClosingRate = -relative.y;
    if (gapClosingRate <= 0) return const DangerAssessment.safe();

    final timeToImpact = separation.y / gapClosingRate;
    if (timeToImpact > warningLeadTime) return const DangerAssessment.safe();

    return DangerAssessment(
      isDangerous: true,
      timeToImpact: timeToImpact,
      closingSpeed: closingSpeed,
    );
  }

  /// Assembles the full telemetry record for a contact.
  static CrashReport buildReport({
    required ContactSeverity severity,
    required String vehicleKind,
    required Vector2 playerVelocity,
    required Vector2 playerPosition,
    required Vector2 trafficVelocity,
    required Vector2 trafficPosition,
    required Vector2 contactPoint,
  }) {
    final axis = impactAxis(playerPosition, trafficPosition);
    return CrashReport(
      severity: severity,
      vehicleKind: vehicleKind,
      playerSpeed: playerVelocity.length,
      trafficSpeed: trafficVelocity.length,
      closingSpeed: (playerVelocity - trafficVelocity).length,
      closingSpeedAlongImpact: approachSpeed(
        playerVelocity: playerVelocity,
        trafficVelocity: trafficVelocity,
        impactAxis: axis,
      ),
      playerPosition: playerPosition.clone(),
      trafficPosition: trafficPosition.clone(),
      contactPoint: contactPoint.clone(),
    );
  }
}
