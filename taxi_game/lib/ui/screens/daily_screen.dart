import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/systems/daily_shift.dart';
import '../../models/daily_result.dart';
import '../../models/ghost_trace.dart';
import '../../services/audio_service.dart';
import '../../services/game_state_service.dart';
import '../../services/haptics_service.dart';
import '../widgets/day_key_builder.dart';
import 'game_screen.dart';

/// The Daily Shift screen (issue #19): today's result up top, the player's
/// daily history below.
///
/// The daily's comparison is social — no leaderboard, no server, no
/// accounts — so this screen is what a player checks before screenshotting
/// their score for the group chat: what today's course paid them, and the
/// run of days behind it. Everything is read from local storage; the
/// shared course itself is derived from the date, never fetched.
class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('daily_screen'),
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
                      key: const Key('daily_back_button'),
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
                          'DAILY SHIFT',
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
              // Both cards below are snapshots of the day they were
              // built for, and the day can change under a screen left
              // open or an app resumed the next morning (issue #113):
              // each rebuilds when the calendar day does, so a new day
              // shows its own unplayed card and moves yesterday's
              // result into the history below.
              DayKeyBuilder(
                builder: (context, _) => Consumer<GameStateService>(
                  builder: (context, gameState, _) => _TodayCard(
                    result: gameState.todayDailyResult,
                    ghost: gameState.todayGhost,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text(
                  'HISTORY',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.yellow,
                  ),
                ),
              ),
              Expanded(
                child: DayKeyBuilder(
                  builder: (context, dayKey) =>
                      Consumer<GameStateService>(
                    builder: (context, gameState, _) {
                      // The day whose result belongs to the history's
                      // "past" — the day this block was built for, so
                      // the rows can never disagree with the today card
                      // above them mid-rebuild.
                      final today = dayKey;
                      // Today has its card above; the history is the days
                      // behind it, newest first.
                      final past = gameState.dailyHistory
                          .where((result) => result.dateKey != today)
                          .toList()
                        ..sort((a, b) => b.dateKey.compareTo(a.dateKey));
                      return past.isEmpty
                          ? _EmptyHistory(
                              todayPlayed: gameState.todayDailyComplete,
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(24, 0, 24, 24),
                              itemCount: past.length,
                              itemBuilder: (context, index) =>
                                  _HistoryRow(result: past[index]),
                            );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today's result, or the invitation to go play it while the day lasts.
/// With a ghost stored for today (issue #20) it is also where the day's
/// replay lives: a later-in-the-day visit can race the best run without
/// replaying the daily from the summary panel.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.result, this.ghost});

  final DailyResult? result;

  /// The stored best run for today's course; null until a run on it has
  /// ever finished.
  final GhostTrace? ghost;

  @override
  Widget build(BuildContext context) {
    final played = result != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        key: const Key('daily_today_card'),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.event, color: Colors.yellow, size: 22),
                const SizedBox(width: 8),
                Text(
                  DailyShift.todayKey,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // The score group yields before the chip does (issue #157):
            // nothing in this row could shrink, so a five-digit day on a
            // 320 pt phone shoved the BANKED/WRECKED chip 16–50 px past
            // the card's edge. The HUD's scale-down idiom (issues #43 and
            // #57): the number and its label render at natural size while
            // they fit and scale down together when they do not, while
            // the chip stays rigid — the outcome is one fixed-width badge
            // either way. Score and PTS must share the one FittedBox:
            // a scaled FittedBox reports its child's *unscaled* baseline
            // to this outer Row, so their baseline alignment has to live
            // inside the pre-scale layout to survive shrinking. That same
            // unscaled baseline is why this outer Row centers instead of
            // baseline-aligning (issue #161): a chip aligned to the
            // reported baseline hung 4–12 px below the number once the
            // scale-down engaged, because the baseline the Row measured
            // against never shrank. Centering is scale-independent — the
            // FittedBox's own box scales with its child, so the chip's
            // center rides the painted number's center at every factor.
            played
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${result!.score}',
                                key: const Key('daily_today_score'),
                                style: const TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.yellow,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'PTS',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      _OutcomeChip(banked: result!.banked),
                    ],
                  )
                : const Text(
                    'No shift yet today.',
                    key: Key('daily_today_unplayed'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
            const SizedBox(height: 10),
            Text(
              played
                  ? 'Done for today — a new course arrives tomorrow.'
                  : 'One shift a day, and every player in the world gets '
                      'the same course. How far can you take it?',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            // Start today's shift (issue #64): the invitation above was
            // dead copy without this — a player who arrived through the
            // menu's DAILY HISTORY link (which exists only while today
            // is unplayed) met the day's course described and no way to
            // drive it. The same route the menu's unplayed daily button
            // takes: the date-derived seed and the one-attempt flag.
            // Once the day is played the button is gone — the attempt is
            // spent, and only the ghost race remains below.
            if (!played) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                key: const Key('daily_start_button'),
                onPressed: () {
                  // The app-wide click (issue #4) and tick (issue #5)
                  // every button press gets, null-safe like _MenuButton —
                  // a missing provider must never break the button.
                  audioOf(context)?.playButtonSound();
                  hapticsOf(context)?.buttonPress();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GameScreen(
                        endlessSeed:
                            DailyShift.seedForDateKey(DailyShift.todayKey),
                        isDailyShift: true,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text(
                  "START TODAY'S SHIFT",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellow,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
            // Race the ghost (issue #20): the day's one scoring attempt
            // is spent, but racing the stored best run — replayed as a
            // translucent car on the same course — never is. Only on a
            // played day, and only when a trace exists to race.
            if (played && ghost != null) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                key: const Key('daily_race_ghost_button'),
                onPressed: () {
                  // The day this card was built for (issue #96): the
                  // card is a Consumer snapshot, so a screen left open
                  // across midnight still shows D's result — and this
                  // tap used to re-read `todayKey` (D+1), driving D+1's
                  // never-shared course as ghostless free practice whose
                  // trace then became D+1's ghost. The card's own day is
                  // the only one it may race; once it is no longer
                  // today, the tap does nothing.
                  if (result!.dateKey != DailyShift.todayKey) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GameScreen(
                        endlessSeed:
                            DailyShift.seedForDateKey(result!.dateKey),
                        isGhostRace: true,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.flash_on, size: 20),
                label: const Text(
                  'RACE YOUR GHOST',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellow,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// How the day's shift ended: paid out, or forfeited — the same
/// bank-vs-wreck wording the stats screen uses.
class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({required this.banked});

  final bool banked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: banked ? Colors.yellow : Colors.red.shade300,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        banked ? 'BANKED' : 'WRECKED',
        key: ValueKey('daily_outcome_${banked ? 'banked' : 'wrecked'}'),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
    );
  }
}

/// One past day in the history: its date, its score, and how it ended.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.result});

  final DailyResult result;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                result.dateKey,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.white70,
                ),
              ),
            ),
            Icon(
              result.banked ? Icons.savings : Icons.car_crash,
              size: 18,
              color: result.banked ? Colors.yellow : Colors.red.shade200,
            ),
            const SizedBox(width: 10),
            Text(
              '${result.score}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The history's empty state, worded for what is actually empty. The
/// history is the *past* days — today has its own card above — so a
/// player who just finished today's shift has not "completed no shifts":
/// the completed one is on screen right above (issue #44). Their empty
/// history is about yesterdays, and the invitation is tomorrow's course.
/// The fresh player, with nothing played at all, still gets the plain
/// truth.
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.todayPlayed});

  /// True when today's shift has been played — its card sits above this
  /// message.
  final bool todayPlayed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        todayPlayed
            ? 'No past daily shifts yet — come back tomorrow for a new course.'
            : 'No completed daily shifts yet.',
        key: const Key('daily_empty_history'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}
