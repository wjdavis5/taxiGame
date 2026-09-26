import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/game/vehicle_sprites.dart';
import 'package:taxi_game/models/traffic_pattern.dart';

void main() {
  group('playerSpritePath', () {
    test('maps every known player vehicle id to its sprite path', () {
      for (final id in VehicleSprites.playerVehicleIds) {
        expect(VehicleSprites.playerSpritePath(id), 'vehicles/player/$id.png');
      }
    });

    test('every player sprite ships in the assets folder', () {
      for (final id in VehicleSprites.playerVehicleIds) {
        final file = File('assets/images/vehicles/player/$id.png');
        expect(file.existsSync(), isTrue, reason: 'missing sprite for "$id"');
      }
    });

    test('unknown ids fall back to the default taxi', () {
      expect(
        VehicleSprites.playerSpritePath('sport_taxi'),
        'vehicles/player/${VehicleSprites.defaultVehicleId}.png',
      );
    });

    test('the default vehicle is one of the known vehicles', () {
      expect(
        VehicleSprites.playerVehicleIds,
        contains(VehicleSprites.defaultVehicleId),
      );
    });

    test('the save-data default renders a sprite', () {
      // SaveData.createDefault() selects 'taxi_yellow'; it must stay a vehicle
      // that ships with art.
      expect(
        VehicleSprites.playerSpritePath('taxi_yellow'),
        'vehicles/player/taxi_yellow.png',
      );
    });
  });

  group('trafficSpritePath', () {
    test('maps every traffic vehicle type to its sprite path', () {
      expect(
        VehicleSprites.trafficSpritePath(TrafficVehicleType.sedan),
        'vehicles/traffic/sedan_gray.png',
      );
      expect(
        VehicleSprites.trafficSpritePath(TrafficVehicleType.truck),
        'vehicles/traffic/truck_red.png',
      );
      expect(
        VehicleSprites.trafficSpritePath(TrafficVehicleType.sportsCar),
        'vehicles/traffic/sports_red.png',
      );
      expect(
        VehicleSprites.trafficSpritePath(TrafficVehicleType.suv),
        'vehicles/traffic/suv_blue.png',
      );
      expect(
        VehicleSprites.trafficSpritePath(TrafficVehicleType.bus),
        'vehicles/traffic/bus_yellow.png',
      );
    });

    test('every traffic sprite ships in the assets folder', () {
      for (final type in TrafficVehicleType.values) {
        final path = VehicleSprites.trafficSpritePath(type);
        final file = File('assets/images/$path');
        expect(file.existsSync(), isTrue,
            reason: 'missing sprite "$path" for $type');
      }
    });
  });
}
