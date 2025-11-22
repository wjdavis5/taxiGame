import 'package:flutter/material.dart';
import 'package:flame/game.dart';

import '../../game/taxi_game.dart';
import '../widgets/hud_overlay.dart';

/// Game screen that contains the actual game widget
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final TaxiGame game;
  
  @override
  void initState() {
    super.initState();
    game = TaxiGame();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Game widget (full screen)
          GameWidget(
            game: game,
            overlayBuilderMap: {
              'hud': (context, game) => const HudOverlay(),
              'pauseMenu': (context, game) => _buildPauseMenu(context),
              'levelComplete': (context, game) => _buildLevelComplete(context),
              'levelFailed': (context, game) => _buildLevelFailed(context),
            },
            initialActiveOverlays: const ['hud'],
          ),
        ],
      ),
    );
  }
  
  Widget _buildPauseMenu(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PAUSED',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                game.resumeGame();
              },
              child: const Text('RESUME'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('MAIN MENU'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLevelComplete(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: Colors.green.shade700,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            const Text(
              'LEVEL COMPLETE!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '+50 Coins',
              style: TextStyle(
                fontSize: 24,
                color: Colors.yellow,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                // TODO: Load next level
                game.overlays.remove('levelComplete');
                game.restartLevel();
              },
              child: const Text('NEXT LEVEL'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLevelFailed(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cancel,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            const Text(
              'CRASH!',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                game.overlays.remove('levelFailed');
                game.restartLevel();
              },
              child: const Text('RETRY'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'MAIN MENU',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
