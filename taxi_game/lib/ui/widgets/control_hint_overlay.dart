import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game/taxi_game.dart';

/// The one-time stick-control hint (issue #37): shown over a first game
/// start for a save that has never dismissed it, naming the invisible
/// relative stick — touch anywhere low, drag up for speed, sideways to
/// steer — with a faint ghost of the ring a landed thumb raises.
///
/// Parked below the cab's own tail, measured (issue #177): the endless
/// camera centres the cab, but the tutorial ladder's camera follows a
/// lead [TaxiGame.levelCameraLead] above it (issue #45), parking the cab
/// that far *below* centre — and the hint used to sit at a fixed
/// alignment computed for a centred cab, riding 30 px up the cab's tail
/// on every rung. The pill's top is now pinned one clearance under the
/// cab's on-screen tail (the bank panel's world-scale idiom, issue
/// #134), and where the lane left below the cab cannot hold the pill at
/// natural size — a 320×568 phone, a large text scale — a FittedBox
/// shrinks it rather than letting it climb back onto the cab.
///
/// Measured in the game canvas's own frame, un-inset (issue #182): the
/// #177 arithmetic was right but its ruler was not. This overlay used to
/// wrap its measurement in a [SafeArea], which ate the home indicator's
/// 34 pt bottom inset — an inset the canvas itself keeps, because
/// GameScreen insets the game top-only and hands the bottom to the
/// system swipe — so the pill was placed in a frame 34 pt shorter than
/// the canvas the cab is rendered into: on a 420×912 phone, 808 pt of
/// ruler against 842 pt of road, and the cab's rendered tail sat lower
/// than the frame-local math placed it, riding the pill back up onto
/// the cab on every home-indicator iPhone. Flame lays overlays in the
/// same stack as the game canvas, so the [LayoutBuilder]'s constraints
/// here are the canvas exactly — and that, nothing narrower, is the
/// frame the tail is measured in.
///
/// Entirely pointer-transparent: the hint sits inside the stick's own
/// touch region (the lower half), so any tap on it *is* a stick touch —
/// [VirtualStick]'s lower-half gate accepts it and answers the hint
/// through `TaxiGame.onStickEngaged`. Placement is wholly below the
/// screen's centre line, so that contract holds in every mode. There is
/// deliberately no separate tap target here to swallow drags meant for
/// the road; the hint is pure display.
///
/// The lesson itself (issue #267) ends only when the player has both
/// accelerated and steered — a single low landing no longer dismisses it
/// forever. A thumb that lands in the dead upper half raises the cue
/// line instead of vanishing: the game's [TaxiGame.controlHintCue]
/// notifier rebuilds this overlay on the touch itself, so the correction
/// reads immediately rather than on the poll's next tick.
class ControlHintOverlay extends StatefulWidget {
  const ControlHintOverlay({super.key, required this.game});

  /// The run the hint is teaching over: the cab whose tail the pill is
  /// parked under, and the mode whose camera framing sets where that
  /// tail sits on screen.
  final TaxiGame game;

  /// The line the hint teaches, in the stick's own terms.
  static const String _hintLine =
      'Touch and hold the lower half — drag up for speed, sideways to steer.';

  /// The upper-half correction (issue #267): shown the moment a thumb
  /// lands where the stick cannot hear it.
  static const String _cueLine =
      'Move your thumb lower — touch and hold in the lower half to drive.';

  @override
  State<ControlHintOverlay> createState() => _ControlHintOverlayState();
}

