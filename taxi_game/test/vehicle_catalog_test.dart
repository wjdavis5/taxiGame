import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_game/data/vehicle_catalog.dart';
import 'package:taxi_game/game/vehicle_sprites.dart';

void main() {
  // The economy basis the ladder is priced against (issue #34), measured
  // by `test/economy_simulation_test.dart` over its standard 101-seed
  // batch: a first-session shift carries 1,240–1,428 coins of fares alone
  // (p25–p75 of the "new" driver stand-in) before banking, and a
  // competent one 1,250–1,660; banking the chain score 1:1 pays on top.
  // The ladder targets the conservative wallet those floors imply —
  // about 2,000 coins a shift for a new player, 2,500 for a median one —
  // so the numbers below are tuning constants, not measurements: the
  // targets the issue sets (first car in 2-3 shifts, mid fleet in about
  // a week of dailies, The Executive a real grind) expressed in shift
  // earnings.
  const newPlayerShiftCoins = 2000;
  const medianPlayerShiftCoins = 2500;

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

    test('the first car is the first-session save: 2-3 shifts in',
        () {
      // The entry rung must be reachable inside the first session's
      // shifts, but never inside one — it has to be a save with an end.
      final first = VehicleCatalog.vehicles
          .where((v) => v.id != VehicleSprites.defaultVehicleId)
          .reduce((a, b) => a.price <= b.price ? a : b);
      expect(first.price / newPlayerShiftCoins, greaterThanOrEqualTo(2.0),
          reason: '${first.name} must take more than one shift');
      expect(first.price / newPlayerShiftCoins, lessThanOrEqualTo(3.0),
          reason: '${first.name} must land inside the first session');
    });

    test('the mid fleet costs about a week of dailies', () {
      // A daily is one shift; a week of median shifts is the target for
      // the middle of the fleet, with two days of slack either way.
      final purchasables = VehicleCatalog.vehicles
          .where((v) => v.id != VehicleSprites.defaultVehicleId)
          .toList()
        ..sort((a, b) => a.price.compareTo(b.price));
      final mid = purchasables.sublist(2, 4); // 3rd and 4th rungs
      for (final vehicle in mid) {
        final shifts = vehicle.price / medianPlayerShiftCoins;
        expect(shifts, greaterThanOrEqualTo(4.0),
            reason: '${vehicle.name} is too cheap for its rung');
        expect(shifts, lessThanOrEqualTo(9.0),
            reason: '${vehicle.name} drifts past a week of dailies');
      }
    });

    test('The Executive is a real grind', () {
      final executive = VehicleCatalog.byId('luxury_white')!;
      // Far past a week of dailies for a median player — the priciest
      // rung is weeks of play, not one lucky banked run.
      expect(
        executive.price,
        greaterThanOrEqualTo(12 * medianPlayerShiftCoins),
        reason: 'the priciest car must stay out of one-shift reach',
      );
    });

    test('no purchasable car is pocket change', () {
      // Every rung is a save worth making: at least two new-player
      // shifts, so the garage never sells anything the wallet already
      // covers.
      for (final vehicle in VehicleCatalog.vehicles) {
        if (vehicle.id == VehicleSprites.defaultVehicleId) continue;
        expect(vehicle.price, greaterThanOrEqualTo(2 * newPlayerShiftCoins),
            reason: '${vehicle.name} must cost a real save');
      }
    });
  });
}
