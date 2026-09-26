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

  /// Fares the player explicitly declined (issue #25). Tracked apart from
  /// [faresMissed] because a decline is a decision, not a slip — the
  /// on-device history can tell "drove past" from "looked at it and
  /// refused it".
  int faresDeclined = 0;

  final List<_ActiveFare> _active = [];

  /// Generate fares this far above the camera centre (px past the view top).
  static const double generationAhead = 1200.0;

  /// Cull a fare once its pending stop is this far below the camera centre.
  static const double cullBehind = 1500.0;

  /// Safety valve so a pathological frame can never spin the generator.
  static const int _maxSpawnsPerUpdate = 8;

  /// How far above the camera centre a pending pickup may sit and still
  /// count as an offer on screen (issue #25). A little past the 400 px
  /// half-viewport, so the player sees the marker before the HUD does.
  static const double offerAbove = 460.0;

  /// How far below the camera centre a pending pickup may sit and still
  /// count as an offer on screen.
  static const double offerBelow = 400.0;

  int get activeFareCount => _active.length;

  /// True while the player is carrying a fare's passenger.
  bool get hasActivePickup =>
      _active.any((f) => f.passenger.isPickedUp && !f.passenger.isDelivered);

  /// The fare currently on offer (issue #25): the pending pickup highest
  /// up the visible road — the one the player is about to reach, whose
  /// kind they can read and decline before committing to the kerb. Null
  /// when nothing waitable is on screen.
  PassengerData? get offerOnScreen {
    final cameraY = game.camera.viewfinder.position.y;
    _ActiveFare? offer;
    for (final f in _active) {
      if (f.passenger.isPickedUp) continue;
      final pickupY = f.fare.pickup.y;
      if (pickupY < cameraY - offerAbove) continue; // too far up yet
      if (pickupY > cameraY + offerBelow) continue; // already behind
      if (offer == null || pickupY < offer.fare.pickup.y) offer = f;
    }
    return offer?.passenger;
  }

  /// Declines a fare offer (issue #25): its zones come off the street, no
  /// timer starts, nothing is paid and nothing is penalised — the cost of
  /// declining is only the fare itself. The whole point of fare variety:
  /// a VIP you cannot refuse would be a modifier, not a decision.
  ///
  /// Returns false when [passenger] is not a pending offer (already
  /// aboard, delivered, or never spawned) — declining a fare you already
  /// picked up is not a thing.
  bool declineOffer(PassengerData passenger) {
    if (passenger.isPickedUp || passenger.isDelivered) return false;
    final index = _active.indexWhere((f) => f.passenger == passenger);
    if (index == -1) return false;

    final fare = _active.removeAt(index);
    fare.pickupZone.removeFromParent();
    fare.dropoffZone.removeFromParent();
    faresDeclined++;
    return true;
  }

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
      fareType: fare.fareType,
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
