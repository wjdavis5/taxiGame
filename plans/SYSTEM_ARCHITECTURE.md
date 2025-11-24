# System Architecture - Taxi Game

**Phase 2 Implementation**
**Date:** 2025-11-22

---

## Component Hierarchy

```
TaxiGame (FlameGame with Collision Detection)
│
├─ Camera (follows player)
│
├─ Background Component
│   └─ Sky gradient + building silhouettes
│
├─ RoadSegment Component
│   └─ Gray road with lane markings
│
├─ PlayerVehicle Component ⭐
│   ├─ RectangleHitbox (90% size)
│   ├─ PathfindingSystem
│   │   └─ NavigationPath
│   │       └─ Waypoint[]
│   ├─ Manual control mode
│   ├─ Autopilot mode (optional)
│   └─ hasPassenger state
│
├─ TrafficSpawner Component ✨
│   ├─ TrafficPattern
│   │   ├─ spawnInterval
│   │   └─ TrafficLaneConfig[]
│   │       ├─ laneX position
│   │       ├─ speedRange
│   │       └─ spawnProbability
│   └─ Manages vehicle lifecycle
│
├─ TrafficVehicle[] Components ✨ (spawned dynamically)
│   ├─ Type: Sedan / Truck / Sports Car / SUV / Bus
│   ├─ RectangleHitbox (85% size)
│   ├─ Path following (waypoints)
│   ├─ Speed based on type
│   └─ Auto-removal when off-screen
│
├─ PickupZone[] Components ✨
│   ├─ CircleHitbox (40px radius)
│   ├─ PassengerData reference
│   ├─ Pulsing animation
│   ├─ Person icon rendering
│   └─ onPickup callback
│
├─ DropoffZone[] Components ✨
│   ├─ CircleHitbox (40px radius)
│   ├─ PassengerData reference
│   ├─ Inactive → Active state
│   ├─ Flag icon rendering
│   └─ onDropoff callback
│
└─ InputController Component
    └─ Handles tap & hold input
```

**Legend:**
- ⭐ = Enhanced existing component
- ✨ = New component

---

## Data Flow

### Level Start
```
GameLevel.createTestLevel()
    ↓
Creates PassengerData[]
    ↓
For each passenger:
    ├─ Create PickupZone at pickupLocation
    └─ Create DropoffZone at dropoffLocation
    ↓
TrafficSpawner starts with level's TrafficPattern
    ↓
Game becomes active
```

### Gameplay Loop
```
Player moves (manual or autopilot)
    ↓
TrafficSpawner spawns vehicles
    ↓
Each frame:
    ├─ Check collision player ↔ traffic
    │   └─ If collision → Game Over
    ├─ Check collision player ↔ pickup zone
    │   └─ If collision → Pickup passenger
    └─ Check collision player ↔ dropoff zone
        └─ If collision (and has passenger) → Deliver
```

### Passenger Pickup Flow
```
Player enters PickupZone
    ↓
PickupZone.onCollisionStart(PlayerVehicle)
    ↓
PassengerData.isPickedUp = true
    ↓
Player.hasPassenger = true
    ↓
PickupZone.onPickup() callback
    ↓
Game._onPassengerPickup()
    ↓
(Optional) Player.navigateTo(dropoffLocation)
    ↓
PickupZone removed from game
```

### Passenger Dropoff Flow
```
Player enters DropoffZone (with passenger)
    ↓
DropoffZone.onCollisionStart(PlayerVehicle)
    ↓
PassengerData.isDelivered = true
    ↓
Player.hasPassenger = false
    ↓
DropoffZone.onDropoff() callback
    ↓
Game._onPassengerDropoff()
    ↓
passengersDelivered++
    ↓
Check if all delivered:
    ├─ Yes → Game._completeLevel()
    └─ No → (Optional) Navigate to next pickup
    ↓
DropoffZone removed from game
```

### Traffic Spawning Flow
```
TrafficSpawner.update(dt)
    ↓
timeSinceLastSpawn >= spawnInterval?
    ├─ No → Continue
    └─ Yes ↓
        For each lane in pattern:
            ↓
        random() <= spawnProbability?
            ├─ No → Skip lane
            └─ Yes ↓
                Create TrafficVehicle
                    ├─ Random type
                    ├─ Random speed in range
                    ├─ Position at laneX, ahead of camera
                    └─ Path: straight down
                ↓
                Add vehicle to game
```

