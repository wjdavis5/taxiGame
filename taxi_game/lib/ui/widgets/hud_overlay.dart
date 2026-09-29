import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../game/systems/fare_chain.dart';
import '../../game/systems/lives.dart';
import '../../game/taxi_game.dart';
import '../../models/fare_type.dart';
import '../../services/game_state_service.dart';

/// HUD overlay that displays during gameplay
class HudOverlay extends StatelessWidget {
  const HudOverlay({super.key, required this.game});

  final TaxiGame game;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Top bar with level, coins, pause button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Level number, or distance driven in an endless shift
                Consumer<GameStateService>(
                  builder: (context, gameState, child) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: game.isEndless
                          // The rung's authored name ('First Ride',
                          // 'Bank It') rides the number: the ladder's
                          // flavor is content, not dead JSON. Polled like
                          // the distance badge because the name lands
                          // with the async level load, after this bar's
                          // first build.
                          ? _EndlessDistanceBadge(game: game)
                          : _LevelNameBadge(game: game),
                    );
                  },
                ),
                
                // Coins
                Consumer<GameStateService>(
                  builder: (context, gameState, child) {
                    // Keyed on the total so a coin award restarts the
                    // pulse: the counter pops as the coin pops land in it
                    // (issue #7).
                    return TweenAnimationBuilder<double>(
                      key: ValueKey('coin-pulse-${gameState.totalCoins}'),
                      tween: Tween(begin: 1.3, end: 1.0),
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      builder: (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.monetization_on,
                              color: Colors.yellow,
                              size: 20,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${gameState.totalCoins}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                
                // Pause button
                IconButton(
                  onPressed: () {
                    game.pauseGame();
                  },
                  icon: const Icon(
                    Icons.pause,
                    color: Colors.white,
                    size: 32,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                ),
              ],
            ),
            
            // Scoring bar: run score, chain multiplier, and the active
            // fare countdown (issue #12).
            const SizedBox(height: 10),
            _ScoringBar(game: game),

            // The fare offer bar (issue #25): what kind of fare is
            // waiting ahead, and the decline that makes it a choice.
            _FareOfferBar(game: game),

            // The lower screen belongs to the thumb: no instruction bar
            // down here (the one-time control hint owns teaching, and a
            // permanent pill would sit exactly where the stick's ring
            // rises and contradict what the hint taught).
            const Spacer(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

/// The ladder rung's number and authored name (issue: the ten level
/// names are content, not dead JSON). Polls on the same short timer as
/// the distance badge — the name arrives with the async level load.
class _LevelNameBadge extends StatefulWidget {
  const _LevelNameBadge({required this.game});

  final TaxiGame game;

  @override
  State<_LevelNameBadge> createState() => _LevelNameBadgeState();
}

class _LevelNameBadgeState extends State<_LevelNameBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.game.currentLevelName;
    final label = (name == null || name.isEmpty)
        ? 'Level ${widget.game.currentLevelNumber}'
        : 'Level ${widget.game.currentLevelNumber} \u00b7 $name';
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

/// Live distance readout for endless shifts (issue #11). The game world
/// has no per-frame Flutter rebuilds, so the badge polls the run distance
/// on a short timer — cheap, and plenty for a counter.
class _EndlessDistanceBadge extends StatefulWidget {
  const _EndlessDistanceBadge({required this.game});

  final TaxiGame game;

  @override
  State<_EndlessDistanceBadge> createState() => _EndlessDistanceBadgeState();
}

class _EndlessDistanceBadgeState extends State<_EndlessDistanceBadge> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// World px to metres: 10 px = 1 m, so a full-speed minute reads as
  /// ~900 m. A made-but-fixed scale — the number only needs to mean
  /// "further is deeper into the shift".
  static const double pixelsPerMetre = 10.0;

  @override
  Widget build(BuildContext context) {
    final metres = widget.game.runDistance / pixelsPerMetre;
    final label = metres >= 1000
        ? '${(metres / 1000).toStringAsFixed(1)} km'
        : '${metres.round()} m';

    return Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

/// Live scoring readout (issue #12): the run score, the chain multiplier,
/// and the most urgent fare countdown while a passenger is aboard. Like
/// [_EndlessDistanceBadge], it polls the game on a short timer — the fare
/// clock only reads to a tenth of a second, so that is plenty.
class _ScoringBar extends StatefulWidget {
  const _ScoringBar({required this.game});

  final TaxiGame game;

  @override
  State<_ScoringBar> createState() => _ScoringBarState();
}

class _ScoringBarState extends State<_ScoringBar> {
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

  @override
  Widget build(BuildContext context) {
    final chain = widget.game.fareChain;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Run score and lives, left. The score is labelled by what it is:
        // at-risk chain score in an endless shift (it is forfeited by a
        // wreck and only kept by a bank), plain score in the tutorial
        // ladder, which settles at completion. The lives badge is
        // endless-only: the tutorial ladder has no failure budget to
        // show, and a badge that never moves is noise.
        Row(
          children: [
            _HudPill(
              child: Text(
                widget.game.isEndless
                    ? 'AT RISK ${chain.score}'
                    : 'SCORE ${chain.score}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            if (widget.game.isEndless) ...[
              const SizedBox(width: 8),
              _LivesBadge(
                key: const ValueKey('lives_badge'),
                remaining: widget.game.lives.remaining,
              ),
              // The ghost gap (issue #20): live +/- metres against the
              // translucent car on the road, so the race reads even when
              // the ghost has scrolled off screen.
              if (widget.game.ghostGapMetres != null) ...[
                const SizedBox(width: 8),
                _GhostBadge(gapMetres: widget.game.ghostGapMetres!),
              ],
            ],
          ],
        ),
        // Chain state, right: the fare meter next to the multiplier it
        // feeds.
        Row(
          children: [
            if (chain.isCarryingFare) ...[
              _FareTimerBadge(timer: chain.mostUrgentTimer!),
              const SizedBox(width: 8),
            ],
            _MultiplierBadge(multiplier: chain.multiplier),
          ],
        ),
      ],
    );
  }
}

/// A rounded black pill matching the HUD's other badges.
class _HudPill extends StatelessWidget {
  const _HudPill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}

/// The shift's remaining lives (issue #14): a heart per life, full red
/// while held and hollowed out as crashes spend them. Always visible in
/// an endless shift — the whole point of a failure budget is knowing how
/// much of it is left. Keyed on the count so each spend re-pops the
/// badge: the pulse is the badge's half of the crash feedback (the world
/// pop is the other half).
class _LivesBadge extends StatelessWidget {
  const _LivesBadge({super.key, required this.remaining});

  /// Lives left in the shift; everything past this renders spent.
  final int remaining;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('lives-pulse-$remaining'),
      tween: Tween(begin: 1.4, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: _HudPill(
        child: Row(
          children: [
            for (var i = 0; i < LivesTracker.maxLives; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Icon(
                i < remaining ? Icons.favorite : Icons.favorite_border,
                color: i < remaining ? Colors.red : Colors.white24,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The live ghost gap (issue #20): metres ahead (green, up arrow) or
/// behind (red, down) of the translucent best-run car, dead level when
/// the gap rounds to nothing. The race is only a race while it reads.
class _GhostBadge extends StatelessWidget {
  const _GhostBadge({required this.gapMetres});

  /// Positive when the player is ahead of the ghost, negative behind.
  final double gapMetres;

  static Color _colorFor(double gap) =>
      gap > 0 ? Colors.greenAccent : gap < 0 ? Colors.red.shade200 : Colors.white;

  @override
  Widget build(BuildContext context) {
    final gap = gapMetres.round();
    return _HudPill(
      key: const ValueKey('ghost_badge'),
      child: Row(
        children: [
          Icon(
            gap > 0
                ? Icons.arrow_upward
                : gap < 0
                    ? Icons.arrow_downward
                    : Icons.remove,
            color: _colorFor(gapMetres),
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            'GHOST ${gap == 0 ? '' : gap > 0 ? '+' : '-'}${gap.abs()} m',
            style: TextStyle(
              color: _colorFor(gapMetres),
              fontSize: 15,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The chain multiplier (issue #12). Dim at 1x; gold and pulsing whenever
/// the chain is alive, keyed on the value so each step re-pops it.
class _MultiplierBadge extends StatelessWidget {
  const _MultiplierBadge({required this.multiplier});

  final int multiplier;

  static Color _colorFor(int multiplier) =>
      multiplier > 1 ? Colors.amber : Colors.white54;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('chain-pulse-$multiplier'),
      tween: Tween(begin: 1.35, end: 1.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: _HudPill(
        child: Text(
          '\u00d7$multiplier',
          style: TextStyle(
            color: _colorFor(multiplier),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// The most urgent fare countdown (issue #12). Counts down in tenths;
/// heats up as it runs out, and reads LATE once the window has closed
/// (the chain is already broken — the badge only explains it).
class _FareTimerBadge extends StatelessWidget {
  const _FareTimerBadge({required this.timer});

  final FareTimer timer;

  static const double _warnSeconds = 5.0;
  static const double _dangerSeconds = 2.5;

  static Color _colorFor(FareTimer timer) {
    if (timer.isExpired) return Colors.red;
    if (timer.remainingSeconds <= _dangerSeconds) return Colors.red;
    if (timer.remainingSeconds <= _warnSeconds) return Colors.orange;
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return _HudPill(
      child: Row(
        children: [
          Icon(
            timer.isExpired ? Icons.timer_off : Icons.timer,
            color: _colorFor(timer),
            size: 18,
          ),
          const SizedBox(width: 5),
          Text(
            timer.isExpired
                ? 'LATE'
                : '${timer.remainingSeconds.toStringAsFixed(1)}s',
            style: TextStyle(
              color: _colorFor(timer),
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The fare offer bar (issue #25): while a passenger waits on a kerb
/// ahead, it names the fare's kind, what it pays, and offers the decline
/// that turns variety into a decision — a VIP you cannot refuse would be
/// a modifier, not a choice. Hidden outside endless runs (a level's
/// pickups are mandatory) and whenever nothing waitable is on screen.
/// Polls the game like the scoring bar does.
class _FareOfferBar extends StatefulWidget {
  const _FareOfferBar({required this.game});

  final TaxiGame game;

  @override
  State<_FareOfferBar> createState() => _FareOfferBarState();
}

class _FareOfferBarState extends State<_FareOfferBar> {
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

  /// The icon that names the fare kind at a glance.
  static IconData _iconFor(FareType type) => switch (type) {
        FareType.standard => Icons.person,
        FareType.vip => Icons.workspace_premium,
        FareType.longHaul => Icons.straighten,
        FareType.awkward => Icons.swap_horiz,
      };

  @override
  Widget build(BuildContext context) {
    if (!widget.game.isEndless) return const SizedBox.shrink();
    // The bank-or-push panel draws in this same band (issue #13): stand
    // the offer down while the choice is up, so the prompt never covers
    // the SKIP the player might still want once it resolves.
    if (widget.game.bankPrompt.isActive) return const SizedBox.shrink();
    final offer = widget.game.currentFareOffer;
    if (offer == null) return const SizedBox.shrink();

    final type = offer.fareType;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _HudPill(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconFor(type), color: type.markerColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  type.offerBlurb(offer.reward),
                  style: TextStyle(
                    color: type.markerColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                // The decline: removes the waiting fare from the street —
                // no pay, no penalty. The whole decision is here. Sized
                // to the platform's minimum touch target: the decline is
                // the point of the offer bar, not fine print.
                TextButton(
                  key: const ValueKey('decline_fare_button'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(44, 44),
                  ),
                  onPressed: () => widget.game.declineCurrentOffer(),
                  child: const Text(
                    'SKIP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
