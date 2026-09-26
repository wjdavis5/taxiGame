import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/data/vehicle_catalog.dart';
import 'package:taxi_game/game/vehicle_sprites.dart';

void main() {
  group('VehicleCatalog', () {
    test('covers exactly the vehicles that ship with art', () {
      // Order is the garage's own choice (starter on top, then the price
      // ladder); coverage must be exact either way — no orphan sprites and
      // no card without art.
      expect(
        VehicleCatalog.vehicles.map((v) => v.id).toSet(),
        VehicleSprites.playerVehicleIds.toSet(),
      );
      expect(VehicleCatalog.vehicles.length, VehicleSprites.playerVehicleIds.length);
    });

    test('the starter cab is free, so no fresh install is gated', () {
      final starter = VehicleCatalog.byId(VehicleSprites.defaultVehicleId);
      expect(starter, isNotNull);
      expect(starter!.price, 0);
    });

    test('every other vehicle costs coins, as a strictly ascending ladder',
        () {
      final purchasables = VehicleCatalog.vehicles
          .where((v) => v.id != VehicleSprites.defaultVehicleId)
          .toList();
      expect(purchasables, isNotEmpty);

      for (final vehicle in purchasables) {
        expect(
          vehicle.price,
          greaterThan(0),
          reason: '${vehicle.id} must cost coins',
        );
      }

      final prices = purchasables.map((v) => v.price).toList();
      expect(prices, orderedEquals(prices.toList()..sort()));
      // A ladder, not three cars at the same price point.
      expect(prices.toSet().length, prices.length);
    });

    test('byId returns null for ids that ship no art', () {
      expect(VehicleCatalog.byId('sport_taxi'), isNull);
    });

    test('every vehicle has a non-empty display name', () {
      for (final vehicle in VehicleCatalog.vehicles) {
        expect(vehicle.name.trim(), isNotEmpty, reason: vehicle.id);
      }
    });
  });
}
