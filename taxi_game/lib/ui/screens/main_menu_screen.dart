import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flame/game.dart';

import '../game/taxi_game.dart';
import '../services/game_state_service.dart';
import 'game_screen.dart';

/// Main menu screen - entry point of the app
class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade300,
              Colors.blue.shade600,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Game Title
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  'TAXI GAME',
                  style: TextStyle(
                    fontSize: 48,
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
              
              const SizedBox(height: 40),
              
              // Game stats
              Consumer<GameStateService>(
                builder: (context, gameState, child) {
                  return Column(
                    children: [
                      _buildStatRow(
                        Icons.star,
                        'Level ${gameState.currentLevel}',
                      ),
                      const SizedBox(height: 10),
                      _buildStatRow(
                        Icons.monetization_on,
                        '${gameState.totalCoins} Coins',
                      ),
                    ],
                  );
                },
              ),
              
              const SizedBox(height: 60),
              
              // Play Button
              _MenuButton(
                icon: Icons.play_arrow,
                label: 'PLAY',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GameScreen(),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 20),
              
              // Garage Button
              _MenuButton(
                icon: Icons.directions_car,
                label: 'GARAGE',
                onPressed: () {
                  // TODO: Navigate to garage screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Garage coming soon!')),
                  );
                },
              ),
              
              const SizedBox(height: 20),
              
              // Settings Button
              _MenuButton(
                icon: Icons.settings,
                label: 'SETTINGS',
                onPressed: () {
                  // TODO: Navigate to settings screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Settings coming soon!')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatRow(IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.yellow, size: 30),
        const SizedBox(width: 10),
        Text(
          text,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 32),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
        minimumSize: const Size(250, 60),
        backgroundColor: Colors.yellow,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        elevation: 8,
      ),
    );
  }
}
