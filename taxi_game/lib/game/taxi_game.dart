import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import 'components/player_vehicle.dart';
import 'components/road_segment.dart';
import 'components/background.dart';
import 'systems/input_controller.dart';
import 'levels/level.dart';

/// Main game class that manages the entire game loop and components
class TaxiGame extends FlameGame with HasCollisionDetection, TapCallbacks {
  late PlayerVehicle player;
  late InputController inputController;
  late GameLevel currentLevel;
  
  bool isGameActive = false;
  int currentLevelNumber = 1;
  
  @override
  Color backgroundColor() => const Color(0xFF87CEEB); // Sky blue
  
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // Add camera
    camera = CameraComponent.withFixedResolution(
      width: 400,
      height: 800,
    );
    
    // Initialize game
    await _initializeGame();
  }
  
  Future<void> _initializeGame() async {
    // Add background
    final background = Background();
    add(background);
    
    // Create a simple test level
    currentLevel = GameLevel.createTestLevel();
    
    // Add road
    final road = RoadSegment(
      position: Vector2(200, 0),
      length: 1000,
    );
    add(road);
    
    // Add player vehicle
    player = PlayerVehicle(
      position: Vector2(200, 600),
    );
    add(player);
    
    // Add input controller
    inputController = InputController(player);
    add(inputController);
    
    // Make camera follow player
    camera.follow(player);
    
    isGameActive = true;
  }
  
  @override
  void update(double dt) {
    super.update(dt);
    
    if (!isGameActive) return;
    
    // Game logic updates here
  }
  
  void restartLevel() {
    // Reset player position
    player.reset();
    isGameActive = true;
  }
  
  void onLevelComplete() {
    isGameActive = false;
    // Show level complete overlay
    overlays.add('levelComplete');
  }
  
  void onLevelFailed() {
    isGameActive = false;
    // Show level failed overlay
    overlays.add('levelFailed');
  }
  
  void pauseGame() {
    paused = true;
    overlays.add('pauseMenu');
  }
  
  void resumeGame() {
    paused = false;
    overlays.remove('pauseMenu');
  }
}
