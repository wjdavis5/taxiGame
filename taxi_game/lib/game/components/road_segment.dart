import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Road segment component that renders the road
class RoadSegment extends PositionComponent {
  final double length;
  final int lanes;
  
  RoadSegment({
    required Vector2 position,
    required this.length,
    this.lanes = 2,
  }) : super(position: position);
  
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    size = Vector2(200, length);
    anchor = Anchor.topCenter;
  }
  
  @override
  void render(Canvas canvas) {
    super.render(canvas);
    
    // Draw road surface (dark gray)
    final roadPaint = Paint()
      ..color = const Color(0xFF404040)
      ..style = PaintingStyle.fill;
    
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      roadPaint,
    );
    
    // Draw lane markings (white dashed lines)
    final laneMarkingPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    // Center line
    _drawDashedLine(
      canvas,
      Offset(size.x / 2, 0),
      Offset(size.x / 2, size.y),
      laneMarkingPaint,
      dashLength: 20,
      gapLength: 15,
    );
    
    // Draw road edges
    final edgePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    
    canvas.drawLine(
      Offset(0, 0),
      Offset(0, size.y),
      edgePaint,
    );
    
    canvas.drawLine(
      Offset(size.x, 0),
      Offset(size.x, size.y),
      edgePaint,
    );
  }
  
  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    double dashLength = 10,
    double gapLength = 5,
  }) {
    final distance = (end - start).distance;
    final dashCount = (distance / (dashLength + gapLength)).floor();
    
    final dx = (end.dx - start.dx) / distance;
    final dy = (end.dy - start.dy) / distance;
    
    for (var i = 0; i < dashCount; i++) {
      final dashStart = Offset(
        start.dx + dx * i * (dashLength + gapLength),
        start.dy + dy * i * (dashLength + gapLength),
      );
      
      final dashEnd = Offset(
        dashStart.dx + dx * dashLength,
        dashStart.dy + dy * dashLength,
      );
      
      canvas.drawLine(dashStart, dashEnd, paint);
    }
  }
}