### Traffic Movement
```
TrafficVehicle.update(dt)
    ↓
Get current waypoint from path
    ↓
Distance to waypoint < 10px?
    ├─ Yes → Advance to next waypoint
    └─ No → Continue toward current
    ↓
Calculate direction to waypoint
    ↓
Move: position += direction * speed * dt
    ↓
Off-screen (y > camera.y + 1000)?
    ├─ Yes → Remove from game
    └─ No → Continue
```

### Pathfinding (Autopilot Mode)
```
Player.navigateTo(destination)
    ↓
PathfindingSystem.setDestination(current, destination)
    ↓
Create NavigationPath (straight line, 10 segments)
    ↓
Each frame (autopilot enabled):
    ↓
PathfindingSystem.getNavigationDirection(position)
    ↓
Get current waypoint
    ↓
Distance < 15px?
    ├─ Yes → Advance to next waypoint
    └─ No → Continue
    ↓
Calculate direction to waypoint
    ↓
Get speed multiplier (slows near waypoints)
    ↓
velocity = direction * speed * multiplier
    ↓
Player moves along path
```

---

## Collision Matrix

|                  | Player | Traffic | PickupZone | DropoffZone |
|------------------|--------|---------|------------|-------------|
| **Player**       | -      | 💥 Crash| ✅ Pickup  | ✅ Dropoff  |
| **Traffic**      | 💥      | -       | -          | -           |
| **PickupZone**   | ✅      | -       | -          | -           |
| **DropoffZone**  | ✅*     | -       | -          | -           |

*Only triggers if player has passenger

---

## State Machines

### PlayerVehicle States
```
┌─────────────────────┐
│   No Passenger      │
│   Manual Control    │
└──────────┬──────────┘
           │ Enter PickupZone
           ↓
┌─────────────────────┐
│   Has Passenger     │
│   (Optional Auto)   │
└──────────┬──────────┘
           │ Enter DropoffZone
           ↓
┌─────────────────────┐
│   No Passenger      │
│   Manual Control    │
└─────────────────────┘
```

### PassengerData States
```
┌─────────────────────┐
│  Not Picked Up      │
│  isPickedUp: false  │
│  isDelivered: false │
└──────────┬──────────┘
           │ Player collision
           ↓
┌─────────────────────┐
│  Picked Up          │
│  isPickedUp: true   │
│  isDelivered: false │
└──────────┬──────────┘
           │ Dropoff collision
           ↓
┌─────────────────────┐
│  Delivered          │
│  isPickedUp: true   │
│  isDelivered: true  │
└─────────────────────┘
```

### DropoffZone States
```
┌─────────────────────┐
│   Inactive          │
│   (Gray, 30% opacity)│
└──────────┬──────────┘
           │ Passenger picked up
           ↓
┌─────────────────────┐
│   Active            │
│   (Blue, 60% opacity)│
│   Pulsing animation │
└──────────┬──────────┘
           │ Player delivers
           ↓
┌─────────────────────┐
│   Completed         │
│   (Removed)         │
└─────────────────────┘
```

### Game States
```
┌─────────────────────┐
│   Menu              │
│   isGameActive=false│
└──────────┬──────────┘
           │ Tap PLAY
           ↓
┌─────────────────────┐
│   Playing           │
│   isGameActive=true │
│   Traffic spawning  │
└─────┬────────┬──────┘
      │        │
      │        │ All delivered
      │        ↓
      │   ┌─────────────────────┐
      │   │   Level Complete    │
      │   │   isGameActive=false│
      │   └──────────┬──────────┘
      │              │ Next Level
      │              ↓
      │         (Back to Playing)
      │
      │ Collision with traffic
      ↓
┌─────────────────────┐
│   Level Failed      │
│   isGameActive=false│
│   Traffic paused    │
└──────────┬──────────┘
           │ Retry
           ↓
      (Back to Playing)
```

---

## Class Relationships

```
┌──────────────────────────────┐
│        TaxiGame              │
│  (FlameGame + Collision)     │
└───────────┬──────────────────┘
            │ has
            ├─────────────────────┬───────────────┬──────────────────┐
            │                     │               │                  │
┌───────────▼──────────┐  ┌──────▼──────┐  ┌────▼─────────┐  ┌─────▼──────┐
│   PlayerVehicle      │  │  TrafficSpaw│  │  PickupZone  │  │ DropoffZone│
│  (PositionComponent) │  │    ner      │  │  (Circle)    │  │  (Circle)  │
└───────────┬──────────┘  └──────┬──────┘  └────┬─────────┘  └─────┬──────┘
            │ has                 │ spawns       │ references       │ references
            │                     │              │                  │
┌───────────▼──────────┐  ┌──────▼──────┐  ┌────▼──────────────────▼──────┐
│ PathfindingSystem    │  │ TrafficVeh  │  │      PassengerData            │
│                      │  │   icle      │  │                               │
└───────────┬──────────┘  └──────┬──────┘  └───────────────────────────────┘
            │ uses                │ follows
            │                     │
┌───────────▼──────────┐  ┌──────▼──────┐
│  NavigationPath      │  │  Waypoint[] │
│                      │  │             │
└──────────────────────┘  └─────────────┘
```

