import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/game_state_service.dart';
import 'credits_screen.dart';
import 'records_screen.dart';
import 'stats_screen.dart';

/// Settings and progress management.
///
/// Every control here does something. Sound and music toggles exist in
/// [GameStateService] but are deliberately not surfaced: the app ships no audio
/// yet, so a toggle would be a control that changes nothing the player can
/// perceive. They belong here once audio is implemented.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('settings_screen'),
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
                      key: const Key('settings_back_button'),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      iconSize: 32,
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'SETTINGS',
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
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [
                    const _SectionLabel('Progress'),
                    Consumer<GameStateService>(
                      builder: (context, gameState, _) => Card(
                        color: Colors.white.withValues(alpha: 0.15),
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Level ${gameState.currentLevel} · '
                                '${gameState.totalCoins} coins',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  key: const Key('reset_progress_button'),
                                  icon: const Icon(Icons.restart_alt),
                                  label: const Text('RESET PROGRESS'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.yellow,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  onPressed: () =>
                                      _confirmReset(context, gameState),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const _SectionLabel('About'),
                    // The records screen (issue #21): personal bests and
                    // achievements. A reading screen, like the stats one
                    // below it.
                    ListTile(
                      key: const Key('settings_records_tile'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.emoji_events,
                          color: Colors.yellow, size: 28),
                      title: const Text(
                        'Records',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Personal bests and achievements, on this device '
                        'only',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: Colors.white70),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RecordsScreen(),
                        ),
                      ),
                    ),
                    // The on-device shift history (issue #17): the game's
                    // only tuning instrument, since nothing analytic ever
                    // leaves the device. A reading screen, not a control.
                    ListTile(
                      key: const Key('settings_stats_tile'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bar_chart,
                          color: Colors.white, size: 28),
                      title: const Text(
                        'Shift stats',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Your shift history, on this device only',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: Colors.white70),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const StatsScreen(),
                        ),
                      ),
                    ),
                    ListTile(
                      key: const Key('settings_credits_tile'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.info_outline,
                          color: Colors.white, size: 28),
                      title: const Text(
                        'Credits',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                      trailing: const Icon(Icons.chevron_right,
                          color: Colors.white70),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CreditsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Resetting wipes the save, so it asks first.
  Future<void> _confirmReset(
    BuildContext context,
    GameStateService gameState,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('reset_confirm_dialog'),
        title: const Text('Reset progress?'),
        content: const Text(
          'This clears your level, coins, records, achievements, and '
          'shift stats, and starts over from level 1. It cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            key: const Key('reset_cancel_button'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            key: const Key('reset_confirm_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('RESET'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      gameState.resetProgress();
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Colors.yellow,
        ),
      ),
    );
  }
}
