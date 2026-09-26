import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/taxi_game.dart';
import '../../services/game_state_service.dart';

/// HUD overlay that displays during gameplay
class HudOverlay extends StatelessWidget {
  const HudOverlay({super.key, required this.game});

  final TaxiGame game;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Top bar with level, coins, pause button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Level number, or distance driven in an endless shift
                Consumer<GameStateService>(
                  builder: (context, gameState, child) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: game.isEndless
                          ? _EndlessDistanceBadge(game: game)
                          : Text(
                              'Level ${game.currentLevelNumber}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    );
                  },
                ),
                
                // Coins
                Consumer<GameStateService>(
                  builder: (context, gameState, child) {
                    // Keyed on the total so a coin award restarts the
                    // pulse: the counter pops as the coin pops land in it
                    // (issue #7).
                    return TweenAnimationBuilder<double>(
                      key: ValueKey('coin-pulse-${gameState.totalCoins}'),
                      tween: Tween(begin: 1.3, end: 1.0),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.monetization_on,
                              color: Colors.yellow,
                              size: 20,
                            ),
                            const SizedBox(width: 5),
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
                    );
                  },
                ),
                
                // Pause button
                IconButton(
                  onPressed: () {
                    game.pauseGame();
                  },
                  icon: const Icon(
                    Icons.pause,
                    color: Colors.white,
                    size: 32,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                ),
              ],
            ),
            
            const Spacer(),
            
            // Bottom instruction
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(25),
              ),
              child: const Text(
                'HOLD OR ↑ TO DRIVE • ←→ STEER',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// Live distance readout for endless shifts (issue #11). The game world
/// has no per-frame Flutter rebuilds, so the badge polls the run distance
/// on a short timer — cheap, and plenty for a counter.
class _EndlessDistanceBadge extends StatefulWidget {
  const _EndlessDistanceBadge({required this.game});

  final TaxiGame game;

  @override
  State<_EndlessDistanceBadge> createState() => _EndlessDistanceBadgeState();
}

class _EndlessDistanceBadgeState extends State<_EndlessDistanceBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// World px to metres: 10 px = 1 m, so a full-speed minute reads as
  /// ~900 m. A made-but-fixed scale — the number only needs to mean
  /// "further is deeper into the shift".
  static const double pixelsPerMetre = 10.0;

  @override
  Widget build(BuildContext context) {
    final metres = widget.game.runDistance / pixelsPerMetre;
    final label = metres >= 1000
        ? '${(metres / 1000).toStringAsFixed(1)} km'
        : '${metres.round()} m';

    return Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
