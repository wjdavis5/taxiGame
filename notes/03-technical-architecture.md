# Technical Architecture

## System Overview

This document describes the technical architecture of the Pick Me Up 3D taxi game built with Flutter and Flame.

---

## Architecture Patterns

### 1. Component-Based Architecture (Flame ECS)
Flame uses an Entity-Component-System (ECS) pattern:
- **Components**: Individual game objects (vehicles, roads, passengers)
- **Systems**: Logic that operates on components (collision, movement, rendering)
- **Game**: Central coordinator managing all systems and components

### 2. State Management
- **Provider**: For global game state (coins, unlocked vehicles, settings)
- **Local State**: Component-level state within Flame components
- **Persistent State**: SharedPreferences for save data

### 3. Service Layer
Separate services for cross-cutting concerns:
- AudioService: Sound effects and music playback
- StorageService: Save/load game data
- AnalyticsService: Track player behavior (future)

---

## Core Game Loop

```
┌─────────────────────────────────────┐
│      Flutter App Entry Point        │
│           (main.dart)               │
└─────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│         GameWidget (Flame)          │
│     Initializes TaxiGame            │
└─────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────┐
│          TaxiGame (FlameGame)       │
│  • onLoad()  - Initialize           │
│  • update()  - Game logic           │
│  • render()  - Draw (implicit)      │
└─────────────────────────────────────┘
                  │
     ┌────────────┴────────────┐
     ▼                         ▼
┌──────────┐           ┌─────────────┐
│Components│           │   Systems   │
│  (ECS)   │           │             │
└──────────┘           └─────────────┘
```

### Frame Cycle (60 FPS target)
1. **Input**: Detect touch/mouse events
2. **Update**: Update all component positions, states
3. **Collision**: Check for collisions
4. **Render**: Draw all visible components
5. **Audio**: Play scheduled sounds
6. Repeat (16.67ms per frame for 60 FPS)

---

## Component Structure

### Core Components

#### 1. PlayerVehicle Component
```dart
class PlayerVehicle extends PositionComponent with CollisionCallbacks, HasGameRef {
  // Properties
  Vector2 velocity;
  double acceleration;
  double maxSpeed;
  bool isAccelerating;
  
  // Methods
  @override
  void update(double dt) {
    // Update position based on velocity
    // Apply acceleration or deceleration
  }
  
  @override
  void onCollision(Set<Vector2> points, PositionComponent other) {
    // Handle collisions
  }
}
```

#### 2. TrafficVehicle Component
```dart
class TrafficVehicle extends PositionComponent with CollisionCallbacks {
  // Properties
  Vector2 velocity;
  Path pathToFollow;
  
  // Methods
  @override
  void update(double dt) {
    // Follow predetermined path
    // Maintain constant speed
  }
}
```

#### 3. Passenger Component
```dart
class Passenger extends PositionComponent {
  // Properties
  Vector2 pickupLocation;
  Vector2 dropoffLocation;
  bool isInVehicle;
  
  // Methods
  void pickup() { ... }
  void dropoff() { ... }
}
```

#### 4. Road Component
```dart
class RoadSegment extends PositionComponent {
  // Properties
  RoadType type; // straight, curve, intersection
  List<Lane> lanes;
  
  // Methods
  @override
  void render(Canvas canvas) {
    // Draw road texture, lane markings
  }
}
```

---

## System Architecture

### Input System
```
Touch/Mouse Input
      ↓
InputComponent (Flame)
      ↓
GameController
      ↓
PlayerVehicle.isAccelerating = true/false
```

**Implementation:**
```dart
class InputController extends Component with TapCallbacks {
  @override
  void onTapDown(TapDownEvent event) {
    gameRef.playerVehicle.startAccelerating();
  }
  
  @override
  void onTapUp(TapUpEvent event) {
    gameRef.playerVehicle.stopAccelerating();
  }
}
```

