import '../game/vehicle_sprites.dart';

/// The felt handling profile of a garage vehicle (issue #9).
///
/// These are the numbers the driving physics reads — forward top speed,
/// throttle ramp, lateral speed at full steering lock — plus the logical
/// body the hitbox is derived from. They are surfaced as bars on every
/// garage card so a purchase is an informed trade.
///
/// The fleet is designed so no car is best at everything: every car is
/// strictly beaten on at least one axis by some other car, and any car
/// faster than the starter gives something up for that speed. Those
/// invariants are enforced in `test/vehicle_handling_test.dart`, because a
/// strictly-dominating car would turn the garage into an upgrade treadmill.
class VehicleStats {
  /// Forward speed (px/s) the car ramps to at full throttle. Higher closes
  /// on traffic faster, so overtakes that were scrapes in a slow car cross
  /// the crash threshold in a fast one — speed is bought with exposure.
  final double topSpeed;

  /// How hard the throttle ramps speed up, in px/s².
  final double acceleration;

  /// Lateral speed (px/s) at full steering lock. Higher dodges harder but
  /// crosses the road faster, so small corrections overshoot.
  final double steeringSpeed;

  /// Logical body width (px). The hitbox derives from the body, never from
  /// the sprite, so this is exactly the width the player must thread
  /// through gaps.
  final double width;

  /// Logical body height (px) — nose-to-tail length in play.
  final double height;

  const VehicleStats({
    required this.topSpeed,
    required this.acceleration,
    required this.steeringSpeed,
    required this.width,
    required this.height,
  });

  /// Footprint of the logical body in px² — the raw material of the hitbox.
  double get bodyArea => width * height;
}

/// A vehicle offered in the garage: its save-data id, display name, price
/// in coins, and the handling profile that makes it worth (or not worth)
/// the money.
class GarageVehicle {
  final String id;
  final String name;
  final int price;
  final VehicleStats stats;

  const GarageVehicle({
    required this.id,
    required this.name,
    required this.price,
    required this.stats,
  });
}

/// The garage's offering: every vehicle that ships with art
/// ([VehicleSprites.playerVehicleIds]), named, priced as an ascending
/// ladder, and given a handling identity (issue #9).
///
/// Prices are sized against the **endless** economy (issue #34): a shift
/// pays its fares on delivery and banks the chain score 1:1, and the
/// instrument behind `test/economy_simulation_test.dart` measured the
/// result at 1,240–1,584 coins of fares alone per shift (p25–p75 across
/// three skill stand-ins) before banking — a competent banked shift lands
/// well past the audit's 800–2,000 figure. The ladder is priced off the
/// conservative wallet those floors imply: roughly 2,000 coins a shift
/// for a first-session player, 2,300–3,000 for a competent one. The
/// targets: the first car costs two to three shifts, the mid fleet about
/// a week of dailies, and The Executive is a real grind — weeks, not one
/// lucky run. The starter cab costs nothing — it is owned from the first
/// launch (`SaveData.createDefault`), so its price never renders; it is
/// listed so the garage shows one card per vehicle that exists.
///
/// The handling ladder, by character:
///
/// - **Classic Cab** — the balanced baseline every stat is judged against.
/// - **City Compact** — tiny body and the quickest steering in the fleet,
///   paid for with the slowest top speed and a weak throttle.
/// - **Street Sedan** — a modest step up in speed and throttle, given back
///   in steering and a slightly longer body.
/// - **Family Minivan** — the hardest launch in the fleet (great off a
///   scrape, where speed is kept at 35%), but the widest, longest, and
///   steering-lazy.
/// - **Trail SUV** — strong throttle and a higher cruise than the baseline,
///   paid for in steering and a big body.
/// - **Night Racer** — the fastest and hardest-charging car in the fleet;
///   at its top speed, overtakes cross the crash threshold that slower cars
///   scrape through, and its steering is a notch worse than the starter's.
/// - **The Executive** — fast and effortlessly steerable, but the longest
///   body and the weakest launch: a highway barge, not a sprinter.
class VehicleCatalog {
  VehicleCatalog._();

  static const List<GarageVehicle> vehicles = [
    GarageVehicle(
      id: 'taxi_yellow',
      name: 'Classic Cab',
      price: 0,
      stats: VehicleStats(
        topSpeed: 150,
        acceleration: 400,
        steeringSpeed: 300,
        width: 40,
        height: 60,
      ),
    ),
    GarageVehicle(
      id: 'compact_red',
      name: 'City Compact',
      price: 5000,
      stats: VehicleStats(
        topSpeed: 132,
        acceleration: 380,
        steeringSpeed: 345,
        width: 34,
        height: 50,
      ),
    ),
    GarageVehicle(
      id: 'sedan_blue',
      name: 'Street Sedan',
      price: 7500,
      stats: VehicleStats(
        topSpeed: 158,
        acceleration: 415,
        steeringSpeed: 285,
        width: 40,
        height: 62,
      ),
    ),
    GarageVehicle(
      id: 'minivan_gray',
      name: 'Family Minivan',
      price: 12000,
      stats: VehicleStats(
        topSpeed: 138,
        acceleration: 480,
        steeringSpeed: 255,
        width: 48,
        height: 72,
      ),
    ),
    GarageVehicle(
      id: 'suv_green',
      name: 'Trail SUV',
      price: 16000,
      stats: VehicleStats(
        topSpeed: 162,
        acceleration: 470,
        steeringSpeed: 270,
        width: 46,
        height: 70,
      ),
    ),
    GarageVehicle(
      id: 'sports_black',
      name: 'Night Racer',
      price: 24000,
      stats: VehicleStats(
        topSpeed: 188,
        acceleration: 540,
        steeringSpeed: 290,
        width: 36,
        height: 56,
      ),
    ),
    GarageVehicle(
      id: 'luxury_white',
      name: 'The Executive',
      price: 40000,
      stats: VehicleStats(
        topSpeed: 172,
        acceleration: 370,
        steeringSpeed: 315,
        width: 46,
        height: 76,
      ),
    ),
  ];

  /// The catalog entry for [id], or null when the id ships no art.
  static GarageVehicle? byId(String id) {
    for (final vehicle in vehicles) {
      if (vehicle.id == id) return vehicle;
    }
    return null;
  }

  /// The handling profile for [id]. Unknown ids (old saves, hand edits) fall
  /// back to the starter cab, mirroring `VehicleSprites.playerSpritePath` —
  /// an unknown id may change neither the rendered art nor the handling.
  static VehicleStats statsFor(String? id) =>
      byId(id ?? '')?.stats ?? byId(VehicleSprites.defaultVehicleId)!.stats;
}
