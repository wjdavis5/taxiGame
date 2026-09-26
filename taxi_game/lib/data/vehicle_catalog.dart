import '../game/vehicle_sprites.dart';

/// A vehicle offered in the garage: its save-data id, display name, and
/// price in coins.
class GarageVehicle {
  final String id;
  final String name;
  final int price;

  const GarageVehicle({
    required this.id,
    required this.name,
    required this.price,
  });
}

/// The garage's offering: every vehicle that ships with art
/// ([VehicleSprites.playerVehicleIds]), named and priced as an ascending
/// ladder.
///
/// Prices are sized against the level economy (rewards run 50 for level 1 to
/// 300 for level 10), so the first car lands within the first session and the
/// priciest takes a few playthroughs. The starter cab costs nothing — it is
/// owned from the first launch (`SaveData.createDefault`), so its price never
/// renders; it is listed so the garage shows one card per vehicle that exists.
class VehicleCatalog {
  VehicleCatalog._();

  static const List<GarageVehicle> vehicles = [
    GarageVehicle(id: 'taxi_yellow', name: 'Classic Cab', price: 0),
    GarageVehicle(id: 'compact_red', name: 'City Compact', price: 150),
    GarageVehicle(id: 'sedan_blue', name: 'Street Sedan', price: 250),
    GarageVehicle(id: 'minivan_gray', name: 'Family Minivan', price: 400),
    GarageVehicle(id: 'suv_green', name: 'Trail SUV', price: 600),
    GarageVehicle(id: 'sports_black', name: 'Night Racer', price: 850),
    GarageVehicle(id: 'luxury_white', name: 'The Executive', price: 1200),
  ];

  /// The catalog entry for [id], or null when the id ships no art.
  static GarageVehicle? byId(String id) {
    for (final vehicle in vehicles) {
      if (vehicle.id == id) return vehicle;
    }
    return null;
  }
}
