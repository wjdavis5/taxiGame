import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Background component with sky and simple scenery
class Background extends PositionComponent {
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    size = Vector2(400, 800);
    position = Vector2.zero();
  }
  
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // Draw sky gradient
    final skyGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF87CEEB), // Sky blue
        const Color(0xFFE0F6FF), // Lighter blue
      ],
    );
    
    final paint = Paint()
      ..shader = skyGradient.createShader(
        Rect.fromLTWH(0, 0, size.x, size.y),
      );
    
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      paint,
    );
    
    // Draw simple buildings on sides (placeholders)
    _drawBuildings(canvas);
  }
  
  void _drawBuildings(Canvas canvas) {
    final buildingPaint = Paint()
      ..color = Colors.grey.shade700
      ..style = PaintingStyle.fill;
    
    // Left side buildings
    for (var i = 0; i < 5; i++) {
      canvas.drawRect(
        Rect.fromLTWH(10, i * 180.0, 60, 150),
        buildingPaint,
      );
    }
    
    // Right side buildings
    for (var i = 0; i < 5; i++) {
      canvas.drawRect(
        Rect.fromLTWH(size.x - 70, i * 180.0, 60, 150),
        buildingPaint,
      );
    }
  }
}
