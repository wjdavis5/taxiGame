import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// One-shot particle burst in world space (issue #7): the punctuation for
/// a pickup, a dropoff, a crash, or a scrape.
///
/// Draws plain circles — no textures, no saveLayer, at most a couple of
/// dozen short-lived particles — so a burst costs almost nothing on the
/// oldest supported device. Removes itself once every particle has died.
class BurstParticles extends PositionComponent {
  BurstParticles({
    required Vector2 position,
    required List<Color> colors,
    this.count = 14,
    this.maxSpeed = 220,
    this.lifetime = BurstParticles.defaultLifetime,
    this.gravity = 480,
    this.maxRadius = 4.5,
    math.Random? random,
  })  : _colors = colors,
        _random = random ?? math.Random(),
        super(position: position.clone(), anchor: Anchor.center);

  /// How many particles the burst spawns.
  final int count;

  /// Launch speed of the fastest particle, px/s.
  final double maxSpeed;

  /// Lifetime of the longest-lived particle, seconds.
  final double lifetime;

  /// The default [lifetime].
  static const double defaultLifetime = 0.55;

  /// Downward pull on the particles, px/s².
  final double gravity;

  /// Radius of the biggest particle, px.
  final double maxRadius;

  final List<Color> _colors;
  final math.Random _random;

  final List<_Particle> _particles = [];

  /// Particles still flying; exposed for tests.
  int get liveParticles => _particles.length;

  @override
  void onLoad() {
    super.onLoad();

    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final speed = maxSpeed * (0.35 + 0.65 * _random.nextDouble());
      final radius = 1.5 + (maxRadius - 1.5) * _random.nextDouble();
      _particles.add(_Particle(
        velocity: Vector2(math.cos(angle), math.sin(angle)) * speed,
        radius: radius,
        color: _colors[_random.nextInt(_colors.length)],
        // Staggered lifetimes so the burst fizzles instead of popping out
        // all at once.
        lifetime: lifetime * (0.6 + 0.4 * _random.nextDouble()),
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    for (final particle in _particles) {
      particle.age += dt;
      particle.velocity.y += gravity * dt;
      particle.position += particle.velocity * dt;
    }
    _particles.removeWhere((p) => p.age >= p.lifetime);

    if (_particles.isEmpty) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    for (final particle in _particles) {
      final t = (particle.age / particle.lifetime).clamp(0.0, 1.0);
      particle.paint.color = particle.baseColor.withValues(alpha: 1.0 - t);
      canvas.drawCircle(
        particle.position.toOffset(),
        particle.radius * (1.0 - 0.5 * t),
        particle.paint,
      );
    }
  }
}

class _Particle {
  _Particle({
    required this.velocity,
    required this.radius,
    required Color color,
    required this.lifetime,
  })  : baseColor = color,
        paint = Paint()..color = color;

  Vector2 position = Vector2.zero();
  final Vector2 velocity;
  final double radius;
  final Color baseColor;
  final Paint paint;
  final double lifetime;

  double age = 0;
}
