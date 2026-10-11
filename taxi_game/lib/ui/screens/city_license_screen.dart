import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/vehicle_catalog.dart';
import '../../game/taxi_game.dart';
import '../../models/city_license.dart';
import '../../services/game_state_service.dart';
import '../widgets/cab_button.dart';
import 'game_screen.dart';
import 'garage_screen.dart';

/// The City License board (issue #278): the post-tutorial challenge board.
///
/// Every entry is a named objective over a system the game already has —
/// banking, close calls, fare contracts, weather, and vehicle tradeoffs —
/// and every one is attempted in an ordinary shift. Completion persists in
/// the save; a completed objective stays on the board and can be attempted
/// again, which is the point: the board is a reason to keep driving the
/// city, not a checklist that empties it. Nothing here reads a network:
/// the whole screen is the local save and the local catalogs.
class CityLicenseScreen extends StatelessWidget {
  const CityLicenseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('city_license_screen'),
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
                      key: const Key('license_back_button'),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      iconSize: 32,
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'CITY LICENSE',
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
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Consumer<GameStateService>(
                  builder: (context, gameState, _) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        Text(
                          '${gameState.completedLicenseObjectiveCount} OF '
                          '${CityLicense.board.length} COMPLETE \u2014 '
                          'EVERY OBJECTIVE IS REPLAYABLE',
                          key: const ValueKey('license_progress'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.yellow,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Each objective is attempted in a shift. Completing '
                          'one never removes it: drive the same bar again any '
                          'time.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (final family in LicenseFamily.values) ...[
                          Text(
                            family.label,
                            key: ValueKey('license_family_${family.name}'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final rule in CityLicense.board)
                            if (rule.family == family) ...[
                              _ObjectiveCard(
                                rule: rule,
                                done: gameState
                                    .isLicenseObjectiveComplete(rule.id),
                              ),
                              const SizedBox(height: 10),
                            ],
                          const SizedBox(height: 8),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One objective card: the name, the ask, the car when the rule names one,
/// and the button that starts an attempt.
class _ObjectiveCard extends StatelessWidget {
  const _ObjectiveCard({required this.rule, required this.done});

  final LicenseRule rule;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final gameState = context.read<GameStateService>();
    final car = rule.requiredVehicleId == null
        ? null
        : VehicleCatalog.byId(rule.requiredVehicleId!);
    final owned = car == null || gameState.isVehicleUnlocked(car.id);
    return Container(
      key: ValueKey('license_card_${rule.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: done ? Colors.greenAccent : Colors.white24,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  rule.title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: done ? Colors.greenAccent : Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  done ? 'DONE' : 'OPEN',
                  key: ValueKey('license_status_${rule.id}'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: done ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            rule.brief,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          if (car != null) ...[
            const SizedBox(height: 4),
            Text(
              owned
                  ? 'CAR: ${car.name.toUpperCase()}'
                  : 'CAR: ${car.name.toUpperCase()} \u2014 ${car.price} '
                      'COINS IN THE GARAGE',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.yellow,
              ),
            ),
          ],
          const SizedBox(height: 10),
          CabButton(
            key: ValueKey('license_attempt_${rule.id}'),
            icon: car != null
                ? Icons.directions_car
                : Icons.play_arrow,
            label: car == null
                ? 'START SHIFT'
                : (owned ? 'DRIVE IT' : 'GET THE CAR'),
            compact: true,
            onPressed: () => _attempt(context, gameState, car, owned),
          ),
        ],
      ),
    );
  }

  /// Starts the attempt. A car-specific objective selects its car first
  /// (only ever an owned one — the button offers the garage otherwise),
  /// then every objective gets the same fresh endless shift: the board
  /// names what to do, never a canned course, so the run is a real shift
  /// with the real traffic, weather, and offers.
  void _attempt(
    BuildContext context,
    GameStateService gameState,
    GarageVehicle? car,
    bool owned,
  ) {
    if (car != null && !owned) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const GarageScreen()),
      );
      return;
    }
    if (car != null) gameState.selectVehicle(car.id);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameScreen(endlessSeed: TaxiGame.freshSeed()),
      ),
    );
  }
}
