import 'package:flame/components.dart';

import '../../models/passenger_data.dart';
import '../components/dropoff_zone.dart';
import '../components/pickup_zone.dart';
import '../taxi_game.dart';
import 'endless_course.dart';

/// One fare currently in play.
class _ActiveFare {
  _ActiveFare({
    required this.fare,
    required this.passenger,
    required this.pickupZone,
    required this.dropoffZone,
  });

  final EndlessFare fare;
  final PassengerData passenger;
  final PickupZone pickupZone;
  final DropoffZone dropoffZone;
}

/// Keeps fares coming for the whole run (issue #11).
///
/// Fares are pulled from the seeded [EndlessCourse] one index at a time and
/// spawned shortly before they scroll into view; missed or finished fares
/// are culled behind the camera. Nothing accumulates: the live list only
/// ever holds the handful of fares around the player.
class EndlessFareController extends Component
    with HasGameReference<TaxiGame> {
  EndlessFareController({
    required this.course,
    required this.onPickup,
    required this.onDropoff,
  });

  final EndlessCourse course;

  /// Called when the player collects a fare's passenger.
  final void Function(PassengerData passenger) onPickup;

  /// Called when the player completes a delivery.
  final void Function(PassengerData passenger) onDropoff;

  /// Index of the next fare to spawn.
  int nextFareIndex = 0;

  int faresGenerated = 0;
  int faresDelivered = 0;
  int faresMissed = 0;

  final List<_ActiveFare> _active = [];

  /// Generate fares this far above the camera centre (px past the view top).
  static const double generationAhead = 1200.0;

  /// Cull a fare once its pending stop is this far below the camera centre.
  static const double cullBehind = 1500.0;

  /// Safety valve so a pathological frame can never spin the generator.
  static const int _maxSpawnsPerUpdate = 8;

  int get activeFareCount => _active.length;

  /// True while the player is carrying a fare's passenger.
  bool get hasActivePickup =>
      _active.any((f) => f.passenger.isPickedUp && !f.passenger.isDelivered);

  @override
  void update(double dt) {
    super.update(dt);

    // While the run is over (crash overlay up) the street freezes with it;
    // a restart rebuilds everything.
    if (!game.isGameActive) return;

    _generateAhead();
    _cullBehind();
  }

  void _generateAhead() {
    final cameraY = game.camera.viewfinder.position.y;
    final horizonY = cameraY - generationAhead;
    final behindY = cameraY + cullBehind;
    var spawned = 0;
    while (spawned < _maxSpawnsPerUpdate) {
      final pickupY = course.fare(nextFareIndex).pickup.y;
      if (pickupY > behindY) {
        // Hopelessly behind the player (a teleport or long freeze jumped
        // the course): skip it without ever putting it on the street.
        faresMissed++;
        nextFareIndex++;
        continue;
      }
      if (pickupY < horizonY) break; // Not needed yet; check again later.
      _spawnFare(course.fare(nextFareIndex));
      nextFareIndex++;
      spawned++;
    }
  }

  void _spawnFare(EndlessFare fare) {
    final passenger = PassengerData(
      id: 'endless_${fare.index}',
      pickupLocation: fare.pickup.clone(),
      dropoffLocation: fare.dropoff.clone(),
      reward: fare.reward,
    );

    final pickupZone = PickupZone(
      position: fare.pickup.clone(),
      passenger: passenger,
      onPickup: () => onPickup(passenger),
    );
    final dropoffZone = DropoffZone(
      position: fare.dropoff.clone(),
      passenger: passenger,
      onDropoff: () {
        // Bookkeeping first, so the game handler reads the post-delivery
        // state when it recomputes hasPassenger.
        _finishFare(passenger);
        onDropoff(passenger);
      },
    );

    game.world.add(pickupZone);
    game.world.add(dropoffZone);

    _active.add(_ActiveFare(
      fare: fare,
      passenger: passenger,
      pickupZone: pickupZone,
      dropoffZone: dropoffZone,
    ));
    faresGenerated++;
  }

  void _finishFare(PassengerData passenger) {
    faresDelivered++;
    _active.removeWhere((f) => f.passenger == passenger);
  }

  /// Removes fares whose pending stop is hopelessly behind the player.
  void _cullBehind() {
    final behindY = game.camera.viewfinder.position.y + cullBehind;

    _active.removeWhere((f) {
      final pickupMissed =
          !f.passenger.isPickedUp && f.fare.pickup.y > behindY;
      final dropoffMissed = f.passenger.isPickedUp &&
          !f.passenger.isDelivered &&
          f.fare.dropoff.y > behindY;

      if (!pickupMissed && !dropoffMissed) return false;

      faresMissed++;
      f.pickupZone.removeFromParent();
      f.dropoffZone.removeFromParent();
      return true;
    });
  }
}
