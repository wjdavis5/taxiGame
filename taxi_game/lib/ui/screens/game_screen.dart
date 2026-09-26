import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:provider/provider.dart';

import '../../game/taxi_game.dart';
import '../../services/game_state_service.dart';
import '../../services/level_loader_service.dart';
import '../widgets/bank_prompt_overlay.dart';
import '../widgets/hud_overlay.dart';
import '../widgets/run_summary_panel.dart';

/// Game screen that contains the actual game widget
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.endlessSeed});

  /// When non-null, the screen runs an endless procedural shift seeded
  /// with this value instead of the next hand-made level (issue #11).
  final int? endlessSeed;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final TaxiGame game;

  @override
  void initState() {
    super.initState();
    game = TaxiGame(
      levelLoader: context.read<LevelLoaderService>(),
      gameState: context.read<GameStateService>(),
      endlessSeed: widget.endlessSeed,
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
            initialActiveOverlays: const ['hud'],
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
                game.resumeGame();
              },
              child: const Text('RESUME'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
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
            Text(
              '+${game.currentLevel.coinReward} Coins',
              style: const TextStyle(
                fontSize: 24,
                color: Colors.yellow,
              ),
            ),
            // A bank's payout, for the levels that teach banking (issue
            // #16): the chain score converted to coins at the dropoff.
            // Null unless a bank happened this level.
            if (game.lastBankedScore != null)
              Text(
                'Banked: +${game.lastBankedScore} score',
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
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
                    onPressed: game.startFirstShift,
                    child: const Text('START SHIFT'),
                  )
                : ElevatedButton(
                    onPressed: () async {
                      await game.startNextLevel();
                    },
                    child: const Text('NEXT LEVEL'),
                  ),
            const SizedBox(height: 10),
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
                game.restartLevel();
              },
              child: const Text('RETRY'),
            ),
            const SizedBox(height: 10),
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
    );
  }
}
