import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/run_stats.dart';
import '../../services/game_state_service.dart';

/// The on-device shift stats screen (issue #17).
///
/// The game is fully offline: no analytics, no funnels, no crash-rate
/// telemetry. This screen — and the per-shift history behind it — is the
/// only instrument the endless mode's difficulty curve and chain economy
/// can be tuned against, so it shows what a tuning pass needs: totals,
/// what a typical (median) shift looks like, the distribution of run
/// lengths, and the bank-vs-push ratio. Everything is read from local
/// storage; nothing here has ever been near a network.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('stats_screen'),
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
                      key: const Key('stats_back_button'),
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
                          'SHIFT STATS',
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
                    final stats = gameState.runStats;
                    return stats.isEmpty
                        ? const _EmptyState()
                        : _StatsList(stats: stats);
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

/// A fresh install, or the history was reset: nothing has ever ended, so
/// there is nothing to show but the invitation to go make some data.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.query_stats, size: 64, color: Colors.white.withValues(alpha: 0.7)),
          const SizedBox(height: 16),
          const Text(
            'No shifts recorded yet',
            key: Key('stats_empty_state'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Finish an endless shift — bank it or wreck it —\n'
            'and its numbers show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsList extends StatelessWidget {
  const _StatsList({required this.stats});

  final RunStats stats;

  @override
  Widget build(BuildContext context) {
    // A scroll view, not a lazy ListView: the whole sheet is a handful of
    // fixed sections, and every number on it must be present the moment
    // the screen opens — nothing pending below the fold.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        const _SectionLabel('Totals'),
        _Card(
          children: [
            _statRow('Shifts ended', '${stats.runCount}',
                valueKey: const Key('stats_shifts_total')),
            _statRow('Total score', '${stats.totalScore}'),
            _statRow('Distance driven',
                RunStats.formatDistance(stats.totalDistanceMetres)),
            _statRow('Fares delivered', '${stats.totalFares}'),
            _statRow('Lives lost', '${stats.totalLivesLost}'),
            _statRow('Time driven',
                RunStats.formatDuration(stats.totalDurationSeconds)),
          ],
        ),
        const SizedBox(height: 24),

        const _SectionLabel('Typical shift'),
        _Card(
          children: [
            _statRow('Median score', _formatMedian(stats.medianScore)),
            _statRow('Median distance',
                _formatMedian(stats.medianDistanceMetres, distance: true)),
            _statRow('Median duration',
                _formatMedian(stats.medianDurationSeconds, duration: true)),
          ],
        ),
        const SizedBox(height: 24),

        const _SectionLabel('Run lengths'),
        _Card(
          children: [
            for (final bucket in stats.runLengthDistribution)
              _bucketRow(context, bucket),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'How far each ended shift drove, in bands.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        const _SectionLabel('Bank or push'),
        _Card(
          children: [
            _statRow('Banked at a dropoff', '${stats.bankedCount}',
                valueKey: const Key('stats_banked_count')),
            _statRow('Wrecked, score forfeited', '${stats.forfeitedCount}',
                valueKey: const Key('stats_forfeited_count')),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bar(
                    fraction: stats.bankedShare,
                    color: Colors.yellow,
                    key: const Key('stats_bank_bar'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${(stats.bankedShare * 100).round()}% of shifts end in a bank',
                    key: const Key('stats_banked_share'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        const _SectionLabel('Crashes'),
        _Card(
          children: [
            // Lives lost is already a total above; this section answers
            // the "where": how far into a shift the typical crash lands.
            _statRow(
              'Median crash distance',
              stats.medianLifeLossDistanceMetres == null
                  ? 'No lives lost yet'
                  : RunStats.formatDistance(stats.medianLifeLossDistanceMetres!),
            ),
          ],
        ),
        ],
      ),
    );
  }

  /// Medians are whole numbers for most histories (a middle record's own
  /// value) and half-values for even counts — show the decimal only when
  /// it exists.
  String _formatMedian(double? value,
      {bool distance = false, bool duration = false}) {
    if (value == null) return '—';
    if (distance) return RunStats.formatDistance(value);
    if (duration) return RunStats.formatDuration(value);
    return value == value.roundToDouble()
        ? '${value.round()}'
        : value.toStringAsFixed(1);
  }

  Widget _bucketRow(BuildContext context, RunLengthBucket bucket) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              bucket.label,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
          ),
          Expanded(
            child: _Bar(
              fraction: bucket.fractionOf(stats.runCount),
              color: Colors.lightBlueAccent,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${bucket.count}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
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
}

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

/// A single-value horizontal bar: a dim track with a proportional fill.
/// Width 0 is a valid state — an empty top band shows as track only.
class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color, super.key});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            Container(color: Colors.white.withValues(alpha: 0.15)),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ],
        ),
      ),
    );
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
