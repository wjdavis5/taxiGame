import 'dart:async';

import 'package:flutter/material.dart';

import '../../game/systems/bank_prompt.dart';
import '../../game/systems/fare_chain.dart';
import '../../game/taxi_game.dart';
import 'hud_overlay.dart';

/// The bank-or-push choice at every endless dropoff (issue #13).
///
/// This is a question asked over live traffic, not a modal: only the panel
/// itself absorbs touches, so the player can keep driving straight through
/// it — steering, picking up, everything. If [BankPrompt.windowSeconds]
/// pass without an answer the game resolves the prompt to "push on" and
/// removes it; this widget also renders nothing whenever the prompt is not
/// active, so a resolution can never flash a stale choice.
///
/// Like the HUD's scoring bar, it polls the game on a short timer — the
/// countdown only reads to a tenth of a second, so that is plenty.
class BankPromptOverlay extends StatefulWidget {
  const BankPromptOverlay({super.key, required this.game});

  final TaxiGame game;

  @override
  State<BankPromptOverlay> createState() => _BankPromptOverlayState();
}

class _BankPromptOverlayState extends State<BankPromptOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// The bar heats up as the window closes, mirroring the fare timer's
  /// language: white, then orange, then red.
  static Color _barColorFor(double secondsLeft) {
    if (secondsLeft <= 1.2) return Colors.red;
    if (secondsLeft <= 2.5) return Colors.orange;
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final prompt = widget.game.bankPrompt;
    final chain = widget.game.fareChain;

    if (!prompt.isActive) return const SizedBox.shrink();

    final nextMultiplier = chain.multiplier + FareChain.pushBonusStep;

    // Parked below the HUD's whole top band — which in a ghost race is
    // one line taller than the fixed 120 px accounted for: the
    // ghost-gap badge sits on its own line under the scoring row
    // (issues #43, #121), and the panel paints above the HUD (the
    // overlays stack in the order they were added), so the old offset
    // covered 36 of the badge's 37 px for the whole decision window
    // (issue #130). The Stack passes every tap outside the panel
    // straight through to the game.
    final panelTop = 120.0 +
        (widget.game.isEndless && widget.game.ghostGapMetres != null
            ? HudOverlay.ghostBadgeBandHeight
            : 0.0);

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(top: panelTop, left: 24, right: 24),
              child: Container(
                key: const ValueKey('bank_prompt_panel'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber.shade700, width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The choice, and what it is worth.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'BANK OR PUSH?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'AT RISK ${chain.score}',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // The stake, in one line: banking is the only way to
                    // keep it. In the tutorial ladder (issue #16) the run
                    // being settled is a level; in a shift, the shift.
                    // The biggest sentence on the panel on purpose — it
                    // is the choice being priced.
                    Text(
                      widget.game.isEndless
                          ? 'Bank ends the shift and keeps it — a crash '
                              'loses it.'
                          : 'Bank ends the level and keeps it — a crash '
                              'loses it.',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    // The window closing: pushes itself toward a default.
                    ClipRRect(
                      key: const ValueKey('bank_prompt_bar'),
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 6,
                        child: Stack(
                          children: [
                            Container(color: Colors.white24),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: prompt.fractionRemaining,
                              child: Container(
                                color: _barColorFor(prompt.remainingSeconds),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: widget.game.bankShift,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.black,
                            ),
                            child: Text(
                              'BANK ${chain.score}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: widget.game.pushOn,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                            ),
                            child: Text(
                              'PUSH ON \u00d7$nextMultiplier',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
