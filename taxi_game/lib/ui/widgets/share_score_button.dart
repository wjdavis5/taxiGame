import 'package:flutter/material.dart';

import '../../game/systems/daily_shift.dart';
import '../../game/systems/run_summary.dart';
import '../../game/systems/score_card.dart';
import '../../game/taxi_game.dart';
import '../../services/score_card_renderer.dart';
import '../../services/share_service.dart';

/// The run-summary panel's SHARE SCORE button (issue #22): renders the
/// settled shift as a score card image — score, chain, distance, date,
/// and the day's seed — and hands it to the OS share sheet. This is how
/// an offline game does a leaderboard: the Daily Shift (#19) made the
/// course shared; the card is how the score travels.
///
/// Shown on iOS only, where the native half of the channel lives (the
/// project ships iOS only — see the release workflow). On tap, the card
/// is rendered fresh from the summary snapshot the panel already holds,
/// so what goes to the sheet is what the panel shows.
class ShareScoreButton extends StatefulWidget {
  const ShareScoreButton({
    super.key,
    required this.game,
    required this.summary,
  });

  final TaxiGame game;
  final RunSummary summary;

  @override
  State<ShareScoreButton> createState() => _ShareScoreButtonState();
}

class _ShareScoreButtonState extends State<ShareScoreButton> {
  final ScoreCardRenderer _renderer = ScoreCardRenderer();
  final ShareService _share = const ShareService();

  bool _sharing = false;

  Future<void> _shareScoreCard() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final card = ScoreCardData.fromRun(
        summary: widget.summary,
        seed: widget.game.runSeed,
        dateKey: widget.game.runDateKey ?? DailyShift.todayKey,
        isDailyShift: widget.game.isDailyShift,
        isGhostRace: widget.game.isGhostRace,
      );
      final png = await _renderer.renderPng(card);
      await _share.shareScoreCard(png: png, text: card.shareText);
    } catch (error) {
      // No sheet to open (no native handler), or rendering failed — the
      // button must never die silently, and never leave itself stuck.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the share sheet.')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      key: const ValueKey('share_score_button'),
      onPressed: _sharing ? null : _shareScoreCard,
      icon: _sharing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.ios_share),
      label: const Text(
        'SHARE SCORE',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
