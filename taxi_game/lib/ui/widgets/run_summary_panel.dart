import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../game/systems/run_summary.dart';
import '../../game/taxi_game.dart';
import 'share_score_button.dart';

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
              // The small-phone pass (issue #187): on a 320 pt screen the
              // panel's content column is 200 px wide, and 'SHIFT BANKED'
              // is 336 px of bold type — the bare Text wrapped into two
              // flush-left lines while everything around it sat centred.
              // The completion panel's #159 scale-down idiom: lay the
              // title out under unbounded width — always one line — and
              // scale it down to fit.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _banked ? 'SHIFT BANKED' : 'SHIFT OVER',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
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
                  // The PB pill's rule, one branch up: the banner's rigid
                  // Row overflows the same 200 px column on a 320 pt phone
                  // with the same flex exception, so it rides the same
                  // scale-down box — natural size where it fits, one
                  // shrinking whole where it does not (issue #187).
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
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
                // would have taken. Scale-down, not wrap (issue #187):
                // the banked branch's twin of the wreck's Forfeited line
                // — '+240 Coins' is 240 px of type against the 200 px
                // column on a 320 pt phone.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '+${summary.score} Coins',
                    style: const TextStyle(
                      fontSize: 24,
                      color: Colors.yellow,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else ...[
                // What ended it: the third crash, named like every other.
                Text(
                  game.lastImpact?.headline ??
                      'Three crashes — the shift is over.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                // Scale-down, not wrap (issue #187): the forfeit number
                // is the wreck's headline — 'Forfeited: 90 coins' is 380
                // px of type in the same 200 px column on a 320 pt phone.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Forfeited: ${summary.score} coins',
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.yellow,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // The recovery lesson in the failure it answers: banking
                // is the escape the third crash just cost the player.
                const Text(
                  'Tip: banking at a dropoff keeps your coins safe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
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
                  // The pill's Row is rigid on purpose — a personal best
                  // banner must read at full size wherever it fits — so
                  // on a 320 pt phone (200 px of panel column against a
                  // ~292 px pill) it overflowed the yellow stripe out
                  // over the panel's edge instead of shrinking (issue
                  // #187). The scale-down idiom again, around the whole
                  // Row: it lays out at natural size under unbounded
                  // width and shrinks as one when it must, icon, gap and
                  // text together.
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.emoji_events,
                            size: 20, color: Colors.black),
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
              // Achievements this shift earned (issue #21): one gold
              // banner each, naming the award. This is the unlock
              // notification — shift end is where every gameplay measure
              // lands, so it is where the game tells you.
              if (summary.achievementsUnlocked.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final achievement in summary.achievementsUnlocked)
                  Container(
                    key: ValueKey('achievement_unlock_${achievement.id}'),
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade700,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.emoji_events,
                          size: 32,
                          color: Colors.black,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ACHIEVEMENT UNLOCKED',
                                key: ValueKey('achievement_unlock_label'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                achievement.title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              _statRow('Score', '${summary.score}'),
              _statRow('Best chain', '\u00d7${summary.bestChain}'),
              _statRow('Fares delivered', '${summary.faresDelivered}'),
              _statRow('Close calls', '${summary.nearMisses}'),
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
                // The button's 80 px of horizontal padding plus 220 px of
                // 'DRIVE AGAIN' never fit a 320 pt phone's 200 px panel
                // column, and the label wrapped inside its own button
                // (issue #187). Scale-down keeps it one line at whatever
                // size fits.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    game.isDailyShift ? 'ENDLESS SHIFT' : 'DRIVE AGAIN',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              // The shareable score card (issue #22): the settled shift as
              // an image — score, chain, distance, date, the day's seed —
              // handed to the OS share sheet, the one outbound channel a
              // permanently offline game has. iOS only: the native half of
              // the channel lives in the AppDelegate, and the project
              // ships iOS only.
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
                const SizedBox(height: 8),
                ShareScoreButton(game: game, summary: summary),
              ],
              // Race the ghost (issue #20): the stored best run for the
              // day's course — often the very shift just settled —
              // replayed as a translucent car. Offered wherever a
              // daily-course shift ends, because that is the only place a
              // "subsequent attempt at the same day's course" exists: the
              // scoring attempt is spent, but racing yourself never is.
              // The offer is this panel's snapshot of the day; the tap
              // itself re-checks the day in [TaxiGame.raceGhost] and
              // refuses once midnight has passed it by (issue #96) — a
              // summary left open cannot hand out the next day's course.
              if ((game.isDailyShift || game.isGhostRace) &&
                  game.gameState.todayGhost != null) ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  key: const ValueKey('race_ghost_button'),
                  onPressed: () {
                    // In place, never stacked (issue #73): the button
                    // used to push a second GameScreen over this
                    // finished one, and the hidden game kept ticking —
                    // its per-frame engine-off fought the live race
                    // through the shared AudioService, and every MAIN
                    // MENU pop landed on an older summary. The restart
                    // tears this panel down and puts the race on the
                    // one route the shift already owns, exactly as
                    // DRIVE AGAIN does.
                    game.raceGhost();
                  },
                  icon: const Icon(Icons.flash_on),
                  // DRIVE AGAIN's rule (issue #187), one button down:
                  // the icon-plus-label row leaves this label less than
                  // DRIVE AGAIN's whole width, and 'RACE YOUR GHOST' at
                  // 18 px is more type than a 320 pt phone's 200 px
                  // panel column holds — the bare label wrapped into
                  // two lines inside its own button (issue #201). The
                  // same scale-down box keeps it one line at whatever
                  // size fits.
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'RACE YOUR GHOST',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  // MAIN MENU means the menu (issue #222): a run started
                  // from the Daily screen sits two routes above it, and a
                  // bare pop landed back on that Daily screen under this
                  // label — the player needed a second exit they were
                  // never told about. The first route is the menu on
                  // every stack this panel can appear over.
                  Navigator.of(context).popUntil((route) => route.isFirst);
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
          // The label yields, the value stays rigid (issue #187, after
          // the HUD scoring row's #43 rule): 'Fares delivered' is 225 px
          // of 15 px type against the 200 px column on a 320 pt phone,
          // and the bare Row overflowed with a flex exception. A whole-
          // row scale-down box would left-pack the row — unbounded width
          // leaves spaceBetween no free space to spend — so only the
          // label rides one, inside a loose Flexible: natural size
          // wherever it fits (the layout is unchanged on every wider
          // phone), scaled down alone when it does not.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.white70,
                ),
              ),
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