class _ControlHintOverlayState extends State<ControlHintOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // The upper-half cue must read the instant the thumb lands (issue
    // #267), so it bypasses the poll below and rebuilds straight off the
    // notifier.
    widget.game.controlHintCue.addListener(_onCueChanged);
    // The hint rides the GameWidget's initialActiveOverlays, so its
    // first build races the game's own load: the level or endless run —
    // and with it the cab this placement measures — may not exist yet.
    // Poll like the HUD does until it does; once the cab stands, the
    // placement moves only with the screen, and the lesson's end removes
    // the overlay (and this state, and the timer) for good.
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onCueChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.game.controlHintCue.removeListener(_onCueChanged);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // No SafeArea in here (issue #182): Flame lays this overlay in
      // the same stack as the game canvas, so the constraints below are
      // the canvas exactly — including the bottom band a SafeArea would
      // carve off the ruler while the cab keeps rendering through it.
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Nothing to park under until the cab exists: render nothing
          // rather than guess a position the measured frame would then
          // have to correct on screen. The poll above brings the first
          // real frame within a tick of the cab appearing.
          if (!widget.game.isPlayerReady) return const SizedBox.shrink();

          final screenW = constraints.maxWidth;
          final screenH = constraints.maxHeight;
          // The fixed-resolution viewport renders the 400×800 world at
          // min(w/400, h/800) — the same scale the bank panel places
          // its cab bound with (issue #134).
          final worldScale = math.min(screenW / 400, screenH / 800);

          // The cab's tail on screen (issue #177). The endless camera
          // follows the cab itself, so the tail sits half a body below
          // centre; the level camera follows a lead 100 px up the
          // road, so the whole cab rides that much lower — the
          // alignment the old fixed placement ignored.
          final leadBelowCentre =
              widget.game.isEndless ? 0.0 : TaxiGame.levelCameraLead;
          final cabTailY = screenH / 2 +
              (leadBelowCentre + widget.game.player.stats.height / 2) *
                  worldScale;

          // The pill's lane: everything below one clearance under the
          // cab's tail. Where that lane cannot hold the pill at
          // natural size, the FittedBox shrinks it uniformly instead
          // of letting it overflow back onto the cab.
          const cabClearance = 16.0;
          final hintTop = cabTailY + cabClearance;
          final laneHeight = math.max(0.0, screenH - hintTop);

          // The upper-half correction (issue #267) is live while the
          // notifier says so; the poll keeps it fresh across ticks.
          final cue = widget.game.controlHintCue.value;

          return Stack(
            children: [
              Positioned(
                top: hintTop,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: laneHeight),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: screenW - 48,
                        child: Container(
                          key: const ValueKey('controlHint'),
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                            // The correction wears the stick knob's amber
                            // (issue #267) — the same accent the landed
                            // thumb's knob draws with, so the cue reads
                            // as this control talking, not a new widget.
                            border: cue
                                ? Border.all(
                                    color: const Color(0xFFFFC933),
                                    width: 2,
                                  )
                                : null,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CustomPaint(
                                size: const Size(140, 116),
                                painter: _StickGhostPainter(cue: cue),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                cue
                                    ? ControlHintOverlay._cueLine
                                    : ControlHintOverlay._hintLine,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.3,
                                ),
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
      ),
    );
  }
}

/// The faint stick ghost: the same ring and knob the live stick draws
/// under a landed thumb (`VirtualStick.ringRadius` / `knobRadius`, the
/// same white ring and amber knob), dimmed, with a small arrow above
/// it — the drag that asks for speed. Faint on purpose: it is a ghost of
/// a control, not a button, and must never read as something to tap.
class _StickGhostPainter extends CustomPainter {
  const _StickGhostPainter({this.cue = false});

  /// True while the upper-half correction (issue #267) is showing: the
  /// arrow turns to point down, at the half of the screen the thumb must
  /// move to.
  final bool cue;

  @override
  void paint(Canvas canvas, Size size) {
    // Ring and knob centred low, leaving the top strip for the arrow.
    final centre = Offset(size.width / 2, size.height - 38);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.30);
    canvas.drawCircle(centre, 34, ring);

    final knob = Paint()
      ..color = const Color(0xFFFFC933).withValues(alpha: 0.45);
    canvas.drawCircle(centre, 15, knob);

    // The arrow, clear of the ring: the ghost's one word of anatomy,
    // matching the line's "drag up for speed" — or pointing down when
    // the cue asks the thumb to move lower.
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = cue
          ? const Color(0xFFFFC933).withValues(alpha: 0.85)
          : const Color(0xFFFFFFFF).withValues(alpha: 0.55);
    final path = Path();
    if (cue) {
      path
        ..moveTo(centre.dx, centre.dy - 70)
        ..lineTo(centre.dx, centre.dy - 46)
        ..moveTo(centre.dx - 8, centre.dy - 55)
        ..lineTo(centre.dx, centre.dy - 46)
        ..lineTo(centre.dx + 8, centre.dy - 55);
    } else {
      path
        ..moveTo(centre.dx, centre.dy - 46)
        ..lineTo(centre.dx, centre.dy - 70)
        ..moveTo(centre.dx - 8, centre.dy - 61)
        ..lineTo(centre.dx, centre.dy - 70)
        ..lineTo(centre.dx + 8, centre.dy - 61);
    }
    canvas.drawPath(path, arrow);
  }

  @override
  bool shouldRepaint(covariant _StickGhostPainter oldDelegate) =>
      oldDelegate.cue != cue;
}
