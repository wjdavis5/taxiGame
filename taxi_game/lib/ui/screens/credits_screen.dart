import 'package:flutter/material.dart';

import '../../data/credits.dart';

/// Shows the app's asset and toolchain attribution.
///
/// Reachable in one tap from the main menu. The content comes from
/// [appCredits], which is the single owning source — do not inline credit text
/// here, or it will drift from `assets/licenses/LICENSES.txt`.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('credits_screen'),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade300,
              Colors.blue.shade600,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const Key('credits_back_button'),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      iconSize: 32,
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'CREDITS',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            offset: Offset(2, 2),
                            blurRadius: 4,
                            color: Colors.black45,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Scrolls because the attribution text is long and the app is
              // portrait-locked on phones as small as the SE.
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  itemCount: appCredits.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 28),
                  itemBuilder: (context, index) =>
                      _CreditBlock(entry: appCredits[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditBlock extends StatelessWidget {
  final CreditEntry entry;

  const _CreditBlock({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.title.toUpperCase(),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.yellow,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          entry.body,
          style: const TextStyle(
            fontSize: 16,
            height: 1.4,
            color: Colors.white,
          ),
        ),
        if (entry.source != null) ...[
          const SizedBox(height: 4),
          Text(
            entry.source!,
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ],
    );
  }
}
