import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/game_state_service.dart';
import 'credits_screen.dart';
import 'game_screen.dart';
import 'garage_screen.dart';
import 'settings_screen.dart';

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
          // Scrolls so the menu survives short viewports — five buttons plus the
          // title and stats overflow a fixed Column on small phones.
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.vertical,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Game Title
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Text(
                      'CAB HUSTLE',
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
                    buttonKey: const Key('play_button'),
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
                    buttonKey: const Key('garage_button'),
                    icon: Icons.directions_car,
                    label: 'GARAGE',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const GarageScreen(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Settings Button
                  _MenuButton(
                    buttonKey: const Key('settings_button'),
                    icon: Icons.settings,
                    label: 'SETTINGS',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Credits Button
                  _MenuButton(
                    buttonKey: const Key('credits_button'),
                    icon: Icons.info_outline,
                    label: 'CREDITS',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CreditsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
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
  final Key? buttonKey;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      key: buttonKey,
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
