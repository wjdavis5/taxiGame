import 'package:flame/components.dart';
import 'package:flutter/services.dart';

/// Close-call detection for cleared traffic (issue #23).
///
/// A **close call** is a pass the taxi cleared without touching: the
/// traffic vehicle crossed from ahead to behind — the player only ever
/// travels up-screen, so every pass is the player's y sinking past the
/// vehicle's — with an edge-to-edge lateral gap inside the award window
/// while the taxi was moving at speed. The rules are geometry, judged at
/// the moment of the pass:
///
///  - **No contact.** A vehicle the taxi already scraped or crashed into
///    this episode is disqualified — a touch that happened is not a touch
///    that almost did. (Enforced by the caller, which owns the contact
///    flag; see [TrafficVehicle.contactedPlayer].)
///  - **Tight clearance.** The logical bodies — the boxes the player
///    actually steers, never the hitboxes — passed within
///    [gapThreshold] px of daylight, down to [contactSlack] px of logical
///    overlap. The overlap range is real: contact is judged on the
///    tightened hitboxes (issue #6), so two bodies can legally interleave
///    and both drive away.
///  - **At speed.** The taxi's forward speed was at least
///    [minPassSpeed] px/s — the same floor where the speed lines begin,
///    so "fast enough to score" and "fast enough to look fast" are the
///    same number.
///
/// Each vehicle is judged exactly once, at the pass: threading a needle
/// between an oncoming car and an overtake pays twice (once per vehicle),
/// which is how the flagship moment outranks an ordinary lane-edge shave
/// without any special-case rule. One vehicle can never pay twice.
///
/// Pure logic — no Flame component state — so every number is unit
/// testable, matching [CollisionRules] and [ImpactFx].
class NearMissRules {
  NearMissRules._();

  /// Largest edge-to-edge lateral gap (px) at which a cleared pass is a
  /// close call. The road's lanes sit 100 px apart with 40-px bodies
  /// (`DifficultyCurve.oncomingLaneX`/`sameDirectionLaneX`), so riding a
  /// lane border shaves to ~10 px of daylight and a full centre-line
  /// thread pays ~10 px on both sides — both inside this window — while
  /// lane-keeping at 60 px never scores. Under a third of a car width:
  /// tight enough that only deliberate shaving earns, wide enough that
  /// the threads the geometry allows are all reachable.
  static const double gapThreshold = 14.0;

  /// Deepest logical overlap (px) a cleared pass may sit at and still
  /// count. Contact is ruled on the tightened hitboxes — the player's is
  /// inset 12.5% per side and traffic's 10% (issue #6) — so the logical
  /// bodies of the 40-px vehicles the lane spacing assumes can overlap by
  /// up to 9 px and still miss. Past this depth a no-contact pass would
  /// be a hitbox artefact, not a close call.
  static const double contactSlack = 9.0;

  /// Slowest taxi forward speed (px/s) at which a pass can score. Pinned
  /// to [ImpactFx.speedLinesStartSpeed] — the speed the windshield
  /// already calls "fast" — so a close call never lands on a crawl.
  static const double minPassSpeed = 95.0;

  /// Edge-to-edge distance between the two logical bodies along the road
  /// (x), in px. Negative when the boxes overlap; the award window runs
  /// from -[contactSlack] (a hitbox-miss interleave) to [gapThreshold].
  static double lateralGap({
    required Vector2 playerPosition,
    required Vector2 playerSize,
    required Vector2 vehiclePosition,
    required Vector2 vehicleSize,
  }) {
    final centreDistance = (playerPosition.x - vehiclePosition.x).abs();
    return centreDistance - (playerSize.x + vehicleSize.x) / 2;
  }

  /// True when a pass cleared with [gap] px of lateral daylight at
  /// [playerForwardSpeed] px/s is a close call. Contact is not this
  /// function's question — a vehicle that touched disqualifies before
  /// the geometry is consulted.
  static bool isCloseCall({
    required double gap,
    required double playerForwardSpeed,
  }) {
    return gap > -contactSlack &&
        gap <= gapThreshold &&
        playerForwardSpeed >= minPassSpeed;
  }
}

/// The sound and haptic legs of close-call feedback (issue #23): a
/// medium haptic thump and a short system click — the closest an asset
/// free game gets to a whoosh. The app ships no audio assets (see
/// CLAUDE.md: returning audio means re-listing every file in
/// LICENSES.txt with a confirmed source), so the sound leg rides the
/// OS-provided system click: nothing to license, nothing to attribute.
/// It honours the save's existing sound setting, so the flag the app
/// already stores governs it.
class CloseCallFeedback {
  CloseCallFeedback._();

  /// Fires the thump, and the click when [soundEnabled].
  static void play({required bool soundEnabled}) {
    HapticFeedback.mediumImpact();
    if (soundEnabled) {
      SystemSound.play(SystemSoundType.click);
    }
  }
}
