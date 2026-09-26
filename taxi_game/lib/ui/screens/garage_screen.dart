import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/vehicle_catalog.dart';
import '../../game/vehicle_sprites.dart';
import '../../services/game_state_service.dart';

/// The garage: browse, buy, and equip vehicles.
///
/// Every card renders live save state through [GameStateService]: locked cars
/// sell for their price via [GameStateService.unlockVehicle], owned cars equip
/// via [GameStateService.selectVehicle], and the header balance tracks the
/// spending. Purchases persist because the service saves on every mutation,
/// and the equipped car is what the game renders in play — the player vehicle
/// is built from `GameStateService.selectedVehicle`.
class GarageScreen extends StatelessWidget {
  const GarageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('garage_screen'),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade300, Colors.blue.shade600],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('garage_back_button'),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      iconSize: 32,
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'GARAGE',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            offset: Offset(2, 2),
                            blurRadius: 4,
                            color: Colors.black45,
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Consumer<GameStateService>(
                      builder: (context, gameState, _) => Container(
                        key: const Key('garage_coin_balance'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.monetization_on,
                              color: Colors.yellow,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${gameState.totalCoins}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Consumer<GameStateService>(
                  builder: (context, gameState, _) => ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    itemCount: VehicleCatalog.vehicles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final vehicle = VehicleCatalog.vehicles[index];
                      return _VehicleCard(
                        vehicle: vehicle,
                        gameState: gameState,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One vehicle in the list, in one of three states:
///
/// - locked: shows the price, offers BUY (which reports a shortfall in a
///   snackbar when the balance does not cover it),
/// - owned: offers SELECT,
/// - equipped: highlighted with a check badge and no action — it is already
///   the car in play.
///
/// Every card also surfaces the car's handling profile (issue #9): four
/// fleet-normalized bars for top speed, acceleration, steering, and body
/// size, all drawn on one shared scale so bar lengths compare across cards.
class _VehicleCard extends StatelessWidget {
  final GarageVehicle vehicle;
  final GameStateService gameState;

  const _VehicleCard({required this.vehicle, required this.gameState});

  @override
  Widget build(BuildContext context) {
    final unlocked = gameState.isVehicleUnlocked(vehicle.id);
    final selected = unlocked && gameState.selectedVehicle == vehicle.id;

    return Container(
      key: Key('garage_card_${vehicle.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: selected ? 0.30 : 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? Colors.yellow : Colors.white24,
          width: selected ? 3 : 1,
        ),
      ),
      child: Row(
        children: [
          // Preview: the exact sprite the game renders for this vehicle.
          SizedBox(
            width: 84,
            height: 56,
            child: Image.asset(
              'assets/images/${VehicleSprites.playerSpritePath(vehicle.id)}',
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicle.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusLine(unlocked, selected),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 8),
                _StatBars(vehicle: vehicle),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _action(context, unlocked, selected),
        ],
      ),
    );
  }

  String _statusLine(bool unlocked, bool selected) {
    if (!unlocked) return 'For sale';
    if (selected) return 'Ready to drive';
    return 'Owned';
  }

  Widget _action(BuildContext context, bool unlocked, bool selected) {
    if (selected) {
      return Container(
        key: Key('garage_in_use_${vehicle.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.yellow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.black),
            SizedBox(width: 4),
            Text(
              'IN USE',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
      );
    }

    if (unlocked) {
      return ElevatedButton(
        key: Key('garage_select_${vehicle.id}'),
        onPressed: () => gameState.selectVehicle(vehicle.id),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.yellow,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          minimumSize: const Size(0, 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: const Text(
          'SELECT',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      );
    }

    return ElevatedButton.icon(
      key: Key('garage_buy_${vehicle.id}'),
      onPressed: () => _purchase(context),
      icon: const Icon(Icons.monetization_on, size: 16),
      label: Text(
        '${vehicle.price}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.yellow,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(0, 0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  /// Buys the car. When the balance falls short the purchase is refused with
  /// a message naming exactly how many more coins are needed.
  void _purchase(BuildContext context) {
    final bought = gameState.unlockVehicle(vehicle.id, vehicle.price);
    if (bought) {
      // New wheels go straight into service so the purchase shows up in
      // play on the very next ride.
      gameState.selectVehicle(vehicle.id);
      return;
    }
    final shortfall = vehicle.price - gameState.totalCoins;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Not enough coins — you need $shortfall more for the '
          '${vehicle.name}.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// The four handling axes a garage card surfaces (issue #9), each with its
/// label and the fleet-relative value the bar length shows. Size is listed
/// as-is — a longer bar is a bigger body, and a bigger body is a bigger
/// target; judging that is the player's half of the trade.
class _StatBars extends StatelessWidget {
  final GarageVehicle vehicle;

  const _StatBars({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    final stats = vehicle.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _bar('speed', 'SPEED', stats.topSpeed, (s) => s.topSpeed),
        _bar('accel', 'ACCEL', stats.acceleration, (s) => s.acceleration),
        _bar(
          'steering',
          'STEER',
          stats.steeringSpeed,
          (s) => s.steeringSpeed,
        ),
        _bar('size', 'SIZE', stats.bodyArea, (s) => s.bodyArea),
      ],
    );
  }

  /// One labelled bar. The fill is fleet-normalized (worst car in the fleet
  /// shows a sliver, best fills the track) so lengths compare across cards.
  Widget _bar(
    String axis,
    String label,
    double value,
    double Function(VehicleStats) pick,
  ) {
    final fleet = VehicleCatalog.vehicles.map((v) => pick(v.stats));
    final min = fleet.reduce((a, b) => a < b ? a : b);
    final max = fleet.reduce((a, b) => a > b ? a : b);
    final t = max > min ? (value - min) / (max - min) : 1.0;
    final fill = 0.06 + 0.94 * t.clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
              color: Colors.white.withValues(alpha: 0.70),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Container(
                height: 6,
                color: Colors.black26,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    key: Key('garage_stat_${axis}_${vehicle.id}'),
                    widthFactor: fill,
                    child: Container(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
