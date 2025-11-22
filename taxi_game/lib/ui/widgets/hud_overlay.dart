import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/game_state_service.dart';

/// HUD overlay that displays during gameplay
class HudOverlay extends StatelessWidget {
  const HudOverlay({super.key});

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
                // Level number
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
                      child: Text(
                        'Level ${gameState.currentLevel}',
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
                    return Container(
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
                    );
                  },
                ),
                
                // Pause button
                IconButton(
                  onPressed: () {
                    // TODO: Pause game
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
                'TAP & HOLD TO DRIVE',
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
