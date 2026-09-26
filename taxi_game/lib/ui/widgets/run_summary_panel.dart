import 'package:flutter/material.dart';

import '../../game/systems/daily_shift.dart';
import '../../game/systems/run_summary.dart';
import '../../game/taxi_game.dart';
import '../screens/game_screen.dart';

/// The end-of-shift run summary (issue #15): what the shift earned, what
/// it cost, and — the number a replay tries to beat — whether the score
/// set a new personal best. Shown for both endings: a banked shift gets
/// its payout celebrated, a wrecked one gets its forfeit named (issue
/// #14). DRIVE AGAIN restarts immediately on a fresh shift; the retry
/// never routes through the menu.
class RunSummaryPanel extends StatelessWidget {
  const RunSummaryPanel({
    super.key,
    required this.game,
    required this.summary,
  });

  final TaxiGame game;
  final RunSummary summary;

  bool get _banked => summary.outcome == ShiftOutcome.banked;

  @override
  Widget build(BuildContext context) {
    // Scrollable, not fixed: the panel's content grows across issues
    // (the daily banner, the ghost-race button), and a tall device or a
    // large accessibility text scale must scroll it, never clip it.
    return Center(
      child: Container(
        key: const ValueKey('run_summary_panel'),
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: _banked ? Colors.blueGrey.shade800 : Colors.red.shade900,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _banked ? Icons.savings : Icons.car_crash,
                size: 64,
                color: Colors.white,
              ),
              const SizedBox(height: 12),
              Text(
                _banked ? 'SHIFT BANKED' : 'SHIFT OVER',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              // The daily's settled attempt (issue #19): the result is in —
              // banked or wrecked alike — and the shared course is done for
              // today. Says so here, where the score being celebrated (or
              // mourned) is the one being screenshotted.
              if (game.isDailyShift) ...[
                const SizedBox(height: 10),
                Container(
                  key: const ValueKey('daily_result_banner'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event, size: 20, color: Colors.black),
                      SizedBox(width: 6),
                      Text(
                        "TODAY'S DAILY IS IN",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'A new course arrives tomorrow.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (_banked)
                // The payout: the whole run score, now permanent in the
                // wallet — the thing pushing would have grown and a crash
                // would have taken.
                Text(
                  '+${summary.score} Coins',
                  style: const TextStyle(
                    fontSize: 24,
                    color: Colors.yellow,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else ...[
                // What ended it: the third crash, named like every other.
                Text(
                  game.lastImpact?.explanation ??
                      'Three crashes — the shift is over.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Forfeited: ${summary.score} coins',
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.yellow,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (summary.isPersonalBest)
                Container(
                  key: const ValueKey('pb_banner'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.yellow,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events, size: 20, color: Colors.black),
                      SizedBox(width: 6),
                      Text(
                        'NEW PERSONAL BEST',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                )
              else if (summary.previousBest > 0)
                Text(
                  'Best: ${summary.previousBest}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              const SizedBox(height: 12),
              _statRow('Score', '${summary.score}'),
              _statRow('Best chain', '\u00d7${summary.bestChain}'),
              _statRow('Fares delivered', '${summary.faresDelivered}'),
              _statRow('Distance', summary.distanceLabel),
              _statRow('Coins earned', '${summary.coinsEarned}'),
              const SizedBox(height: 20),
              ElevatedButton(
                key: const ValueKey('retry_button'),
                onPressed: () {
                  // Straight back behind the wheel: a fresh shift on a new
                  // seed, without touching the menu stack (issue #15). After
                  // a daily (issue #19) retryShift demotes to free play —
                  // the day's course is done — so the button names what it
                  // actually starts.
                  game.retryShift();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellow,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                ),
                child: Text(
                  game.isDailyShift ? 'ENDLESS SHIFT' : 'DRIVE AGAIN',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Race the ghost (issue #20): the stored best run for the
              // day's course — often the very shift just settled —
              // replayed as a translucent car. Offered wherever a
              // daily-course shift ends, because that is the only place a
              // "subsequent attempt at the same day's course" exists: the
              // scoring attempt is spent, but racing yourself never is.
              if ((game.isDailyShift || game.isGhostRace) &&
                  game.gameState.todayGhost != null) ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  key: const ValueKey('race_ghost_button'),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GameScreen(
                          endlessSeed:
                              DailyShift.seedForDateKey(DailyShift.todayKey),
                          isGhostRace: true,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.flash_on),
                  label: const Text(
                    'RACE YOUR GHOST',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
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
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.white70,
            ),
          ),
          Text(
            value,
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
