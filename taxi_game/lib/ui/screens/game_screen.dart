import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:provider/provider.dart';

import '../../game/taxi_game.dart';
import '../../services/audio_service.dart';
import '../../services/game_state_service.dart';
import '../../services/haptics_service.dart';
import '../../services/level_loader_service.dart';
import '../widgets/bank_prompt_overlay.dart';
import '../widgets/control_hint_overlay.dart';
import '../widgets/hud_overlay.dart';
import '../widgets/run_summary_panel.dart';

/// Game screen that contains the actual game widget
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.endlessSeed,
    this.isDailyShift = false,
    this.isGhostRace = false,
    this.dailyDateKey,
  });

  /// When non-null, the screen runs an endless procedural shift seeded
  /// with this value instead of the next hand-made level (issue #11).
  final int? endlessSeed;

  /// The calendar day [endlessSeed] was derived from, when this screen is
  /// a run on the daily course (issue #248): the scoring Daily Shift or
  /// its ghost race. The caller that derives the seed from the date
  /// passes the same day here, and the game pins its result and ghost
  /// keys from it — never from a second clock read that could cross
  /// midnight and pin the next day to this day's course.
  final String? dailyDateKey;

  /// True when [endlessSeed] is today's date-derived course and this
  /// screen is the player's one Daily Shift (issue #19) — the flag rides
  /// to the game, which records the day's result when the shift ends.
  final bool isDailyShift;

  /// True when this screen is a ghost race (issue #20): the day's course
  /// again — [endlessSeed] set to the daily seed — after the one scoring
  /// attempt is spent, with the stored best run riding along as a
  /// translucent ghost. Records no daily result; keeps no retry.
  final bool isGhostRace;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late TaxiGame game;

  /// True when this session's save has never dismissed the stick-control
  /// hint (issue #37): the first game start — level, endless, daily,
  /// ghost race — then renders the hint until a thumb lands on the stick
  /// ([TaxiGame.onStickEngaged]). A save that has already dismissed it —
  /// every save older than this feature among them — never sees it
  /// again. Decided here rather than inside the game so the hint rides
  /// the [GameWidget]'s own `initialActiveOverlays`: Flame requires a
  /// builder to be registered before its overlay can be added, and the
  /// registry is exactly what this screen owns.
  late final bool showControlHint;

  @override
  void initState() {
    super.initState();
    showControlHint =
        !context.read<GameStateService>().controlHintDismissed;
    game = _createGame();
  }

  /// Builds the game this screen drives — shared by the initial load and
  /// the failed load's RETRY (issue #241). Carries the daily's date key
  /// through (issue #248) so the run pins the day its seed came from.
  TaxiGame _createGame() => TaxiGame(
        levelLoader: context.read<LevelLoaderService>(),
        gameState: context.read<GameStateService>(),
        audio: context.read<AudioService>(),
        haptics: context.read<HapticsService>(),
        endlessSeed: widget.endlessSeed,
        isDailyShift: widget.isDailyShift,
        isGhostRace: widget.isGhostRace,
        dailyDateKey: widget.dailyDateKey,
      );

  /// A fresh game for the failed load's RETRY (issue #241): a game whose
  /// load threw cannot be re-loaded in place, and flame's GameWidget
  /// re-runs the whole load when its `game` instance changes.
  void _retryLoad() {
    setState(() => game = _createGame());
  }

  @override
  Widget build(BuildContext context) {
    // The run may only end through its own surfaces (issue #81). iOS
    // edge back-swipes and the system back button both popped this
    // route raw: a steer that starts at the left bezel quit the shift
    // mid-flight with no confirmation, forfeiting the at-risk score the
    // pause menu exists to name. `canPop: false` makes the route's
    // popDisposition `doNotPop`, which kills the Cupertino edge
    // recognizer at pointer-down — the swipe becomes an ordinary touch
    // the game steers with — and turns a system back into a vetoed pop
    // that lands in [onPopInvokedWithResult] instead of the navigator.
    // The veto routes to [TaxiGame.pauseGame]: the shift freezes behind
    // the menu that already states the stake, and quitting becomes the
    // deliberate act it always should have been. Every explicit exit —
    // the pause menu's quit, the summaries' buttons — pops
    // imperatively via `Navigator.pop`, which never consults
    // popDisposition, so none of them is touched. [pauseGame]'s own
    // guards keep a veto arriving while the bank primer holds the world
    // or a summary owns the screen a no-op rather than a stacked menu.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        game.pauseGame();
      },
      child: Scaffold(
      // The fixed-resolution viewport letterboxes on any screen taller
      // than its 400x800 frame, and the game's world used to run under
      // the status bar through that top band (issue #45) — pickup rings
      // and traffic brushing the Wi-Fi and battery icons. A top-only
      // SafeArea drops the game just below the bar, and the strip it
      // exposes is painted the same colour the game paints outside its
      // viewport ([TaxiGame.backgroundColor]), so bar band and letterbox
      // read as one edge-to-edge frame. On the 402x874 and 420x912
      // devices the report came from, the inset eats the top band
      // outright: the viewport that remains is barely taller than 2:1,
      // so the visible letterboxing collapses to a sliver at the bottom.
      // The bottom stays un-inset on purpose — the HUD's chip band and
      // the stick both live at the top of the frame, and the home
      // indicator's swipe area belongs to the system.
      body: ColoredBox(
        color: game.backgroundColor(),
        child: SafeArea(
          top: true,
          bottom: false,
          left: false,
          right: false,
          child: Stack(
            children: [
              // Game widget (full screen)
              GameWidget(
                game: game,
                // A game whose load throws gets a real recovery surface
                // (issue #241), not flame's raw error box: the route
                // vetoes back ([PopScope] above), so the red screen left
                // the player stuck. RETRY rebuilds the game — a load
                // that can simply run again does — and MAIN MENU leaves
                // the route.
                errorBuilder: _buildLoadError,
                overlayBuilderMap: {
                  'hud': (context, TaxiGame game) => HudOverlay(game: game),
                  // The one-time stick-control hint (issue #37): active from
                  // the first frame when [showControlHint], removed by the
                  // first real stick touch. Carries the game so the pill
                  // can park below the cab's tail wherever the mode's
                  // camera frames it (issue #177).
                  'controlHint': (context, TaxiGame game) =>
                      ControlHintOverlay(game: game),
                  'pauseMenu': (context, TaxiGame game) =>
                      _buildPauseMenu(context),
                  'levelComplete': (context, TaxiGame game) =>
                      LevelCompleteOverlay(game: game),
                  'levelFailed': (context, TaxiGame game) =>
                      LevelFailedOverlay(game: game),
                  // The end-of-shift run summaries (issues #14, #15): the
                  // wrecked shift names its forfeit, the banked one celebrates
                  // its payout, and both show the full run's numbers.
                  'shiftWrecked': (context, TaxiGame game) => RunSummaryPanel(
                        game: game,
                        // Finalized in the same call stack that added this
                        // overlay — the snapshot always precedes the panel.
                        summary: game.lastRunSummary!,
                      ),
                  // The timed bank-or-push choice at every endless dropoff
                  // (issue #13) — asked over live traffic, not a modal.
                  'bankOrPush': (context, TaxiGame game) =>
                      BankPromptOverlay(game: game),
                  'shiftBanked': (context, TaxiGame game) => RunSummaryPanel(
                    game: game,
                    summary: game.lastRunSummary!,
                  ),
                },
                // The hint rides the initial overlays so Flame registers its
                // builder before it is ever added (issue #37).
                initialActiveOverlays: [
                  'hud',
                  if (showControlHint) 'controlHint',
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  /// The load failure's recovery surface (issue #241), rendered by the
  /// [GameWidget]'s `errorBuilder` in place of flame's raw error box.
  /// MAIN MENU always leaves the failed route; RETRY rebuilds the game,
  /// which re-runs the whole load — the plausible recovery for the
  /// failures that can simply run again. The level's number is named
  /// when the throw carries it.
  Widget _buildLoadError(BuildContext context, Object error) {
    final levelNumber =
        error is LevelLoadException ? error.levelNumber : null;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            const Text(
              'COULD NOT START',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              levelNumber != null
                  ? 'Level $levelNumber could not be loaded.'
                  : 'The level could not be loaded.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const ValueKey('game_load_retry_button'),
              onPressed: _retryLoad,
              child: const Text('RETRY'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const ValueKey('game_load_menu_button'),
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text(
                'MAIN MENU',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPauseMenu(BuildContext context) {
    // The at-risk stake (issue #5): quitting an endless run forfeits the
    // unbanked score silently, so the menu names the number — and offers
    // the bank as the exit that keeps it. A level or a scoreless run has
    // nothing at stake, and the menu stays the plain two buttons. A
    // shift that already settled has nothing at stake either (issue
    // #52): the score has been paid or forfeited, and this menu can only
    // be open from before the ending — the summary owns the screen now.
    final atRisk =
        game.isEndless && !game.isShiftOver ? game.score : 0;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PAUSED',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (atRisk > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$atRisk coins at risk',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
              ),
            ],
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                game.audio?.playButtonSound();
                game.haptics?.buttonPress();
                game.resumeGame();
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 40, vertical: 12),
              ),
              child: const Text('RESUME'),
            ),
            if (atRisk > 0) ...[
              const SizedBox(height: 10),
              ElevatedButton(
                key: const ValueKey('pause_bank_button'),
                onPressed: () {
                  game.audio?.playButtonSound();
                  game.haptics?.buttonPress();
                  game.bankFromPause();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellow,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 30, vertical: 12),
                ),
                child: Text(
                  'BANK $atRisk & QUIT',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextButton(
              key: const ValueKey('pause_quit_button'),
              onPressed: () {
                game.audio?.playButtonSound();
                game.haptics?.buttonPress();
                // The label names the exit (issue #222): MAIN MENU goes
                // all the way to the first route, while QUIT — a run
                // abandoned with coins at risk — steps back one route to
                // where the run started, which on the daily path is the
                // Daily screen that owns the still-unspent attempt.
                if (atRisk > 0) {
                  Navigator.of(context).pop();
                } else {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
              child: Text(
                atRisk > 0 ? 'QUIT — $atRisk LOST' : 'MAIN MENU',
                style: const TextStyle(color: Colors.white),
              ),
            ),
            // The daily's one attempt survives an abandoned run — but
            // only an abandoned one (issue #206). BANK & QUIT above
            // settles the shift, and a settled daily records its result
            // for the day: the attempt is spent. With a score at risk
            // the note must say both halves, because the old blanket
            // line read as describing the button it sat under; scoreless
            // there is no bank on offer and quitting is the only exit,
            // so the plain reassurance stands. The branch loses the
            // widget's `const`, and the at-risk line centres across its
            // two wrapped lines in the narrow panel.
            if (game.isDailyShift)
              Text(
                atRisk > 0
                    ? "Quitting keeps today's daily attempt. "
                        'Banking ends it.'
                    : "Today's daily attempt is saved.",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }
}

/// The level-complete overlay, shared by the whole tutorial ladder.
///
/// Past the last rung it stops offering a NEXT LEVEL button that can only
/// dead-end (issue #16) and becomes the handoff: the ladder is finished,
/// the button starts the player's first endless shift in the same
/// session. Public and self-contained so the ladder tests can pump it
/// directly, like [LevelFailedOverlay].
class LevelCompleteOverlay extends StatefulWidget {
  const LevelCompleteOverlay({super.key, required this.game});

  final TaxiGame game;

  @override
  State<LevelCompleteOverlay> createState() => _LevelCompleteOverlayState();
}

class _LevelCompleteOverlayState extends State<LevelCompleteOverlay> {
  /// True once this panel's NEXT LEVEL load failed (issue #241): the
  /// rung is unreadable, so the button turns dead and the panel says
  /// why. A retry is not offered from here because the failed load has
  /// already advanced the game's rung counter — asking again would skip
  /// the rung it could not read.
  bool _loadFailed = false;

  Future<void> _nextLevel() async {
    final game = widget.game;
    game.audio?.playButtonSound();
    game.haptics?.buttonPress();
    try {
      // The panel is deliberately still up while this runs: the game
      // retires it only once the load has landed (issue #241).
      await game.startNextLevel();
    } on LevelLoadException {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    // The completion's exit is the ladder and the save (issue #229),
    // never an asset probe: the ladder says whether a rung follows, and
    // the save says whether the tutorial was actually finished. A probe
    // answering "missing" for a declared inner rung used to be read as
    // "tutorial complete" right here and handed the player an Endless
    // shift mid-ladder; if the rung really cannot load, the NEXT LEVEL
    // load fails loudly instead of a silent swap.
    final handoff = !game.hasNextLevel && game.gameState.tutorialComplete;

    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: handoff ? Colors.amber.shade800 : Colors.green.shade700,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              handoff ? Icons.local_taxi : Icons.check_circle,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            // The ladder's finish line (issue #159): "TUTORIAL
            // COMPLETE!" is wider than the panel on every standard
            // iPhone (296 px of bold type in a 255-273 px panel), and a
            // bare Text wrapped into two flush-left lines while
            // everything around it sat centred. The garage/HUD
            // scale-down idiom (issues #156, #43 and #57): the box lays
            // the title out under unbounded width — always one line —
            // and scales it down to fit, the default centre alignment
            // keeping it centred whether scaled or natural.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                handoff ? 'TUTORIAL COMPLETE!' : 'LEVEL COMPLETE!',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            // The rung's authored name ('First Ride', 'Bank It') — the
            // ladder's flavor, finally on screen where it was written
            // for.
            if (!handoff && game.currentLevelName != null) ...[
              const SizedBox(height: 4),
              Text(
                'Level ${game.currentLevelNumber} — ${game.currentLevelName}',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
            ],
            const SizedBox(height: 10),
            // The payout line (issue #34): a banked level was paid the
            // chain score at the dropoff — the flat reward was forfeited
            // with the undelivered fares — so the bank is the payout the
            // panel names. Any other completion names what it was
            // actually credited (issue #155): the banking rungs' unbanked
            // finish pays the better of the chain score and the flat
            // reward, so the line reads the settled payout — falling back
            // to the level's authored reward before any completion has
            // settled one.
            // The payout rides the scale-down box (issue #201), the
            // summary panel's own payout idiom (#187) one screen over:
            // 'Banked: +125 Coins' at 24 px is wider than the ~200 px
            // column a 320 pt phone leaves this panel, and the bare
            // Text wrapped the payout into two lines. One widget covers
            // both branches, so one box carries them — whichever line
            // the settled level earned, it stays one line.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                game.lastBankedScore != null
                    ? 'Banked: +${game.lastBankedScore} Coins'
                    : '+${game.lastCompletionPayout ?? game.currentLevel.coinReward} Coins',
                style: const TextStyle(
                  fontSize: 24,
                  color: Colors.yellow,
                ),
              ),
            ),
            // The run's fare-chain score (issue #12): the number a replay
            // tries to beat.
            Text(
              'Score: ${game.score}',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            if (handoff) ...[
              const SizedBox(height: 10),
              const Text(
                'You know the ropes — fares, chains, banking.\n'
                'Your shift starts now.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ],
            // The failed advance's explanation (issue #241): the rung
            // the bundle declares but cannot hand over. The panel stays,
            // the message names what happened, and MAIN MENU is the way
            // off the frozen world.
            if (_loadFailed) ...[
              const SizedBox(height: 10),
              const Text(
                'The next level could not be loaded.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.white),
              ),
            ],
            const SizedBox(height: 30),
            handoff
                ? ElevatedButton(
                    onPressed: () {
                      game.audio?.playButtonSound();
                      game.haptics?.buttonPress();
                      game.startFirstShift();
                    },
                    child: const Text('START SHIFT'),
                  )
                : ElevatedButton(
                    // A rung that failed to load turns the button dead
                    // (issue #241): the handler answers the throw with
                    // the message above, and the failed load has already
                    // advanced the rung counter — a second ask would
                    // skip the rung it could not read.
                    onPressed: _loadFailed ? null : _nextLevel,
                    child: const Text('NEXT LEVEL'),
                  ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                game.audio?.playButtonSound();
                game.haptics?.buttonPress();
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
    );
  }
}

/// The level-failure overlay. Names what ended the run — a crash, from
/// the telemetry recorded at the moment of contact (issue #6), or a fare
/// stranded behind the one-way cab (issue #112) — and offers the rung
/// again: RETRY restarts it from below every zone.
class LevelFailedOverlay extends StatelessWidget {
  const LevelFailedOverlay({super.key, required this.game});

  final TaxiGame game;

  @override
  Widget build(BuildContext context) {
    // The two endings share the panel's machinery and differ in every
    // word: a missed fare is the player's own route gone wrong, not
    // something traffic did to them.
    final missedFare = game.lastFailReason == LevelFailReason.fareMissed;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cancel,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            // The completion panel's #159 fix, 130 lines below its first
            // use: 'FARE MISSED!' is 384 px of bold type against the
            // 200 px this panel's column offers on a 320 pt phone, and
            // the bare Text wrapped into two flush-left lines while the
            // panel sat centred (issue #187). The scale-down box lays
            // the title out under unbounded width — always one line —
            // and shrinks it to fit, centred either way.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                missedFare ? 'FARE MISSED!' : 'CRASH!',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              missedFare
                  ? 'You drove past a fare this level still needs — the '
                      'street only runs one way.'
                  : game.lastImpact?.headline ??
                      'You collided with traffic.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                game.audio?.playButtonSound();
                game.haptics?.buttonPress();
                game.restartLevel();
              },
              child: const Text('RETRY'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                game.audio?.playButtonSound();
                game.haptics?.buttonPress();
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
    );
  }
}
