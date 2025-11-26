import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import 'components/player_vehicle.dart';
import 'components/road_segment.dart';
import 'components/background.dart';
import 'components/traffic_spawner.dart';
import 'components/pickup_zone.dart';
import 'components/dropoff_zone.dart';
import 'levels/level.dart';
import '../models/passenger_data.dart';

/// Main game class that manages the entire game loop and components
class TaxiGame extends FlameGame with HasCollisionDetection, TapCallbacks {
  late PlayerVehicle player;
  late GameLevel currentLevel;
  late TrafficSpawner trafficSpawner;

  List<PassengerData> passengers = [];
  int passengersDelivered = 0;

  bool isGameActive = false;
  int currentLevelNumber = 1;

  // Touch position tracking for steering
  Vector2? _touchPosition;
  
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

    // Add traffic spawner based on level pattern
    trafficSpawner = TrafficSpawner(pattern: currentLevel.trafficPattern);
    add(trafficSpawner);

    // Create passengers from level data
    _createPassengers();

    // Don't follow player - keep camera fixed so player can see ahead
    // This gives better visibility of oncoming traffic

    isGameActive = true;
  }

  void _createPassengers() {
    passengers.clear();
    passengersDelivered = 0;

    // Create a passenger for each pickup/dropoff pair in the level
    for (int i = 0; i < currentLevel.pickupPoints.length; i++) {
      final pickupPoint = currentLevel.pickupPoints[i];
      final dropoffPoint = i < currentLevel.dropoffPoints.length
          ? currentLevel.dropoffPoints[i]
          : currentLevel.dropoffPoints.last;

      final passenger = PassengerData(
        id: 'passenger_$i',
        pickupLocation: pickupPoint,
        dropoffLocation: dropoffPoint,
        reward: currentLevel.coinReward ~/ currentLevel.pickupPoints.length,
      );

      passengers.add(passenger);

      // Add pickup zone
      final pickupZone = PickupZone(
        position: pickupPoint,
        passenger: passenger,
        onPickup: () => _onPassengerPickup(passenger),
      );
      add(pickupZone);

      // Add dropoff zone
      final dropoffZone = DropoffZone(
        position: dropoffPoint,
        passenger: passenger,
        onDropoff: () => _onPassengerDropoff(passenger),
      );
      add(dropoffZone);
    }

    // Start by navigating to first pickup (optional - can keep manual for now)
    if (passengers.isNotEmpty) {
      // Auto-navigate to first pickup point
      // player.navigateTo(passengers.first.pickupLocation);
      // For now, keep it manual so player has full control
    }
  }

  void _onPassengerPickup(PassengerData passenger) {
    // Update player visual state
    player.hasPassenger = true;

    // Auto-navigate to dropoff location (OPTIONAL - enable for autopilot)
    // player.navigateTo(passenger.dropoffLocation);

    // Could add pickup sound effect here
    // audioService.playSound('pickup');
  }

  void _onPassengerDropoff(PassengerData passenger) {
    passengersDelivered++;

    // Update player visual state
    player.hasPassenger = false;

    // Stop autopilot if it was active
    player.stopNavigation();

    // Could add dropoff sound effect here
    // audioService.playSound('dropoff');

    // Check if there are more passengers
    if (passengersDelivered < passengers.length) {
      // Find next passenger that hasn't been picked up
      final nextPassenger = passengers.firstWhere(
        (p) => !p.isPickedUp,
        orElse: () => passenger,
      );

      // Auto-navigate to next pickup (OPTIONAL - enable for autopilot)
      // if (nextPassenger != passenger) {
      //   player.navigateTo(nextPassenger.pickupLocation);
      // }
    } else {
      // All passengers delivered!
      _completeLevel();
    }
  }

  void _completeLevel() {
    // Level complete!
    onLevelComplete();
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

    // Clear and restart traffic
    trafficSpawner.clear();
    trafficSpawner.resume();

    // Recreate passengers and zones
    _createPassengers();

    // Remove any overlays
    overlays.remove('levelFailed');
    overlays.remove('levelComplete');

    isGameActive = true;
  }
  
  void onLevelComplete() {
    isGameActive = false;
    // Show level complete overlay
    overlays.add('levelComplete');
  }
  
  void onLevelFailed() {
    isGameActive = false;

    // Pause traffic spawning
    trafficSpawner.pause();

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

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (isGameActive) {
      _touchPosition = event.localPosition;
      player.startAccelerating();
      _updateSteeringFromTouch();
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    _touchPosition = null;
    player.stopAccelerating();
    player.setSteering(0);
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    super.onTapCancel(event);
    _touchPosition = null;
    player.stopAccelerating();
    player.setSteering(0);
  }

  void _updateSteeringFromTouch() {
    if (_touchPosition == null || !isGameActive) return;

    // Calculate steering based on touch position relative to screen center
    final screenCenter = size.x / 2;
    final touchX = _touchPosition!.x;
    final deltaX = touchX - screenCenter;

    // Convert to steering input (-1 to 1)
    // Divide by half screen width to normalize
    final steeringInput = (deltaX / (size.x / 2)).clamp(-1.0, 1.0);
    player.setSteering(steeringInput);
  }
}
