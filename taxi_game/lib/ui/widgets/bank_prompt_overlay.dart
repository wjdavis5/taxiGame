import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game/systems/bank_prompt.dart';
import '../../game/systems/fare_chain.dart';
import '../../game/taxi_game.dart';

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

    // The panel's lane, measured against the cab it must never cover
    // (issue #134). The fixed-resolution camera renders the 400×800
    // world at min(w/400, h/800) and the endless camera follows the cab
    // vertically only, so the cab sits centred on screen and its nose —
    // half its body height, in screen px — is where the panel's bottom
    // must stop. #130's fix parked the panel below the ghost badge with
    // no lower bound, and on a 667 pt phone the badge-to-nose gap is
    // narrower than the panel itself: it slid down over the cab. The
    // badge now stands down for the window (hud_overlay.dart, the
    // fare-offer bar's pattern), and this cap holds regardless of the
    // text scale or the phone. The level ladder's camera follows a lead
    // point above the cab, parking it *below* centre — the centred-cab
    // nose computed here is the stricter bound, so the cap protects
    // both modes. The Stack passes every tap outside the panel straight
    // through to the game.
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;
        final worldScale = math.min(screenW / 400, screenH / 800);
        final noseY = screenH / 2 -
            (widget.game.player.stats.height / 2) * worldScale;

        // Below the HUD's fixed top band (plus whatever the status bar
        // takes), and never below a 12 px clearance above the cab's
        // nose. Where the panel at full size does not fit that lane —
        // 667 pt at large text — the FittedBox shrinks it uniformly
        // instead of letting it overflow onto the cab.
        const cabClearance = 12.0;
        final top = MediaQuery.paddingOf(context).top + 120.0;
        final laneHeight = math.max(0.0, noseY - cabClearance - top);

        return Stack(
          children: [
            Positioned(
              top: top,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: laneHeight),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    // The panel's natural width is the padded street
                    // width — FittedBox lays its child out unbounded, so
                    // the width has to be named here, not inherited.
                    child: SizedBox(
                      width: screenW - 48,
                      child: Container(
                        key: const ValueKey('bank_prompt_panel'),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.amber.shade700, width: 1.5),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // The choice, and what it is worth. Both ends
                            // yield (the HUD title's pattern, issue #57):
                            // the stake grows with the score, and a wide
                            // one must scale down rather than shove the
                            // title off the panel.
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                const Flexible(
                                  fit: FlexFit.loose,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'BANK OR PUSH?',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ),
                                Flexible(
                                  fit: FlexFit.loose,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'AT RISK ${chain.score}',
                                      style: const TextStyle(
                                        color: Colors.amber,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        fontFeatures: [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // The stake, in one line: banking is the only
                            // way to keep it. In the tutorial ladder
                            // (issue #16) the run being settled is a
                            // level; in a shift, the shift. The biggest
                            // sentence on the panel on purpose — it is
                            // the choice being priced.
                            Text(
                              widget.game.isEndless
                                  ? 'Bank ends the shift and keeps it — a '
                                      'crash loses it.'
                                  : 'Bank ends the level and keeps it — a '
                                      'crash loses it.',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            // The window closing: pushes itself toward a
                            // default.
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
                                      widthFactor:
                                          prompt.fractionRemaining,
                                      child: Container(
                                        color: _barColorFor(
                                            prompt.remainingSeconds),
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
                                      backgroundColor:
                                          Colors.amber.shade700,
                                      foregroundColor: Colors.black,
                                    ),
                                    child: Text(
                                      'BANK ${chain.score}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontFeatures: [
                                          FontFeature.tabularFigures()
                                        ],
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
                                      side: const BorderSide(
                                          color: Colors.white54),
                                    ),
                                    child: Text(
                                      'PUSH ON \u00d7$nextMultiplier',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontFeatures: [
                                          FontFeature.tabularFigures()
                                        ],
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
              ),
            ),
        ],
        );
      },
    );
  }
}
