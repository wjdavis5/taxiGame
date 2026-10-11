import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../game/systems/daily_shift.dart';
import '../../game/taxi_game.dart';
import '../../services/audio_service.dart';
import '../../services/game_state_service.dart';
import '../../services/haptics_service.dart';
import '../widgets/cab_button.dart';
import '../widgets/day_key_builder.dart';
import 'credits_screen.dart';
import 'city_license_screen.dart';
import 'daily_screen.dart';
import 'game_screen.dart';
import 'garage_screen.dart';
import 'records_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

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
                  // The wordmark (issue #264): the first screen is the
                  // identity judgement, so it opens on the game's own
                  // mark — the loading state's voice (issue #265's blue
                  // field, white type, yellow cab) grown into a cab-sign
                  // plate — instead of a bare centered Text. The scale-
                  // down box stays (#187): one line of ink at whatever
                  // width the phone offers.
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: _Wordmark(),
                  ),

                  const SizedBox(height: 40),

                  // Game stats
                  Consumer<GameStateService>(
                    builder: (context, gameState, child) {
                      return Column(
                        children: [
                          _buildStatRow(
                            // A school cap, not a star: stars read as
                            // ratings, and this number is the ladder
                            // rung. The wording matches the completion
                            // panel's 'TUTORIAL COMPLETE!'.
                            Icons.school,
                            gameState.tutorialComplete
                                ? 'TUTORIAL COMPLETE'
                                : 'Level ${gameState.currentLevel}',
                          ),
                          const SizedBox(height: 10),
                          _buildStatRow(
                            Icons.monetization_on,
                            '${gameState.totalCoins} Coins',
                          ),
                          // The next reachable goal (issue #282): the
                          // first screen a returning player sees names
                          // what they are chasing — the next car, the
                          // next open City License objective (issue #278),
                          // or the closest locked achievement — so
                          // progression stops being a garage price list.
                          if (gameState.nextGoal != null) ...[
                            const SizedBox(height: 14),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                gameState.nextGoal!.line,
                                key: const ValueKey('menu_next_goal'),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.yellow,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 60),

                  // The play modes, ordered by who is holding the phone
                  // (first-run hierarchy): a save still on the ladder
                  // leads with the ladder — the designed on-ramp that
                  // teaches pickups, timers, chains, and banking — with
                  // Endless and the one-attempt-a-day Daily standing
                  // back in white until the tutorial is done. A finished
                  // save keeps the retained player's order (issue #19
                  // put the day's ritual on top; issue #15 made Endless
                  // the headline beneath it).
                  Consumer<GameStateService>(
                    builder: (context, gameState, child) {
                      final firstRun = !gameState.tutorialComplete;
                      return Column(
                        children: [
                          if (firstRun) ...[
                            // The designed on-ramp, as the headline:
                            // the ladder teaches pickups, timers,
                            // chains, and banking (levels 9–10) before
                            // the game ever risks anything on the
                            // player.
                            _buildLadderButton(context, primary: true),
                            const SizedBox(height: 20),
                            _buildEndlessBlock(context, gameState,
                                primary: false),
                            const SizedBox(height: 20),
                            // The daily block is day-dependent, so it
                            // rebuilds when the calendar day does —
                            // resumed or left open across midnight —
                            // instead of showing yesterday's DONE FOR
                            // TODAY until an unrelated save write comes
                            // along (issue #113).
                            DayKeyBuilder(
                              builder: (context, dayKey) => _buildDailyBlock(
                                  context, gameState, dayKey,
                                  primary: false),
                            ),
                          ] else ...[
                            DayKeyBuilder(
                              builder: (context, dayKey) => _buildDailyBlock(
                                  context, gameState, dayKey,
                                  primary: true),
                            ),
                            const SizedBox(height: 20),
                            _buildEndlessBlock(context, gameState,
                                primary: true),
                            const SizedBox(height: 20),
                            _buildLadderButton(context, primary: false),
                          ],
                        ],
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

                  // City License board (issue #278): the post-tutorial
                  // challenge board — named, replayable objectives across
                  // banking, close calls, fare kinds, weather, and vehicle
                  // tradeoffs. It sits beside the garage because that is
                  // where its car objectives send a player back to.
                  _MenuButton(
                    buttonKey: const Key('license_button'),
                    icon: Icons.badge,
                    label: 'CITY LICENSE',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CityLicenseScreen(),
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

                  // Shift stats (issue #282): the mastery wall was
                  // reachable only through Settings, where a returning
                  // player never looks. It is a top-level destination
                  // beside Records — the two reading screens sit
                  // together.
                  _MenuButton(
                    buttonKey: const Key('stats_button'),
                    icon: Icons.query_stats,
                    label: 'SHIFT STATS',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const StatsScreen(),
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

  /// The hand-made career ladder button (issue #11's predecessor): one
  /// crash fails the level, and completion unlocks the next. While the
  /// ladder is unfinished this is the menu's headline action and its
  /// label says what it is for; a finished save keeps it as the plain
  /// PLAY it has always been (the handoff to Endless).
  Widget _buildLadderButton(
    BuildContext context, {
    required bool primary,
  }) {
    return _MenuButton(
      buttonKey: const Key('play_button'),
      icon: Icons.play_arrow,
      label: primary ? 'START DRIVING' : 'PLAY',
      primary: primary,
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const GameScreen(),
          ),
        );
      },
    );
  }

  /// Endless shift (issue #15): the headline mode for a retained player,
  /// one step back for a first-timer the ladder should reach first. A
  /// procedurally generated run (issue #11) — each shift gets a fresh
  /// seed, and the seed fully determines the course — with the score to
  /// beat right beneath it.
  Widget _buildEndlessBlock(
    BuildContext context,
    GameStateService gameState, {
    required bool primary,
  }) {
    return Column(
      children: [
        _MenuButton(
          buttonKey: const ValueKey('endless_button'),
          icon: Icons.all_inclusive,
          label: 'ENDLESS SHIFT',
          primary: primary,
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
        // The flagship rule, stated before the mode is ever entered
        // (issue #264): three crashes end the shift and every dropoff is
        // a bank-or-push call. Rides the scale-down box like the daily
        // status line (#201), one line at every width.
        const SizedBox(height: 10),
        const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '3 CRASHES END IT \u2014 BANK OR PUSH AT EVERY DROPOFF',
            key: ValueKey('endless_rule_status'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
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
  }

  /// The Date-seeded Daily Shift block (issue #19): one shared course a
  /// day, derived from the date — computed, never fetched, so the game
  /// stays fully offline. One attempt: once today's shift has ended, the
  /// button becomes the way back to the day's result instead of a replay
  /// — labelled as the destination it opens, not the state it is in. The
  /// history link exists only while today is unplayed; once the button
  /// itself opens the result screen, a second path to it is clutter.
  ///
  /// Built under a [DayKeyBuilder] (issue #113): [dayKey] is the day the
  /// card is being laid out for, so a day that rolls over under a live
  /// menu rebuilds the card rather than leaving yesterday's DONE FOR
  /// TODAY to hide the new course. Every part of the card — the result
  /// it branches on, the date it names, and the course its button starts
  /// — reads that one [dayKey] (issue #245), so the built day and the
  /// tapped day cannot disagree inside the midnight window.
  Widget _buildDailyBlock(
    BuildContext context,
    GameStateService gameState,
    String dayKey, {
    required bool primary,
  }) {
    // The card is a snapshot of the day it was built for (issue #113),
    // and every part of it reads that one day (issue #245): the result
    // it shows, the date it names, and the course its button starts. The
    // old shape read `todayDailyResult` and `DailyShift.todayKey` live
    // while the label rendered `dayKey`, so inside the midnight window a
    // save-notification rebuild showed D's label over D+1's course.
    final result = gameState.dailyResultFor(dayKey);
    return Column(
      children: [
        _MenuButton(
          buttonKey: const ValueKey('daily_button'),
          icon: result == null ? Icons.event : Icons.emoji_events,
          label: result == null ? 'DAILY SHIFT' : "TODAY'S RESULT",
          primary: primary,
          onPressed: () {
            if (result == null) {
              // The day's course: the seed derived from the day this
              // card was built for (issue #19's shared course, riding
              // issue #11's endless shift) — the same day the status
              // line above names (issue #245).
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GameScreen(
                    endlessSeed: DailyShift.seedForDateKey(dayKey),
                    isDailyShift: true,
                    dailyDateKey: dayKey,
                  ),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DailyScreen(),
                ),
              );
            }
          },
        ),
        const SizedBox(height: 10),
        // The status line rides the scale-down box (issue #201), the
        // menu title's own #187 idiom a few widgets up: the unplayed
        // branch — '$dayKey · ONE SHIFT, SAME FOR EVERYONE' — is more
        // type than the menu's padded column holds on a 320 pt phone,
        // and the bare Text wrapped it under the button. The key stays
        // on the Text itself: finders key on it, and the box around it
        // is transparent to them.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            result == null
                ? '$dayKey \u00b7 ONE SHIFT, '
                    'SAME FOR EVERYONE'
                : '${result.score} PTS \u00b7 DONE FOR TODAY',
            key: const ValueKey('daily_status'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 6),
        // The visible streak (issue #281): the current run and the best
        // ever. Read for the snapshot day the card was built for, so a
        // missed day reads 0 here without touching the stored run. Rides
        // the scale-down box like the status line above it (#201's idiom).
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'STREAK ${gameState.dailyStreakOn(dayKey)} \u00b7 '
            'BEST ${gameState.dailyBestStreak}',
            key: const ValueKey('daily_streak_status'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.yellow,
            ),
          ),
        ),
        const SizedBox(height: 6),
        // The ghost payoff, named before the first attempt (issue #264):
        // the shared course alone never said what it is for — the run you
        // set becomes the car you race. The Daily screen's own verb
        // (RACE YOUR GHOST) in the menu's scale-down idiom (#201).
        const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'RACE YOUR GHOST AFTER YOUR RUN',
            key: ValueKey('daily_ghost_status'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
        ),
        if (result == null)
          // The history link in the menu's own control language (issue
          // #264's follow-up): it was the one stock Material TextButton
          // left on the fresh-save menu, so the first screen's claim —
          // every action is a CabButton — was one control short of true.
          // The compact face keeps the link subordinate to the modes.
          _MenuButton(
            buttonKey: const ValueKey('daily_history_button'),
            icon: Icons.history,
            label: 'DAILY HISTORY',
            compact: true,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DailyScreen(),
                ),
              );
            },
          ),
      ],
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

/// The menu's press wrapper (issue #264): keeps the route guard and the
/// click/tick feedback (issues #4, #5, #220) in one place, and hands the
/// face to [CabButton] — the menu's own control language, not a stock
/// Material button.
class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Key? buttonKey;

  /// Primary buttons are the menu's headline actions: bigger, in the
  /// app's signature yellow. Everything else steps back in white.
  final bool primary;

  /// The compact face for the menu's secondary links (issue #264's
  /// follow-up) — the Daily History link.
  final bool compact;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.buttonKey,
    this.primary = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return CabButton(
      key: buttonKey,
      icon: icon,
      label: label,
      primary: primary,
      compact: compact,
      // Every menu press clicks (issue #4) and ticks (issue #5), then
      // does its job. The route guard comes first (issue #220): a stray
      // second tap from the push transition — the menu stays
      // hit-testable until the incoming route turns opaque — used to
      // push a second screen over the first, and two live games stacked.
      // Only the current route's buttons act.
      onPressed: () {
        if (ModalRoute.of(context)?.isCurrent != true) return;
        audioOf(context)?.playButtonSound();
        hapticsOf(context)?.buttonPress();
        onPressed();
      },
    );
  }
}

/// The Cab Hustle wordmark (issue #264): the loading state's voice
/// (issue #265) as a mark — a dark plate with the yellow rim and the
/// taxi, the wordmark in the loading state's white, letterspaced type.
/// The mark is the first thing a fresh save shows, and it is the game's
/// own, not Flutter's.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('cab_hustle_wordmark'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.yellow, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            offset: Offset(0, 6),
            blurRadius: 0,
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_taxi, size: 40, color: Colors.yellow),
          SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'CAB HUSTLE',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
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
    );
  }
}
