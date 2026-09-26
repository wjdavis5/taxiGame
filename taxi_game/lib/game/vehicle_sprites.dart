import '../models/traffic_pattern.dart';

/// Registry that maps vehicle identifiers to the sprite PNGs bundled under
/// `assets/images/vehicles/`.
///
/// The player vehicle ids double as save-data ids (`SaveData.selectedVehicle`)
/// and match the PNG file names in `assets/images/vehicles/player/`, so adding
/// a vehicle is a matter of dropping a PNG in the folder and listing it here.
class VehicleSprites {
  VehicleSprites._();

  /// The vehicle every new player starts with; also the fallback used when a
  /// save data file names a vehicle that does not exist (old saves, hand
  /// edits), so unknown ids can never break rendering.
  static const String defaultVehicleId = 'taxi_yellow';

  /// Every player vehicle id that ships with a sprite.
  static const List<String> playerVehicleIds = [
    'compact_red',
    'luxury_white',
    'minivan_gray',
    'sedan_blue',
    'sports_black',
    'suv_green',
    'taxi_yellow',
  ];

  /// Sprite asset path for [vehicleId], relative to the Flame image prefix
  /// `assets/images/`. Unknown ids fall back to [defaultVehicleId].
  static String playerSpritePath(String vehicleId) {
    final id =
        playerVehicleIds.contains(vehicleId) ? vehicleId : defaultVehicleId;
    return 'vehicles/player/$id.png';
  }

  /// Sprite asset path for a traffic vehicle of [type], relative to the Flame
  /// image prefix `assets/images/`.
  static String trafficSpritePath(TrafficVehicleType type) {
    switch (type) {
      case TrafficVehicleType.sedan:
        return 'vehicles/traffic/sedan_gray.png';
      case TrafficVehicleType.truck:
        return 'vehicles/traffic/truck_red.png';
      case TrafficVehicleType.sportsCar:
        return 'vehicles/traffic/sports_red.png';
      case TrafficVehicleType.suv:
        return 'vehicles/traffic/suv_blue.png';
      case TrafficVehicleType.bus:
        return 'vehicles/traffic/bus_yellow.png';
    }
  }
}