### Collision System
```
CollisionDetection (Flame built-in)
      ↓
Check all PositionComponent with CollisionCallbacks
      ↓
Call onCollision() on colliding components
      ↓
Game responds (level fail, pickup passenger, etc.)
```

**Hitbox Strategy:**
- Use `RectangleHitbox` for vehicles (slightly smaller than visual)
- Use `CircleHitbox` for pickup/dropoff zones
- Forgiving hitboxes: 90% of visual size for fairness

### Physics System
```
update(dt) called every frame
      ↓
Calculate new velocity: v = v + (a * dt)
      ↓
Update position: pos = pos + (v * dt)
      ↓
Apply constraints (max speed, bounds)
      ↓
Render at new position
```

**Physics Properties:**
- Acceleration: 200 units/second²
- Max Speed: 300 units/second
- Deceleration: 400 units/second² (instant stop feel)
- No friction (arcade-style)

### Pathfinding System
```
Player reaches pickup
      ↓
Calculate path to dropoff
      ↓
Generate waypoints along roads
      ↓
PlayerVehicle follows waypoints automatically
      ↓
Player controls speed via tap-hold
```

**Pathfinding Algorithm:**
- Simple waypoint system (not A*)
- Predetermined paths per level
- No dynamic pathfinding (performance optimization)

---

## Data Models

### Level Data
```dart
class Level {
  int levelNumber;
  String name;
  LevelDifficulty difficulty;
  List<RoadSegment> roads;
  List<TrafficPattern> trafficPatterns;
  List<Passenger> passengers;
  int coinReward;
  Vector2 startPosition;
}
```

**Storage Format: JSON**
```json
{
  "levelNumber": 1,
  "difficulty": "easy",
  "roads": [
    {"type": "straight", "length": 500, "lanes": 2}
  ],
  "traffic": [
    {"type": "sedan", "speed": 100, "spawnTime": 2.0}
  ],
  "passengers": [
    {"pickup": [100, 200], "dropoff": [400, 200]}
  ],
  "coinReward": 50
}
```

### Vehicle Data
```dart
class VehicleData {
  String id;
  String name;
  int unlockLevel;
  int coinCost;
  int? gemCost;
  Color color;
  VehicleType type;
  bool isUnlocked;
}
```

### Save Data
```dart
class SaveData {
  int currentLevel;
  int totalCoins;
  int totalGems;
  List<String> unlockedVehicles;
  String selectedVehicle;
  Map<String, bool> achievements;
  Settings settings;
}
```

---

## File Structure

