import 'package:flutter/material.dart';

/// The menu's control face (issue #264): a chunky cab-sign button drawn
/// with the game's own palette — the yellow/white face, the black rim,
/// and the hard offset shadow — instead of a stock Material button.
///
/// It exists because the first screen is the identity judgement: the
/// reviewer's 30 seconds said "built with Flutter" before "Cab Hustle",
/// and the loading state's own voice (the blue field, the white type,
/// the yellow cab) had no control language to match. Labels still ride
/// a scale-down box ([FittedBox]) under unbounded width, so every label
/// stays one line on the 320 pt phones the menu's layout issues name.
class CabButton extends StatelessWidget {
  const CabButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  /// Primary buttons are the menu's headline actions: the signature
  /// yellow, black ink, a larger face. Everything else steps back in
  /// white with the deep-blue ink.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final face = primary ? Colors.yellow : Colors.white;
    final ink = primary ? Colors.black : Colors.blue.shade900;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        // Opaque so the whole face — padding and the gap around the
        // icon included — is the tap target, not just the painted text.
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: primary ? 26 : 22,
            vertical: primary ? 14 : 11,
          ),
          decoration: BoxDecoration(
            color: face,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                offset: Offset(0, 5),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: primary ? 30 : 26, color: ink),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: primary ? 24 : 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      color: ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
