// ignore_for_file: prefer_const_constructors, unnecessary_const, unnecessary_import
// PM diagnostic probe (issue #40): renders the SAME taxi sprite three
// ways on one screen to isolate which image path fails on real renderers
// (Impeller) while passing on the host tester:
//
//   A) SpriteComponent — the exact construction PlayerVehicle uses
//   B) custom render() with canvas.drawImageRect on the loaded ui.Image
//   C) Image.asset — the widget path known to work (garage previews)
//
// Run: flutter run -t lib/dev_sprite_probe.dart -d emulator-5554
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: const SpriteProbeScreen(),
  ));
}

class SpriteProbeScreen extends StatelessWidget {
  const SpriteProbeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF202020),
      body: Column(children: [
        SizedBox(height: 24),
        Text('A: SpriteComponent (top)  B: drawImageRect (middle)',
            style: TextStyle(color: Colors.white, fontSize: 12)),
        Text('C: Image.asset (bottom)',
            style: TextStyle(color: Colors.white, fontSize: 12)),
        Expanded(
          child: Stack(children: [
            GameWidget(game: ProbeGame()),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Image.asset(
                  'assets/images/vehicles/player/taxi_yellow.png',
                  width: 120,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class ProbeGame extends FlameGame {
  final _mover = _Mover();

  ProbeGame()
      : super(
          camera: CameraComponent.withFixedResolution(width: 400, height: 800),
        );

  @override
  Future<void> onLoad() async {
    camera.follow(_mover, verticalOnly: true);
    final image =
        await images.load('vehicles/player/taxi_yellow.png');

    // C2) A plain drawn rectangle through the camera: does ANYTHING show?
    add(RectangleComponent(
      size: Vector2(120, 30),
      position: Vector2(size.x / 2, size.y * 0.12),
      anchor: Anchor.center,
      paint: Paint()..color = const Color(0xFFFF5252),
    ));

    // A) The exact SpriteComponent construction from PlayerVehicle.
    world.add(SpriteComponent(
      sprite: Sprite(image),
      size: Vector2(60, 40),
      position: Vector2(size.x / 2, size.y * 0.3),
      angle: -1.5708,
      anchor: Anchor.center,
    ));

    // B) The same image, drawn directly with drawImageRect.
    world.add(RawImageDrawer(
      image: image,
      position: Vector2(size.x / 2, size.y * 0.55),
      size: Vector2(60, 40),
    ));
    world.add(_mover);
  }
}

class _Mover extends PositionComponent {}

class RawImageDrawer extends PositionComponent {
  RawImageDrawer({
    required ui.Image image,
    required Vector2 position,
    required Vector2 size,
  })  : _image = image,
        super(position: position, size: size, anchor: Anchor.center);

  final ui.Image _image;

  @override
  void render(Canvas canvas) {
    canvas.drawImageRect(
      _image,
      Rect.fromLTWH(0, 0, _image.width.toDouble(), _image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()..filterQuality = FilterQuality.low,
    );
  }
}