```
taxi_game/
├── lib/
│   ├── main.dart                      # App entry point
│   │
│   ├── game/
│   │   ├── taxi_game.dart             # Main Flame game class
│   │   │
│   │   ├── components/
│   │   │   ├── player_vehicle.dart
│   │   │   ├── traffic_vehicle.dart
│   │   │   ├── passenger.dart
│   │   │   ├── road_segment.dart
│   │   │   ├── pickup_zone.dart
│   │   │   ├── dropoff_zone.dart
│   │   │   └── background.dart
│   │   │
│   │   ├── systems/
│   │   │   ├── input_controller.dart
│   │   │   ├── collision_handler.dart
│   │   │   ├── traffic_spawner.dart
│   │   │   ├── camera_controller.dart
│   │   │   └── particle_manager.dart
│   │   │
│   │   └── levels/
│   │       ├── level.dart             # Level model
│   │       ├── level_loader.dart      # Load levels from JSON
│   │       └── level_generator.dart   # Procedural generation (future)
│   │
│   ├── ui/
│   │   ├── screens/
│   │   │   ├── main_menu_screen.dart
│   │   │   ├── game_screen.dart       # Contains GameWidget
│   │   │   ├── level_complete_screen.dart
│   │   │   ├── level_failed_screen.dart
│   │   │   ├── garage_screen.dart
│   │   │   ├── settings_screen.dart
│   │   │   └── level_select_screen.dart
│   │   │
│   │   ├── widgets/
│   │   │   ├── hud_overlay.dart       # In-game HUD
│   │   │   ├── coin_display.dart
│   │   │   ├── vehicle_card.dart
│   │   │   └── custom_button.dart
│   │   │
│   │   └── overlays/
│   │       ├── pause_menu.dart
│   │       └── tutorial_overlay.dart
│   │
│   ├── models/
│   │   ├── vehicle_data.dart
│   │   ├── level_data.dart
│   │   ├── save_data.dart
│   │   ├── settings.dart
│   │   └── traffic_pattern.dart
│   │
│   ├── services/
│   │   ├── audio_service.dart         # Sound & music playback
│   │   ├── storage_service.dart       # Save/load to SharedPreferences
│   │   ├── game_state_service.dart    # Global game state
│   │   └── asset_loader.dart          # Preload assets
│   │
│   ├── utils/
│   │   ├── constants.dart             # Game constants
│   │   ├── colors.dart                # Color palette
│   │   ├── math_utils.dart            # Vector math helpers
│   │   └── collision_utils.dart       # Collision helpers
│   │
│   └── config/
│       ├── game_config.dart           # Game configuration
│       └── vehicle_config.dart        # Vehicle definitions
│
├── assets/
│   ├── images/
│   │   ├── vehicles/
│   │   │   ├── taxi_01.svg
│   │   │   ├── sedan_01.svg
│   │   │   └── ...
│   │   ├── environment/
│   │   │   ├── road_straight.png
│   │   │   ├── building_01.svg
│   │   │   └── ...
│   │   └── ui/
│   │       ├── button_bg.png
│   │       └── ...
│   │
│   ├── audio/
│   │   ├── sfx/
│   │   │   ├── engine_start.mp3
│   │   │   ├── crash.mp3
│   │   │   └── ...
│   │   └── music/
│   │       ├── menu_theme.mp3
│   │       └── gameplay_theme.mp3
│   │
│   └── data/
│       └── levels/
│           ├── level_001.json
│           ├── level_002.json
│           └── ...
│
├── test/
│   ├── unit/
│   │   ├── models_test.dart
│   │   └── services_test.dart
│   ├── widget/
│   │   └── ui_test.dart
│   └── integration/
│       └── game_flow_test.dart
│
├── pubspec.yaml
└── README.md
```

---

## Rendering Pipeline

### Layer Order (back to front)
1. **Background** (sky gradient)
2. **Environment** (buildings, parallax)
3. **Road** (asphalt, lane markings)
4. **Shadows** (vehicle shadows)
5. **Vehicles** (traffic, then player)
6. **Particles** (smoke, sparkles)
7. **Markers** (pickup/dropoff zones)
8. **HUD** (overlay, always on top)

### Camera System
```dart
class CameraController extends Component {
  void follow(PlayerVehicle player, double dt) {
    // Smooth camera following
    Vector2 targetPos = player.position;
    camera.position = camera.position.lerp(targetPos, 0.1);
    
    // Add screen shake on collision
    if (shouldShake) {
      camera.position += randomOffset();
    }
  }
}
```

### Optimization Strategies
- **Object Pooling**: Reuse traffic vehicles instead of creating/destroying
- **Culling**: Only render objects in viewport
- **LOD**: Use simpler graphics for distant objects
- **Batching**: Batch similar draw calls
- **Caching**: Cache static elements (buildings, roads)

---

## State Management

### Global State (Provider)
```dart
class GameStateProvider extends ChangeNotifier {
  SaveData _saveData;
  
  int get coins => _saveData.totalCoins;
  
  void addCoins(int amount) {
    _saveData.totalCoins += amount;
    notifyListeners();
    _storageService.save(_saveData);
  }
  
  // Other global state methods...
}
```