---

## File Dependencies

```
taxi_game.dart
├── imports ─► player_vehicle.dart
│                └─► pathfinding_system.dart
│                      └─► waypoint.dart
├── imports ─► traffic_spawner.dart
│                └─► traffic_vehicle.dart
│                      └─► traffic_pattern.dart
├── imports ─► pickup_zone.dart
│                └─► passenger_data.dart
└── imports ─► dropoff_zone.dart
                 └─► passenger_data.dart
```

---

## Performance Considerations

### Spawning Limits
```
TrafficSpawner
├─ Light pattern: ~20 vehicles/minute
├─ Medium pattern: ~30 vehicles/minute
└─ Heavy pattern: ~40 vehicles/minute

Auto-cleanup when off-screen
└─ Typically 3-10 active vehicles at once
```

### Collision Detection
```
Flame's built-in QuadTree
├─ O(log n) collision checks
├─ Spatial partitioning
└─ Only checks nearby objects

Hitbox sizes:
├─ Player: 90% of sprite (forgiving)
├─ Traffic: 85% of sprite (forgiving)
└─ Zones: Fixed 40px radius
```

### Pathfinding Optimization
```
Simple straight-line paths
├─ No A* algorithm needed
├─ Pre-calculated waypoints
├─ O(1) lookup for current waypoint
└─ Minimal CPU usage

Segments: 10 waypoints per path
└─ Smooth enough for visual quality
```

### Rendering
```
All simple shapes (no sprites yet)
├─ Canvas.drawCircle
├─ Canvas.drawRect
├─ Canvas.drawRRect
└─ Canvas.drawPath

No transparency effects
No particle systems (yet)
└─ Target: 60 FPS even on low-end devices
```

---

## Extension Points

### Adding New Vehicle Types
1. Add to `TrafficVehicleType` enum
2. Define size in `TrafficVehicleTypeExtension.size`
3. Define speed in `TrafficVehicleTypeExtension.speedMultiplier`
4. Add color in `TrafficVehicle._getColorForType()`

### Adding New Traffic Patterns
1. Add static getter to `TrafficPattern` class
2. Define spawn interval
3. Define lane configurations
4. Reference in level JSON

### Adding New Levels
1. Create JSON file in `assets/levels/`
2. Define pickup/dropoff points
3. Choose traffic pattern
4. Set coin reward
5. Load in level progression

### Adding Autopilot Features
1. Uncomment navigation lines in `taxi_game.dart`
2. Adjust speed control in `player_vehicle._updateAutopilotMovement()`
3. Tune waypoint segments in `pathfinding_system.dart`

---

## Testing Checklist

### Visual Tests (Manual)
- [ ] Traffic vehicles appear and move smoothly
- [ ] Player collision with traffic triggers game over
- [ ] Pickup zones visible with pulsing
- [ ] Dropoff zones change color when active
- [ ] Player picks up passenger automatically
- [ ] Player delivers passenger at dropoff
- [ ] Level complete overlay appears
- [ ] Level failed overlay appears

### Functional Tests
- [ ] Traffic spawns at correct intervals
- [ ] Different vehicle types appear
- [ ] Collision detection accurate (not too harsh)
- [ ] Pickup detection radius feels right
- [ ] Dropoff only works with passenger
- [ ] All passengers must be delivered to win
- [ ] Crash stops the game

### Performance Tests
- [ ] 60 FPS with 10+ traffic vehicles
- [ ] No memory leaks (vehicles cleanup)
- [ ] Smooth camera following
- [ ] No stuttering on spawns

### Autopilot Tests (if enabled)
- [ ] Player navigates to pickup smoothly
- [ ] Player navigates to dropoff after pickup
- [ ] Hold makes player go faster
- [ ] Release makes player go slower
- [ ] Navigation stops at destination

---

**Architecture Version:** 1.0
**Last Updated:** 2025-11-22
**Status:** Implementation Complete, Awaiting Testing
