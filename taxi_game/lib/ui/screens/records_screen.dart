import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/achievements.dart';
import '../../models/run_stats.dart';
import '../../services/game_state_service.dart';

/// The records screen (issue #21).
///
/// With no leaderboards — the game is permanently offline — this screen
/// and the history behind it are the only place a player's history lives.
/// Two halves: the personal bests (best banked score, longest chain,
/// furthest distance, most fares in one shift) and the achievement set,
/// every entry shown with either its earned state or its progress toward
/// it. Everything reads live save state through [GameStateService]; the
/// `achievements` map in the save is the single source of truth for what
/// has been earned.
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('records_screen'),
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
                      key: const Key('records_back_button'),
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
                          'RECORDS',
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
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PersonalBestsCard(gameState: gameState),
                          const SizedBox(height: 24),
                          _AchievementsList(gameState: gameState),
                        ],
                      ),
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

/// The four personal bests (issue #21). Always shown, even all-zero: a
/// fresh install's records are an invitation, not an empty screen —
/// every zero is a number a shift can beat.
class _PersonalBestsCard extends StatelessWidget {
  const _PersonalBestsCard({required this.gameState});

  final GameStateService gameState;

  @override
  Widget build(BuildContext context) {
    final bests = gameState.personalBests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Personal bests'),
        _Card(
          children: [
            _statRow(
              'Best banked score',
              '${bests.bestBankedScore}',
              valueKey: const Key('records_pb_score'),
            ),
            _statRow(
              'Longest chain',
              '\u00d7${bests.longestChain}',
              valueKey: const Key('records_pb_chain'),
            ),
            _statRow(
              'Furthest distance',
              RunStats.formatDistance(bests.furthestDistanceMetres),
              valueKey: const Key('records_pb_distance'),
            ),
            _statRow(
              'Most fares in one shift',
              '${bests.mostFaresInOneShift}',
              valueKey: const Key('records_pb_fares'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The whole achievement set (issue #21): earned entries in gold with
/// their badge, locked ones dimmed with a progress line toward the
/// threshold. Every achievement is always on the screen — locked ones
/// name exactly what they ask for, because a hidden requirement is a
/// rumour, not an achievement.
class _AchievementsList extends StatelessWidget {
  const _AchievementsList({required this.gameState});

  final GameStateService gameState;

  @override
  Widget build(BuildContext context) {
    final state = gameState.achievementState;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Achievements'),
        Text(
          '${gameState.unlockedAchievementCount} of '
          '${AchievementCatalog.all.length} earned',
          key: const Key('records_achievement_count'),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        for (final achievement in AchievementCatalog.all)
          _AchievementCard(
            achievement: achievement,
            unlocked: gameState.isAchievementUnlocked(achievement.id),
            state: state,
          ),
      ],
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({
    required this.achievement,
    required this.unlocked,
    required this.state,
  });

  final AchievementDef achievement;
  final bool unlocked;
  final AchievementState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('achievement_card_${achievement.id}'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: unlocked
            ? Colors.amber.shade700.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: unlocked ? Colors.yellow : Colors.white24,
          width: unlocked ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            unlocked ? Icons.emoji_events : Icons.lock_outline,
            size: 32,
            color: unlocked ? Colors.yellow : Colors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: unlocked ? Colors.yellow : Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          unlocked
              ? const Text(
                  'EARNED',
                  key: Key('achievement_state_earned'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.yellow,
                  ),
                )
              : Text(
                  '${achievement.progress(state)}/${achievement.threshold}',
                  key: Key('achievement_progress_${achievement.id}'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
        ],
      ),
    );
  }
}

/// Shared with the stats screen's look — same card, same row shape, same
/// section labels, so the two reading screens read as one family.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

Widget _statRow(String label, String value, {Key? valueKey}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Flexible label: a long label wraps instead of pushing the row
        // past a narrow screen's edge.
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white70,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          key: valueKey,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
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
