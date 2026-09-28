/// A single attribution block shown on the credits screen.
class CreditEntry {
  /// Section heading, e.g. "Artwork".
  final String title;

  /// The attribution text itself.
  final String body;

  /// Where the work came from, shown beneath [body] when present.
  final String? source;

  const CreditEntry({
    required this.title,
    required this.body,
    this.source,
  });
}

/// The app's attribution, in display order.
///
/// This list is the single owning source for in-app credits. It must stay in
/// sync with `assets/licenses/LICENSES.txt`, which is the full per-file license
/// inventory — when an asset with an attribution-required license is added to
/// the bundle, its credit is added here.
///
/// Nothing currently shipped *requires* attribution: the Kenney artwork is CC0,
/// and the CC-BY music that did require it was removed from the bundle along
/// with the rest of the unused audio. The Kenney entry is a courtesy credit.
const appCredits = <CreditEntry>[
  CreditEntry(
    title: 'Artwork',
    body: 'Vehicle sprites and interface icons by Kenney, released into the '
        'public domain under CC0 1.0. Attribution is not required for CC0 — '
        'this credit is here because the work earned it.',
    source: 'kenney.nl',
  ),
  CreditEntry(
    title: 'Sound',
    body: 'Sound effects and jingles by Kenney, released into the public '
        'domain under CC0 1.0. Attribution is not required for CC0 — this '
        'credit is here because the work earned it. The engine hum, the '
        'brake squeal, and the music loop were synthesized in-repo and are '
        'the project\'s own.',
    source: 'kenney.nl',
  ),
  CreditEntry(
    title: 'Built with',
    body: 'Flutter, the Flame game engine, and flame_audio.',
    source: 'flutter.dev · flame-engine.org',
  ),
  CreditEntry(
    title: 'Game',
    body: 'Cab Hustle — design, code, and level layouts by William Davis.',
    source: 'github.com/wjdavis5/taxiGame',
  ),
];
