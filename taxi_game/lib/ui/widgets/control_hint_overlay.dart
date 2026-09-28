import 'package:flutter/material.dart';

/// The one-time stick-control hint (issue #37): shown over a first game
/// start for a save that has never dismissed it, naming the invisible
/// relative stick — touch anywhere low, drag up for speed, sideways to
/// steer — with a faint ghost of the ring a landed thumb raises.
///
/// Positioned low on the screen, well below the taxi (which rides at the
/// viewport's vertical centre), so the road centre and the street ahead
/// stay clear.
///
/// Entirely pointer-transparent: the hint sits inside the stick's own
/// touch region (the lower half), so any tap on it *is* a stick touch —
/// [VirtualStick]'s lower-half gate accepts it and dismisses the hint
/// through `TaxiGame.onStickEngaged`. There is deliberately no separate
/// tap target here to swallow drags meant for the road; the hint is pure
/// display, and the first real input — wherever the thumb lands low,
/// including on the hint itself — ends it for good.
class ControlHintOverlay extends StatelessWidget {
  const ControlHintOverlay({super.key});

  /// The line the hint teaches, in the stick's own terms.
  static const String _hintLine =
      'Touch and hold the lower half — drag up for speed, sideways to steer.';

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: const Alignment(0, 0.72),
          child: Container(
            key: const ValueKey('controlHint'),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(size: Size(140, 116), painter: _StickGhostPainter()),
                SizedBox(height: 8),
                Text(
                  _hintLine,
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
