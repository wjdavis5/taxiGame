import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../data/vehicle_catalog.dart';
import '../../models/ghost_trace.dart';
import '../systems/ghost_replay.dart';
import '../taxi_game.dart';
import '../vehicle_sprites.dart';

/// The translucent replay of the best Daily Shift run (issue #20).
///
/// Purely visual — no hitbox, no collisions, no movement of its own: it
/// follows its [GhostPlayback] along the recorded path, driven by the
/// same live-shift clock the recording was taken on, so a hit-stop or
/// crash stall freezes the ghost with the run. When the trace runs out
/// the ghost parks at its final recorded position: that run is over —
/// it banked or it wrecked — and the race is against the road it left
/// behind.
///
/// Rendered at a third of the player's opacity and added to the world
/// underneath the real taxi (the game adds it before the player), so an
/// overlap always reads as the player's car.
class GhostCar extends PositionComponent with HasGameReference<TaxiGame> {
  GhostCar({required this.trace, this.sprite})
      : playback = GhostPlayback(trace),
        super(
          position: _startOf(trace),
          anchor: Anchor.center,
        );

  /// The stored best run being replayed.
  final GhostTrace trace;

  /// The driven time already replayed.
  double _elapsed = 0;

  /// Pre-loaded sprite to render instead of the bundled one (tests
  /// inject a fake here). When null the sprite is loaded from the
  /// bundled PNG for the vehicle that set the trace.
  final Sprite? sprite;

  /// The replay this component animates.
  final GhostPlayback playback;

  static Vector2 _startOf(GhostTrace trace) =>
      GhostPlayback(trace).positionAt(0);

  /// How faded the ghost renders — a visible after-image that never
  /// competes with the real taxi or traffic for readability.
  static const double ghostOpacity = 0.35;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    // The same logical body the car that set the trace drove with, so
    // the ghost's footprint matches its race; an unknown id (an older
    // save, a hand edit) falls back to the starter cab like everywhere
    // else in the game.
    final stats = VehicleCatalog.statsFor(trace.vehicleId);
    size = Vector2(stats.width, stats.height);

    final carSprite = sprite ??
        await game.loadSprite(
            VehicleSprites.playerSpritePath(trace.vehicleId));

    // Same quarter-turn as [PlayerVehicle]: the bundled art is side-view
    // facing right, the world drives up the screen.
    add(SpriteComponent(
      sprite: carSprite,
      size: Vector2(size.y, size.x),
      position: size / 2,
      angle: -math.pi / 2,
      anchor: Anchor.center,
    )..paint.color = Colors.white.withValues(alpha: ghostOpacity));
  }

  @override
  void update(double dt) {
    super.update(dt);

    // The recorded clock only ran while the shift was live, so the
    // replay freezes whenever the shift does — hit-stop, crash stall,
    // and the settled shift after a bank or wreck.
    if (!game.isGameActive) return;
    _elapsed += dt;
    position = playback.positionAt(_elapsed);
  }
}