### Usage in UI
```dart
Consumer<GameStateProvider>(
  builder: (context, gameState, child) {
    return Text('Coins: ${gameState.coins}');
  },
)
```

---

## Audio Architecture

### Audio Service
```dart
class AudioService {
  FlameAudio audioPlayer;
  
  // Sound effects
  Future<void> playSound(String soundName, {double volume = 1.0}) async {
    await FlameAudio.play('sfx/$soundName.mp3', volume: volume);
  }
  
  // Background music
  Future<void> playMusic(String musicName, {bool loop = true}) async {
    await FlameAudio.bgm.play('music/$musicName.mp3');
  }
  
  void stopMusic() {
    FlameAudio.bgm.stop();
  }
  
  void setMusicVolume(double volume) {
    FlameAudio.bgm.audioPlayer.setVolume(volume);
  }
}
```

### Audio Events
- Engine start: On game start
- Acceleration: On tap down
- Brake: On tap up (if moving fast)
- Crash: On collision
- Pickup: On passenger pickup
- Dropoff: On passenger dropoff
- Coin collect: On coin earn
- Button click: On any UI button

---

## Performance Targets

### Frame Rate
- **Target**: 60 FPS (16.67ms per frame)
- **Acceptable**: 30 FPS on low-end devices
- **Strategy**: Dynamic quality scaling

### Memory
- **Target**: <200MB RAM usage
- **Strategy**: Object pooling, asset unloading

### Load Time
- **Target**: <3 seconds to game ready
- **Strategy**: Lazy loading, splash screen

### Battery
- **Target**: <15% per hour
- **Strategy**: Efficient rendering, reduce CPU work in menus

---

## Testing Strategy

### Unit Tests
- Model validation
- Service logic
- Collision math
- Path calculations

### Widget Tests
- UI rendering
- Navigation
- State updates

### Integration Tests
- Complete game flow
- Save/load
- Level progression

### Manual Testing
- Gameplay feel
- Difficulty balance
- Cross-platform compatibility

---

## Build & Deployment

### Build Commands
```bash
# Development build (with hot reload)
flutter run

# Android APK
flutter build apk --release

# iOS IPA
flutter build ios --release

# Web
flutter build web --release

# Windows
flutter build windows --release
```

### Platform-Specific Configurations
- **Android**: `android/app/build.gradle`
- **iOS**: `ios/Runner.xcodeproj`
- **Web**: `web/index.html`

---

## Security Considerations

### Save Data
- Encrypt save data to prevent cheating
- Validate data integrity on load
- Use secure storage for sensitive data

### Anti-Cheat
- Server-side validation (future)
- Obfuscate code in release builds
- Rate limiting for rewards

---

## Future Architecture Enhancements

### Multiplayer
- WebSocket connection
- Ghost replays
- Leaderboards (Firebase)

### Live Operations
- Remote config (Firebase Remote Config)
- A/B testing
- Dynamic content updates

### Analytics
- Event tracking
- Player behavior analysis
- Crash reporting

---

## Dependencies

### Core
- `flutter`: SDK
- `flame`: ^1.11.0 (Game engine)
- `flame_audio`: ^2.1.0 (Audio)

### UI & State
- `provider`: ^6.1.1 (State management)
- `flutter_svg`: ^2.0.9 (SVG rendering)

### Storage
- `shared_preferences`: ^2.2.2 (Save data)
- `path_provider`: ^2.1.1 (File paths)

### Utilities
- `vector_math`: ^2.1.4 (Math operations)

### Development
- `flutter_test`: SDK (Testing)
- `integration_test`: SDK (Integration tests)

---

## Next Steps
1. Initialize Flutter project
2. Add dependencies to pubspec.yaml
3. Create folder structure
4. Implement TaxiGame class (main game)
5. Create PlayerVehicle component
6. Test basic rendering

This architecture provides a solid foundation for building the taxi game with clear separation of concerns and scalability.
