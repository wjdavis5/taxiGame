import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../game/systems/daily_shift.dart';
import '../../game/taxi_game.dart';
import '../../services/audio_service.dart';
import '../../services/game_state_service.dart';
import '../../services/haptics_service.dart';
import '../widgets/day_key_builder.dart';
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
                  //
                  // The scale-down box (issue #187): 'CAB HUSTLE' at 48 px
                  // is ~480 px of bold type, and the 280 px left on a
                  // 320 pt iPhone wrapped the title into two flush-left
                  // lines — the menu's headline, broken on the oldest
                  // phones still running iOS 15. The garage/HUD/completion
                  // idiom (issues #156, #159): one line, laid out under
                  // unbounded width, scaled down to whatever fits.
                  const Padding(
                    padding: EdgeInsets.all(20.0),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
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
  /// TODAY to hide the new course.
  Widget _buildDailyBlock(
    BuildContext context,
    GameStateService gameState,
    String dayKey, {
    required bool primary,
  }) {
    final result = gameState.todayDailyResult;
    return Column(
      children: [
        _MenuButton(
          buttonKey: const ValueKey('daily_button'),
          icon: result == null ? Icons.event : Icons.emoji_events,
          label: result == null ? 'DAILY SHIFT' : "TODAY'S RESULT",
          primary: primary,
          onPressed: () {
            if (result == null) {
              // The day's course: the seed derived from today's date
              // (issue #19's shared course, riding issue #11's endless
              // shift).
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
        if (result == null)
          TextButton(
            key: const ValueKey('daily_history_button'),
            onPressed: () {
              // The same transition guard as the menu buttons (issue
              // #220): this link is a push too.
              if (ModalRoute.of(context)?.isCurrent != true) return;
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
      icon: Icon(icon, size: primary ? 34 : 32),
      // Every menu label rides the scale-down box (issue #208, the
      // title's #187 idiom one screen up): on a 320 pt iPhone the
      // button's padding and icon leave ~190 px of label slot, and the
      // widest labels — START DRIVING, TODAY'S RESULT — wrapped into
      // two flush-left lines there. One line of ink, shrunk to whatever
      // fits; text finders key on the Text inside, so nothing that
      // looks the label up notices the box.
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: TextStyle(
            fontSize: primary ? 26 : 22,
            fontWeight: FontWeight.bold,
          ),
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
