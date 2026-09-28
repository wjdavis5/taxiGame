import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../game/systems/daily_shift.dart';
import '../../game/taxi_game.dart';
import '../../services/audio_service.dart';
import '../../services/game_state_service.dart';
import '../../services/haptics_service.dart';
import 'credits_screen.dart';
import 'daily_screen.dart';
import 'game_screen.dart';
import 'garage_screen.dart';
import 'records_screen.dart';
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
          // Scrolls so the menu survives short viewports — six buttons plus
          // the title and stats overflow a fixed Column on small phones.
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
                            // Past the last rung the ladder is finished
                            // (issue #16): PLAY hands off to Endless, and
                            // the stat stops promising an eleventh level.
                            gameState.tutorialComplete
                                ? 'TUTORIAL DONE'
                                : 'Level ${gameState.currentLevel}',
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

                  // The Date-seeded Daily Shift (issue #19): one shared
                  // course a day, derived from the date — computed, never
                  // fetched, so the game stays fully offline. One attempt:
                  // once today's shift has ended, the button becomes the
                  // way back to the day's result instead of a replay.
                  Consumer<GameStateService>(
                    builder: (context, gameState, child) {
                      final result = gameState.todayDailyResult;
                      return Column(
                        children: [
                          _MenuButton(
                            buttonKey: const ValueKey('daily_button'),
                            icon: result == null
                                ? Icons.event
                                : Icons.emoji_events,
                            label: result == null
                                ? 'DAILY SHIFT'
                                : 'DAILY COMPLETE',
                            primary: true,
                            onPressed: () {
                              if (result == null) {
                                // The day's course: the seed derived from
                                // today's date (issue #19's shared course,
                                // riding issue #11's endless shift).
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => GameScreen(
                                      endlessSeed: DailyShift.seedForDateKey(
                                          DailyShift.todayKey),
                                      isDailyShift: true,
                                    ),
                                  ),
                                );
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const DailyScreen(),
                                  ),
                                );
                              }
                            },
                          ),
                          const SizedBox(height: 10),
                          Text(
                            result == null
                                ? '${DailyShift.todayKey} \u00b7 ONE SHIFT, '
                                    'SAME FOR EVERYONE'
                                : '${result.score} PTS \u00b7 DONE FOR TODAY',
                            key: const ValueKey('daily_status'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          TextButton(
                            key: const ValueKey('daily_history_button'),
                            onPressed: () {
                              audioOf(context)?.playButtonSound();
                              hapticsOf(context)?.buttonPress();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const DailyScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'DAILY HISTORY',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Endless shift is the headline mode (issue #15): the
                  // top shift button, in the primary style, with the score
                  // to beat right beneath it. (Issue #19 later added the
                  // day's Daily above it — the one course that is shared,
                  // where this one is the player's own.) A procedurally
                  // generated run (issue #11) — each shift gets a fresh
                  // seed, and the seed fully determines the course.
                  Consumer<GameStateService>(
                    builder: (context, gameState, child) {
                      return Column(
                        children: [
                          _MenuButton(
                            buttonKey: const ValueKey('endless_button'),
                            icon: Icons.all_inclusive,
                            label: 'ENDLESS SHIFT',
                            primary: true,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => GameScreen(
                                    endlessSeed: TaxiGame.freshSeed(),
                                  ),
                                ),
                              );
                            },
                          ),
                          if (gameState.endlessBestScore > 0) ...[
                            const SizedBox(height: 10),
                            Text(
                              'BEST ${gameState.endlessBestScore}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // The hand-made career ladder (issue #11's predecessor):
                  // one crash fails the level, and completion unlocks the
                  // next.
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

                  // Records button (issue #21): personal bests and the
                  // achievement set — with no leaderboards in a fully
                  // offline game, this is where the player's history
                  // lives.
                  _MenuButton(
                    buttonKey: const Key('records_button'),
                    icon: Icons.emoji_events,
                    label: 'RECORDS',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RecordsScreen(),
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

  /// Primary buttons are the menu's headline actions: bigger, in the
  /// app's signature yellow. Everything else steps back in white.
  final bool primary;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.buttonKey,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      key: buttonKey,
      // Every menu press clicks (issue #4) and ticks (issue #5), then
      // does its job.
      onPressed: () {
        audioOf(context)?.playButtonSound();
        hapticsOf(context)?.buttonPress();
        onPressed();
      },
      icon: Icon(icon, size: primary ? 34 : 32),
      label: Text(
        label,
        style: TextStyle(
          fontSize: primary ? 26 : 22,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: primary ? 44 : 40,
          vertical: primary ? 18 : 15,
        ),
        minimumSize: Size(primary ? 280 : 250, primary ? 70 : 60),
        backgroundColor: primary ? Colors.yellow : Colors.white,
        foregroundColor: primary ? Colors.black : Colors.blue.shade900,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
        elevation: primary ? 10 : 6,
      ),
    );
  }
}
