import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/systems/collision_rules.dart';

void main() {
  group('severityFor', () {
    test('a gentle touch is a scrape', () {
      expect(
        CollisionRules.severityFor(
          CollisionRules.scrapeSpeedThreshold - 1,
          100,
        ),
        ContactSeverity.scrape,
      );
      expect(
        CollisionRules.severityFor(0, 0),
        ContactSeverity.scrape,
      );
    });

    test('closing at or above the threshold is a crash', () {
      expect(
        CollisionRules.severityFor(
          CollisionRules.scrapeSpeedThreshold,
          100,
        ),
        ContactSeverity.crash,
      );
      expect(
        CollisionRules.severityFor(
          CollisionRules.scrapeSpeedThreshold + 500,
          100,
        ),
        ContactSeverity.crash,
      );
    });

    test('a stationary cab struck over the threshold is a scrape (issue #58)',
        () {
      // The issue's log line, verbatim geometry: taxi 0.0, sportsCar 147.5
      // closing along the impact axis — over the 110 crash threshold, all
      // of it the striker's. The player contributed nothing, so nothing
      // can be ruled against them.
      expect(
        CollisionRules.severityFor(147.5, 0),
        ContactSeverity.scrape,
      );
      expect(
        CollisionRules.severityFor(
          CollisionRules.scrapeSpeedThreshold + 500,
          0,
        ),
        ContactSeverity.scrape,
      );
    });

    test('a cab driving away while struck is a scrape (issue #58)', () {
      // Rear-end of a slower cab: the player's own velocity points away
      // from the striker (negative contribution).
      expect(
        CollisionRules.severityFor(150, -40),
        ContactSeverity.scrape,
      );
    });

    test('any player share of the closing keeps the crash rule intact', () {
      // Even one px/s of player closing, over the threshold, is a crash:
      // the fault gate must not neuter real player-caused contacts.
      expect(
        CollisionRules.severityFor(CollisionRules.scrapeSpeedThreshold, 1),
        ContactSeverity.crash,
      );
    });
  });

  group('playerContribution', () {
    test('head-on driving counts the full player speed', () {
      // Player drives up (-y) into a vehicle above; the axis points
      // down-screen from the vehicle to the player.
      final contribution = CollisionRules.playerContribution(
        playerVelocity: Vector2(0, -150),
        impactAxis: Vector2(0, 1),
      );
      expect(contribution, 150);
    });

    test('a stationary cab contributes nothing', () {
      expect(
        CollisionRules.playerContribution(
          playerVelocity: Vector2.zero(),
          impactAxis: Vector2(0, 1),
        ),
        0,
      );
    });

    test('driving away from the striker is negative', () {
      // Player crawling up-screen away from a faster vehicle behind it:
      // the axis points up-screen (traffic → player), the player's
      // velocity along it is negative.
      final contribution = CollisionRules.playerContribution(
        playerVelocity: Vector2(0, -40),
        impactAxis: Vector2(0, -1),
      );
      expect(contribution, -40);
    });
  });

  group('approachSpeed', () {
    test('head-on closing adds the two speeds along the axis', () {
      // Player drives up (-y), traffic drives down (+y).
      final approach = CollisionRules.approachSpeed(
        playerVelocity: Vector2(0, -150),
        trafficVelocity: Vector2(0, 60),
        impactAxis: Vector2(0, 1),
      );
      expect(approach, 210);
    });

    test('separating vehicles have zero approach speed', () {
      final approach = CollisionRules.approachSpeed(
        playerVelocity: Vector2(0, 100), // player falling back
        trafficVelocity: Vector2(0, -50), // vehicle pulling away
        impactAxis: Vector2(0, 1),
      );
      expect(approach, 0);
    });

    test('motion parallel to the impact axis does not count', () {
      // Both drive the same direction at the same speed: no closing.
      final approach = CollisionRules.approachSpeed(
        playerVelocity: Vector2(0, -150),
        trafficVelocity: Vector2(0, -150),
        impactAxis: Vector2(0, 1),
      );
      expect(approach, 0);
    });

    test('only the component into the vehicle counts', () {
      // 3-4-5 triangle: 30 px/s of the player's 50 px/s motion points
      // along the impact axis.
      final approach = CollisionRules.approachSpeed(
        playerVelocity: Vector2(40, -30),
        trafficVelocity: Vector2.zero(),
        impactAxis: Vector2(0, 1),
      );
      expect(approach, 30);
    });
  });

  group('impactAxis', () {
    test('points from the traffic centre to the player centre', () {
      final axis = CollisionRules.impactAxis(
        Vector2(200, 100), // player
        Vector2(200, 40), // traffic above
      );
      expect(axis, Vector2(0, 1)); // straight down-screen
    });

    test('degenerate overlap falls back to a head-on axis', () {
      final axis = CollisionRules.impactAxis(
        Vector2(200, 100),
        Vector2(200, 100),
      );
      expect(axis, Vector2(0, -1));
    });
  });

  group('assessDanger', () {
    // Canonical player: centre of the road, flat out up the screen.
    Vector2 playerPos() => Vector2(200, 100);
    Vector2 playerVel() => Vector2(0, -150);

    test('an oncoming vehicle on a collision course is dangerous', () {
      final assessment = CollisionRules.assessDanger(
        playerPosition: playerPos(),
        playerVelocity: playerVel(),
        playerSize: Vector2(40, 60),
        vehiclePosition: Vector2(200, 40), // 60 px ahead
        vehicleVelocity: Vector2(0, 80), // oncoming
        vehicleSize: Vector2(40, 60),
      );

      expect(assessment.isDangerous, isTrue);
      // Closing at 230 px/s over a 60 px gap.
      expect(assessment.timeToImpact, closeTo(60 / 230, 1e-9));
      expect(assessment.closingSpeed, closeTo(230, 1e-9));
    });

    test('a slower vehicle ahead being overtaken is dangerous in time', () {
      final assessment = CollisionRules.assessDanger(
        playerPosition: playerPos(),
        playerVelocity: playerVel(),
        playerSize: Vector2(40, 60),
        vehiclePosition: Vector2(200, 20), // 80 px ahead
        vehicleVelocity: Vector2(0, -50), // same direction, slower
        vehicleSize: Vector2(40, 60),
      );

      expect(assessment.isDangerous, isTrue);
      expect(assessment.timeToImpact, closeTo(80 / 100, 1e-9));
    });

    test('a vehicle far ahead is not yet dangerous', () {
      final assessment = CollisionRules.assessDanger(
        playerPosition: playerPos(),
        playerVelocity: playerVel(),
        playerSize: Vector2(40, 60),
        vehiclePosition: Vector2(200, -250), // 350 px ahead
        vehicleVelocity: Vector2(0, 80),
        vehicleSize: Vector2(40, 60),
      );

      // 350 px gap at 230 px/s: about 1.5 s, beyond the lead time.
      expect(assessment.isDangerous, isFalse);
      expect(assessment.timeToImpact, greaterThan(1.1));
    });

    test('a vehicle in another lane is not dangerous', () {
      final assessment = CollisionRules.assessDanger(
        playerPosition: playerPos(),
        playerVelocity: playerVel(),
        playerSize: Vector2(40, 60),
        // Lanes are 120 px apart; the boxes sum to 40 px of half-widths.
        vehiclePosition: Vector2(260, 40),
        vehicleVelocity: Vector2(0, 80),
        vehicleSize: Vector2(40, 60),
      );

      expect(assessment.isDangerous, isFalse);
    });

    test('a vehicle the player has already passed is not dangerous', () {
      final assessment = CollisionRules.assessDanger(
        playerPosition: playerPos(),
        playerVelocity: playerVel(),
        playerSize: Vector2(40, 60),
        vehiclePosition: Vector2(200, 400), // behind the player
        vehicleVelocity: Vector2(0, 80),
        vehicleSize: Vector2(40, 60),
      );

      expect(assessment.isDangerous, isFalse);
    });

    test('a vehicle pulling away is not dangerous', () {
      final assessment = CollisionRules.assessDanger(
        playerPosition: playerPos(),
        playerVelocity: Vector2(0, -50), // player easing off
        playerSize: Vector2(40, 60),
        vehiclePosition: Vector2(200, 40),
        vehicleVelocity: Vector2(0, -150), // vehicle accelerating away
        vehicleSize: Vector2(40, 60),
      );

      expect(assessment.isDangerous, isFalse);
      expect(assessment.timeToImpact, double.infinity);
    });
  });

  group('buildReport / explanation', () {    test('a crash report records and explains the full contact', () {
      final report = CollisionRules.buildReport(
        severity: ContactSeverity.crash,
        vehicleKind: 'bus',
        playerVelocity: Vector2(0, -150),
        playerPosition: Vector2(200, 100),
        trafficVelocity: Vector2(0, 60),
        trafficPosition: Vector2(200, 40),
        contactPoint: Vector2(198.3, 70.2),
      );

      expect(report.playerSpeed, 150);
      expect(report.trafficSpeed, 60);
      expect(report.closingSpeed, 210);
      expect(report.closingSpeedAlongImpact, 210);
      // The player drove the full 150 into the contact along the axis.
      expect(report.playerContribution, 150);
      expect(report.playerPosition, Vector2(200, 100));
      expect(report.contactPoint, Vector2(198.3, 70.2));

      final explanation = report.explanation;
      expect(explanation, contains('bus'));
      expect(explanation, contains('210.0'));
      expect(explanation, contains('150.0'));
      expect(explanation, contains('60.0'));
      expect(explanation, contains('198.3'));
      // The crash explanation states the rule that doomed it.
      expect(
        explanation,
        contains(CollisionRules.scrapeSpeedThreshold.toStringAsFixed(0)),
      );
    });

    test('a scrape report names the vehicle and the survival rule', () {
      final report = CollisionRules.buildReport(
        severity: ContactSeverity.scrape,
        vehicleKind: 'sedan',
        playerVelocity: Vector2(0, -40),
        playerPosition: Vector2(200, 100),
        trafficVelocity: Vector2.zero(),
        trafficPosition: Vector2(200, 80),
        contactPoint: Vector2(200, 78),
      );

      expect(report.closingSpeedAlongImpact, 40);
      expect(report.explanation, contains('sedan'));
      expect(report.explanation, contains('40.0'));
      expect(
        report.explanation,
        contains(
          (CollisionRules.scrapeSpeedKeep * 100).toStringAsFixed(0),
        ),
      );
    });

    test('a struck-stationary report records zero contribution and never '
        'blames the player (issue #58)', () {
      // The issue's Level 8 contact: a parked cab, oncoming sportsCar at
      // 147.5 px/s — the ruling is a scrape and every surface words it as
      // the taxi being hit, not hitting.
      final report = CollisionRules.buildReport(
        severity: CollisionRules.severityFor(
          147.5,
          CollisionRules.playerContribution(
            playerVelocity: Vector2.zero(),
            impactAxis: CollisionRules.impactAxis(
              Vector2(200, 527.7),
              Vector2(200, 400),
            ),
          ),
        ),
        vehicleKind: 'sportsCar',
        playerVelocity: Vector2.zero(),
        playerPosition: Vector2(200, 527.7),
        trafficVelocity: Vector2(0, 147.5),
        trafficPosition: Vector2(200, 400),
        contactPoint: Vector2(185.0, 527.7),
      );

      expect(report.severity, ContactSeverity.scrape);
      expect(report.closingSpeedAlongImpact, closeTo(147.5, 1e-9));
      expect(report.playerContribution, 0);

      expect(report.headline, 'A sportsCar ran into you — nothing lost.');
      expect(report.headline, isNot(contains('You hit')));
      expect(report.headline, isNot(contains('You scraped')));

      expect(report.explanation, contains('Struck by a sportsCar'));
      expect(report.explanation, contains('147.5'));
      // The struck scrape closes *over* the crash threshold; claiming it
      // was under it (the ordinary scrape wording) would be a lie.
      expect(report.explanation, isNot(contains('under the')));
      expect(report.explanation, contains('not ruled against the taxi'));
    });
  });

  group('buildReport / headline — the player-facing one-liner', () {
    test('a flat-out crash says so, in words, with the vehicle', () {
      final report = CollisionRules.buildReport(
        severity: ContactSeverity.crash,
        vehicleKind: 'bus',
        playerVelocity: Vector2(0, -150),
        playerPosition: Vector2(200, 100),
        trafficVelocity: Vector2(0, 60),
        trafficPosition: Vector2(200, 40),
        contactPoint: Vector2(198.3, 70.2),
      );

      expect(report.headline, 'You hit the bus flat out.');
    });

    test('a slower crash drops the speed word rather than lying', () {
      final report = CollisionRules.buildReport(
        severity: ContactSeverity.crash,
        vehicleKind: 'sedan',
        playerVelocity: Vector2(0, -60),
        playerPosition: Vector2(200, 100),
        trafficVelocity: Vector2(0, 60),
        trafficPosition: Vector2(200, 40),
        contactPoint: Vector2(200, 70),
      );

      expect(report.headline, 'You hit the sedan.');
    });

    test('a scrape headline names the vehicle and the mercy', () {
      final report = CollisionRules.buildReport(
        severity: ContactSeverity.scrape,
        vehicleKind: 'sedan',
        playerVelocity: Vector2(0, -40),
        playerPosition: Vector2(200, 100),
        trafficVelocity: Vector2.zero(),
        trafficPosition: Vector2(200, 80),
        contactPoint: Vector2(200, 78),
      );

      expect(report.headline, contains('scraped the sedan'));
      expect(report.headline, contains('nothing lost'));
    });

    test('a cab run into from behind is worded as the victim (issue #58)',
        () {
      // Same-direction traffic closing on a slower cab from behind: the
      // player is driving *away* along the impact axis (it points from the
      // striker below up to the cab), so the headline must not read as the
      // player doing anything.
      final report = CollisionRules.buildReport(
        severity: ContactSeverity.scrape,
        vehicleKind: 'sedan',
        playerVelocity: Vector2(0, -40),
        playerPosition: Vector2(200, 100),
        trafficVelocity: Vector2(0, -190),
        trafficPosition: Vector2(200, 200),
        contactPoint: Vector2(200, 130),
      );

      expect(report.playerContribution, -40);
      expect(report.headline, 'A sedan ran into you — nothing lost.');
      expect(report.headline, isNot(contains('You ')));
    });

    test('the headline never leaks the telemetry vocabulary', () {
      final report = CollisionRules.buildReport(
        severity: ContactSeverity.crash,
        vehicleKind: 'truck',
        playerVelocity: Vector2(0, -150),
        playerPosition: Vector2(200, 100),
        trafficVelocity: Vector2(0, 60),
        trafficPosition: Vector2(200, 40),
        contactPoint: Vector2(199.5, 70),
      );

      expect(report.headline, isNot(contains('px/s')));
      expect(report.headline, isNot(contains('axis')));
      expect(report.headline, isNot(contains('(')));
    });
  });
}
