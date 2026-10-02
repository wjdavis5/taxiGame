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
/// Entirely pointer-transparent: the hint sits inside the stick's own
/// touch region (the lower half), so any tap on it *is* a stick touch —
/// [VirtualStick]'s lower-half gate accepts it and dismisses the hint
/// through `TaxiGame.onStickEngaged`. Placement is wholly below the
/// screen's centre line, so that contract holds in every mode. There is
/// deliberately no separate tap target here to swallow drags meant for
/// the road; the hint is pure display, and the first real input —
/// wherever the thumb lands low, including on the hint itself — ends it
/// for good.
class ControlHintOverlay extends StatefulWidget {
  const ControlHintOverlay({super.key, required this.game});

  /// The run the hint is teaching over: the cab whose tail the pill is
  /// parked under, and the mode whose camera framing sets where that
  /// tail sits on screen.
  final TaxiGame game;

  /// The line the hint teaches, in the stick's own terms.
  static const String _hintLine =
      'Touch and hold the lower half — drag up for speed, sideways to steer.';

  @override
  State<ControlHintOverlay> createState() => _ControlHintOverlayState();
}

class _ControlHintOverlayState extends State<ControlHintOverlay> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // The hint rides the GameWidget's initialActiveOverlays, so its
    // first build races the game's own load: the level or endless run —
    // and with it the cab this placement measures — may not exist yet.
    // Poll like the HUD does until it does; once the cab stands, the
    // placement moves only with the screen, and the first real stick
    // touch removes the overlay (and this state, and the timer) for
    // good.
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
    return IgnorePointer(
      child: SafeArea(
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
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CustomPaint(
                                  size: Size(140, 116),
                                  painter: _StickGhostPainter(),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  ControlHintOverlay._hintLine,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
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
      ),
    );
  }
}

/// The faint stick ghost: the same ring and knob the live stick draws
/// under a landed thumb (`VirtualStick.ringRadius` / `knobRadius`, the
/// same white ring and amber knob), dimmed, with a small up arrow above
/// it — the drag that asks for speed. Faint on purpose: it is a ghost of
/// a control, not a button, and must never read as something to tap.
class _StickGhostPainter extends CustomPainter {
  const _StickGhostPainter();

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

    // The up arrow, clear of the ring: the ghost's one word of anatomy,
    // matching the line's "drag up for speed".
    final arrow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.55);
    final path = Path()
      ..moveTo(centre.dx, centre.dy - 46)
      ..lineTo(centre.dx, centre.dy - 70)
      ..moveTo(centre.dx - 8, centre.dy - 61)
      ..lineTo(centre.dx, centre.dy - 70)
      ..lineTo(centre.dx + 8, centre.dy - 61);
    canvas.drawPath(path, arrow);
  }

  @override
  bool shouldRepaint(covariant _StickGhostPainter oldDelegate) => false;
}
