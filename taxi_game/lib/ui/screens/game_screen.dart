import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:provider/provider.dart';

import '../../game/taxi_game.dart';
import '../../services/audio_service.dart';
import '../../services/game_state_service.dart';
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
  });

  /// When non-null, the screen runs an endless procedural shift seeded
  /// with this value instead of the next hand-made level (issue #11).
  final int? endlessSeed;

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
  late final TaxiGame game;

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
    game = TaxiGame(
      levelLoader: context.read<LevelLoaderService>(),
      gameState: context.read<GameStateService>(),
      audio: context.read<AudioService>(),
      endlessSeed: widget.endlessSeed,
      isDailyShift: widget.isDailyShift,
      isGhostRace: widget.isGhostRace,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Game widget (full screen)
          GameWidget(
            game: game,
            overlayBuilderMap: {
              'hud': (context, TaxiGame game) => HudOverlay(game: game),
              // The one-time stick-control hint (issue #37): active from
              // the first frame when [showControlHint], removed by the
              // first real stick touch.
              'controlHint': (context, TaxiGame game) =>
                  const ControlHintOverlay(),
              'pauseMenu': (context, TaxiGame game) => _buildPauseMenu(context),
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
    );
  }

  Widget _buildPauseMenu(BuildContext context) {
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
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                game.audio?.playButtonSound();
                game.resumeGame();
              },
              child: const Text('RESUME'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                game.audio?.playButtonSound();
                Navigator.of(context).pop();
              },
              child: const Text('MAIN MENU'),
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
class LevelCompleteOverlay extends StatelessWidget {
  const LevelCompleteOverlay({super.key, required this.game});

  final TaxiGame game;

  @override
  Widget build(BuildContext context) {
    final handoff = !game.hasNextLevel;

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
            Text(
              handoff ? 'TUTORIAL COMPLETE!' : 'LEVEL COMPLETE!',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            // The payout line (issue #34): a banked level was paid the
            // chain score at the dropoff — the flat reward was forfeited
            // with the undelivered fares — so the bank is the payout the
            // panel names. Any other completion pays the flat reward.
            Text(
              game.lastBankedScore != null
                  ? 'Banked: +${game.lastBankedScore} Coins'
                  : '+${game.currentLevel.coinReward} Coins',
              style: const TextStyle(
                fontSize: 24,
                color: Colors.yellow,
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
            const SizedBox(height: 30),
            handoff
                ? ElevatedButton(
                    onPressed: () {
                      game.audio?.playButtonSound();
                      game.startFirstShift();
                    },
                    child: const Text('START SHIFT'),
                  )
                : ElevatedButton(
                    onPressed: () async {
                      game.audio?.playButtonSound();
                      await game.startNextLevel();
                    },
                    child: const Text('NEXT LEVEL'),
                  ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                game.audio?.playButtonSound();
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

/// The crash overlay. Names what hit the player and how fast, from the
/// telemetry recorded at the moment of contact (issue #6).
class LevelFailedOverlay extends StatelessWidget {
  const LevelFailedOverlay({super.key, required this.game});

  final TaxiGame game;

  @override
  Widget build(BuildContext context) {
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
            const Text(
              'CRASH!',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              game.lastImpact?.explanation ?? 'You collided with traffic.',
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
                game.restartLevel();
              },
              child: const Text('RETRY'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                game.audio?.playButtonSound();
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
