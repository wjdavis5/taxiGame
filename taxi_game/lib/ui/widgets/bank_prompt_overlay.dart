import 'dart:async';
import 'dart:math' as math;

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

  /// Reads the panel's natural height off the width-pinned box inside
  /// the FittedBox (see [build]): the FittedBox lays its child out
  /// unbounded, so the box's render size is the panel *before* any
  /// scale-down — the number the fit against the badge's band turns
  /// on.
  final GlobalKey _panelNaturalKey =
      GlobalKey(debugLabel: 'bank_prompt_panel_natural');

  /// The panel's natural (pre-scale) height as laid out by the last
  /// frame the prompt was on screen, at that frame's width and text
  /// scale. Null until the first such frame has been measured — until
  /// then [build] parks optimistically below the badge band.
  double? _panelNaturalHeight;

  /// The lane geometry and parking branch the current build used —
  /// kept so the post-frame measurement judges against the numbers the
  /// layout actually had, and can tell whether it disagrees.
  double _laneHeight = 0;
  double _badgeBand = 0;
  bool _parksBelowBadge = false;

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

  /// Judges the fit the last build laid out and reconciles both halves
  /// of it: which branch the next build parks the panel in, and whether
  /// the ghost badge keeps its band — written to
  /// [TaxiGame.bankPanelOustsGhostBadge], a plain field the HUD polls
  /// on its own 100 ms tick the way it reads every other piece of game
  /// state. Runs after every frame the prompt paints; setState only on
  /// a branch flip, so the steady state rebuilds nothing extra.
  void _resolveFit() {
    if (!mounted) return;
    final naturalContext = _panelNaturalKey.currentContext;
    // The prompt went down between the build that scheduled this and
    // the frame's end — nothing left to measure, and the game's own
    // teardown path owns the flag.
    if (naturalContext == null || naturalContext.size == null) return;
    final measured = naturalContext.size!.height;
    _panelNaturalHeight = measured;
    final ousts = _badgeBand > 0 && measured > _laneHeight - _badgeBand;
    widget.game.bankPanelOustsGhostBadge = ousts;
    // The flag write alone repaints nothing here. Re-park only where a
    // band is in play and the measurement disagrees with the branch
    // just laid out — most commonly the first measurement of a
    // too-tall panel arriving after the optimistic below-the-band
    // build, or a text-scale change moving the panel across the line
    // mid-window. The band check is load-bearing: with no badge to
    // arbitrate (`_badgeBand == 0` — every ordinary dropoff, every
    // banking-lesson level) `ousts` and `_parksBelowBadge` are both
    // false on every frame, and reading that agreement as a flip would
    // setState after every painted frame of the window — a
    // self-sustaining rebuild loop at frame rate.
    if (_badgeBand > 0 && ousts == _parksBelowBadge) {
      setState(() {});
    }
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
    // narrower than the panel itself: it slid down over the cab. #134's
    // answer — hide the badge on every phone and take the whole lane —
    // brought back #130's report everywhere else (issue #139), so the
    // fit is now measured per screen instead of assumed: where the lane
    // still fits the panel below the badge's band, both share the
    // screen; only where it does not does the badge stand down and the
    // panel take the full lane. The scale-down cap holds in both
    // branches, so the cab bound holds unconditionally — either phone,
    // any text scale. The level ladder's camera follows a lead point
    // above the cab, parking it *below* centre — the centred-cab nose
    // computed here is the stricter bound, so the cap protects both
    // modes. The Stack passes every tap outside the panel straight
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

        // The ghost badge's band (issues #130, #139): the badge sits on
        // its own line under the scoring row, and the panel paints
        // above the HUD (the overlays stack in the order they were
        // added). Where the lane still fits the panel below that band,
        // #130's placement holds and both are on screen together — the
        // race the badge reads is live through every non-primer window
        // (only a save's first-ever offer freezes the world, issue
        // #132), and the gap is what the decision turns on. The fit is
        // measured, not assumed: the FittedBox below lays its child out
        // unbounded, so the width-pinned box carries the panel's
        // natural (pre-scale) height, and the post-frame callback
        // compares it against the lane. Until that first measurement
        // lands the panel parks below the band optimistically — the cap
        // holds there too, so the cab bound survives even that frame.
        // Where the panel does not fit below the band — a 667 pt phone
        // at large text — it takes the full lane instead and raises
        // [TaxiGame.bankPanelOustsGhostBadge], which the HUD reads to
        // stand the badge down for the window.
        final badgeBand = widget.game.isEndless &&
                widget.game.ghostGapMetres != null
            ? HudOverlay.ghostBadgeBandHeight
            : 0.0;
        final natural = _panelNaturalHeight;
        final parksBelowBadge = badgeBand > 0 &&
            (natural == null || natural <= laneHeight - badgeBand);
        final panelTop = top + (parksBelowBadge ? badgeBand : 0.0);
        final panelLane = math.max(
            0.0, laneHeight - (parksBelowBadge ? badgeBand : 0.0));

        // What the post-frame measurement judges against, and the
        // branch it must stay in sync with.
        _laneHeight = laneHeight;
        _badgeBand = badgeBand;
        _parksBelowBadge = parksBelowBadge;
        WidgetsBinding.instance.addPostFrameCallback((_) => _resolveFit());

        return Stack(
          children: [
            Positioned(
              top: panelTop,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: panelLane),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    // The panel's natural width is the padded street
                    // width — FittedBox lays its child out unbounded, so
                    // the width has to be named here, not inherited. The
                    // GlobalKey reads this box's size back after the
                    // frame: unbounded layout means it is the panel's
                    // natural height, before any scale-down.
                    child: SizedBox(
                      key: _panelNaturalKey,
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
                            // The two choices split the panel's width,
                            // and on a 320 pt phone each half is less
                            // type than even a plain 'BANK 42' needs —
                            // a four-digit stake only widens it. Both
                            // labels ride the scale-down box (issue
                            // #208, the menu title's #187 idiom): one
                            // line of ink, shrunk to fit the half each
                            // button gets. The outer panel-wide
                            // FittedBox above cannot help here — it pins
                            // the panel at full street width and scales
                            // the whole card, wrap and all.
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
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
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
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
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
