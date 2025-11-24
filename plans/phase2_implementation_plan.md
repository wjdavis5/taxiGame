# Phase 2 Implementation Plan - Core Gameplay
**Created:** 2025-11-22
**Status:** Approved - Ready for Implementation
**Goal:** Transform foundation into fully playable game with complete gameplay loop

## Executive Summary

Phase 1 delivered a solid foundation with ~500 lines of well-architected Flutter/Flame code. The project is ~15% complete overall. Phase 2 will add the critical missing features that make this an actual game: traffic AI, pickup/dropoff mechanics, pathfinding, and a complete game loop.

**Timeline:** 4-6 weeks
**Outcome:** Minimum Viable Game (MVP) ready for user testing

---

## Current State Analysis

### ✅ What Works
- Flutter/Flame project structure complete
- Player taxi renders and moves on tap-hold-release
- Basic visual elements (road, buildings, sky gradient)
- Service layer (GameState, Storage, Audio placeholder)
- UI framework (menu, game screen, HUD)
- Save/load foundation (untested)
- Input system fully functional

### ❌ Critical Gaps
- **NO traffic vehicles** → No challenge or obstacles
- **NO pickup/dropoff** → No objectives or win condition
- **NO pathfinding** → Player only moves vertically, no navigation
- **NO complete game loop** → Can't win, lose, or progress to next level
- **NO actual level content** → Only 1 test level with no features
- **NO audio assets** → Service exists but silent
- **NO visual polish** → No particles, animations, or juice

### 🎯 Priority
**Phase 2 is the critical path.** Without traffic and pickups, this is a tech demo, not a game.

---

## Implementation Roadmap

### Week 1: Traffic System (Days 1-7)

#### Day 1-2: TrafficVehicle Component
**Files to Create:**
- `lib/game/components/traffic_vehicle.dart`
- `lib/game/components/traffic_spawner.dart`
- `lib/models/traffic_pattern.dart`

**Implementation:**
```dart
class TrafficVehicle extends SpriteComponent with CollisionCallbacks {
  final double speed;
  final List<Vector2> path;
  int currentWaypoint = 0;

  // Auto-follow path waypoints
  // Detect collision with player
  // Remove when off-screen
}
```

**Tasks:**
- [ ] Create TrafficVehicle component extending SpriteComponent
- [ ] Implement path following with waypoint system
- [ ] Add collision detection with player vehicle
- [ ] Create 3 vehicle types (sedan, truck, sports car) with different speeds
- [ ] Test movement and collision response

#### Day 3-4: Traffic Spawning System
**Implementation:**
```dart
class TrafficSpawner extends Component {
  final TrafficPattern pattern;
  Timer spawnTimer;

  // Spawn vehicles at intervals
  // Follow defined traffic patterns
  // Manage vehicle lifecycle
}
```

**Tasks:**
- [ ] Create TrafficSpawner component
- [ ] Implement configurable spawn intervals
- [ ] Create 3-5 traffic patterns (steady, burst, mixed)
- [ ] Add vehicle pooling for performance
- [ ] Test with multiple simultaneous vehicles

#### Day 5: Collision Integration
**Files to Modify:**
- `lib/game/components/player_vehicle.dart`
- `lib/game/taxi_game.dart`
- `lib/services/game_state_service.dart`

**Tasks:**
- [ ] Connect collision detection to game over logic
- [ ] Add crash animation/effect (basic)
- [ ] Show game over overlay on collision
- [ ] Test crash → restart flow
- [ ] Tune hitboxes for fairness

#### Day 6-7: Testing & Balancing
**Tasks:**
- [ ] Test traffic with various speeds and densities
- [ ] Balance difficulty (timing windows)
- [ ] Optimize performance (60 FPS with 10+ vehicles)
- [ ] Fix any collision detection bugs
- [ ] Document traffic system in code

**Week 1 Deliverable:** Working traffic system with AI vehicles that spawn, move, and collide with player

---

### Week 2: Pickup/Dropoff System (Days 8-14)

#### Day 8-9: Passenger Component
**Files to Create:**
- `lib/game/components/passenger.dart`
- `lib/game/components/pickup_zone.dart`
- `lib/game/components/dropoff_zone.dart`
- `lib/models/passenger_data.dart`

**Implementation:**
```dart
class Passenger {
  final Vector2 pickupLocation;
  final Vector2 dropoffLocation;
  final int reward;
  bool pickedUp = false;

  // Passenger state management
}

class PickupZone extends CircleComponent {
  final Passenger passenger;

  // Visual marker (glowing circle)
  // Proximity detection
  // Trigger pickup on player entry
}
```

**Tasks:**
- [ ] Create Passenger model with pickup/dropoff locations
- [ ] Create PickupZone component with visual marker
- [ ] Create DropoffZone component with visual marker
- [ ] Implement proximity detection
- [ ] Test zone visibility and detection radius

#### Day 10-11: Pickup/Dropoff Mechanics
**Files to Modify:**
- `lib/game/components/player_vehicle.dart`
- `lib/game/taxi_game.dart`
- `lib/services/game_state_service.dart`

**Tasks:**
- [ ] Implement automatic pickup on zone entry
- [ ] Update player vehicle to show "has passenger" state
- [ ] Implement dropoff detection at destination
- [ ] Award coins on successful dropoff
- [ ] Add visual feedback for pickup/dropoff events

#### Day 12-13: Level Completion Logic
**Files to Modify:**
- `lib/game/taxi_game.dart`
- `lib/ui/overlays/level_complete_overlay.dart`
- `lib/models/level.dart`

**Tasks:**
- [ ] Connect dropoff to level complete trigger
- [ ] Show level complete overlay with stats
- [ ] Calculate score (time bonus, perfect run, etc.)
- [ ] Award coins and save progress
- [ ] Implement "Next Level" button functionality

#### Day 14: Testing
**Tasks:**
- [ ] Test full pickup → dropoff flow
- [ ] Test with traffic obstacles
- [ ] Verify coin rewards work correctly
- [ ] Test edge cases (pickup while crashing, etc.)
- [ ] Balance pickup zone sizes and timing

**Week 2 Deliverable:** Complete pickup/dropoff system with level completion

---

### Week 3: Pathfinding & First Playable Level (Days 15-21)

#### Day 15-16: Waypoint System
**Files to Create:**
- `lib/game/systems/pathfinding_system.dart`
- `lib/models/waypoint.dart`

**Implementation:**
```dart
class PathfindingSystem {
  List<Vector2> currentPath;

  Vector2 getNextWaypoint();
  void followPath(PlayerVehicle player);
  bool hasReachedDestination();
}
```

**Tasks:**
- [ ] Create waypoint data structure
- [ ] Implement path following algorithm (simple)
- [ ] Make player vehicle auto-navigate along path
- [ ] Add player speed control (hold = faster)
- [ ] Test smooth path following

#### Day 17-18: Level Design - First Complete Level
**Files to Modify:**
- `lib/models/level.dart`
- Create: `assets/levels/level_001.json`

**Level 001 Design:**
- Straight road with 2 lanes
- Pickup 200m ahead
- Light traffic (3-4 vehicles)
- Dropoff 300m after pickup
- Tutorial hints in UI

**Tasks:**
- [ ] Design level layout (pickup, dropoff, traffic pattern)
- [ ] Create level JSON data structure
- [ ] Implement level loader from JSON
- [ ] Add level to game progression
- [ ] Test complete gameplay loop

#### Day 19: Game Loop Integration
**Files to Modify:**
- `lib/services/game_state_service.dart`
- `lib/ui/screens/main_menu_screen.dart`
- `lib/ui/overlays/level_complete_overlay.dart`

**Tasks:**
- [ ] Connect "Next Level" button to load next level
- [ ] Implement level unlock progression
- [ ] Save progress after level complete
- [ ] Load last unlocked level on restart
- [ ] Test level progression (1 → 2 → 3)

#### Day 20-21: Testing & Polish
**Tasks:**
- [ ] Playtest entire flow: Menu → Play → Win → Next
- [ ] Test losing and retrying
- [ ] Verify save/load works correctly
- [ ] Balance first level difficulty (should be easy)
- [ ] Fix all critical bugs
- [ ] Document gameplay systems

**Week 3 Deliverable:** First fully playable level with complete game loop

---

### Week 4: Content & Integration (Days 22-28)

#### Day 22-24: Additional Levels
**Files to Create:**
- `assets/levels/level_002.json` through `level_010.json`

**Level Progression:**
1. **Level 1:** Tutorial - straight road, light traffic
2. **Level 2:** Introduce curves - gentle turns
3. **Level 3:** Increase traffic density
4. **Level 4:** Multiple pickups (2 passengers)
5. **Level 5:** Faster traffic
6. **Level 6:** Narrow lanes
7. **Level 7:** Time pressure
8. **Level 8:** Complex traffic patterns
9. **Level 9:** Long distance
10. **Level 10:** Boss level - all mechanics

**Tasks:**
- [ ] Design 9 additional levels
- [ ] Create JSON data for each level
- [ ] Test each level individually
- [ ] Verify difficulty curve is smooth
- [ ] Balance rewards (coins per level)

#### Day 25-26: Currency & Progression
**Files to Modify:**
- `lib/services/game_state_service.dart`
- `lib/ui/screens/main_menu_screen.dart`
- `lib/ui/overlays/hud_overlay.dart`

**Tasks:**
- [ ] Display coin count in HUD during gameplay
- [ ] Animate coin collection on dropoff
- [ ] Update main menu with total coins
- [ ] Show level unlock status in menu
- [ ] Add "locked level" indicators
- [ ] Test coin earning and persistence

#### Day 27: Save System Testing
**Files to Modify:**
- `lib/services/storage_service.dart`
- `lib/models/save_data.dart`

**Tasks:**
- [ ] Test save after each level
- [ ] Test load on app restart
- [ ] Verify progress persists (levels, coins)
- [ ] Handle save corruption gracefully
- [ ] Test on multiple platforms (iOS, Android, Web)
- [ ] Add save/load error handling

#### Day 28: Final Integration & Bug Fixing
**Tasks:**
- [ ] Fix all critical bugs from testing
- [ ] Optimize performance (target 60 FPS)
- [ ] Test full gameplay flow end-to-end
- [ ] Verify all levels are completable
- [ ] Polish UI transitions
- [ ] Update documentation

**Week 4 Deliverable:** MVP with 10 playable levels and complete progression

---

## Success Criteria

### Minimum Requirements (Must Have)
- ✅ Traffic AI with 3+ vehicle types
- ✅ Pickup/dropoff mechanics working
- ✅ Player auto-navigation (pathfinding)
- ✅ 10+ playable levels
- ✅ Complete game loop (play → win → next)
- ✅ Collision detection (crash = game over)
- ✅ Coin rewards and progression
- ✅ Save/load working
- ✅ 60 FPS performance

### Quality Goals (Should Have)
- ✅ Smooth difficulty curve
- ✅ Fair collision hitboxes
- ✅ Responsive controls
- ✅ Clear visual feedback
- ✅ No critical bugs
- ✅ Works on iOS and Android

### Stretch Goals (Nice to Have)
- 🎯 20+ levels
- 🎯 Basic particle effects (crash smoke)
- 🎯 Sound effects (placeholder)
- 🎯 Tutorial overlay
- 🎯 Multiple traffic patterns per level

---

## Technical Specifications

### Traffic System Architecture
```
TrafficSpawner (manages lifecycle)
  └─> TrafficVehicle[] (follows paths)
      └─> CollisionCallbacks (detects player)
          └─> GameStateService.gameOver()
```

### Pickup/Dropoff Flow
```
Level loads → PickupZone spawns → Player enters → Passenger pickedUp
  → DropoffZone appears → Player enters → Level complete
  → Award coins → Save progress → Next level
```

### Data Models
```dart
// Level structure
{
  "id": "level_001",
  "difficulty": 1,
  "pickupLocation": {"x": 0, "y": -200},
  "dropoffLocation": {"x": 0, "y": -500},
  "trafficPattern": "light_steady",
  "coinReward": 50
}
```

### Performance Targets
- **FPS:** 60 (locked)
- **Max Traffic:** 15 simultaneous vehicles
- **Load Time:** < 1 second per level
- **Memory:** < 100 MB on mobile

---

## Risk Assessment & Mitigation

### Risk 1: Collision Detection Too Hard/Easy
**Mitigation:**
- Use forgiving hitboxes (80% of sprite size)
- Extensive playtesting
- Adjustable difficulty setting

### Risk 2: Pathfinding Too Complex
**Mitigation:**
- Start with simple waypoint system (not A*)
- Use straight paths for early levels
- Add curves gradually

### Risk 3: Performance Issues with Traffic
**Mitigation:**
- Implement object pooling early
- Cull off-screen vehicles
- Profile regularly
- Limit max simultaneous vehicles

### Risk 4: Level Design Takes Longer Than Expected
**Mitigation:**
- Start with 5 levels minimum
- Use traffic patterns for variety
- Can add more levels in Phase 3

### Risk 5: Save System Bugs
**Mitigation:**
- Test early and often
- Add comprehensive error handling
- Include save file versioning
- Test on all platforms

---

## Testing Strategy

### Unit Testing
- Collision detection accuracy
- Pathfinding waypoint navigation
- Save/load data integrity
- Coin calculation logic

### Integration Testing
- Full gameplay loop
- Level transitions
- Save persistence across restarts
- Traffic spawning under load

### Playtesting
- Each level completable
- Difficulty feels fair
- Controls responsive
- No softlocks or crashes

### Performance Testing
- 60 FPS with max traffic
- Memory usage stable
- Load times acceptable
- Battery usage reasonable (mobile)

---

## Deliverables Summary

### End of Week 1
- Traffic system with AI vehicles
- Collision detection working
- 3+ traffic vehicle types

### End of Week 2
- Pickup/dropoff mechanics complete
- Level completion logic
- Coin rewards system

### End of Week 3
- First fully playable level
- Pathfinding/auto-navigation
- Complete game loop

### End of Week 4
- 10 playable levels
- Save/load tested and working
- MVP ready for user testing
- Documentation updated

---

## Next Steps After Phase 2

Once MVP is complete, proceed to:

### Phase 3: Visual Polish (Weeks 5-6)
- Particle effects (smoke, sparkles, explosions)
- Vehicle animations (wheels, bounce)
- Screen shake and camera effects
- Better graphics (replace geometric shapes)

### Phase 4: Audio & Content (Weeks 7-8)
- Sound effects for all events
- Background music
- 20-30 additional levels
- Environment variations

### Phase 5: Advanced Features (Weeks 9-10)
- Vehicle unlocks and garage
- Settings screen
- Daily rewards
- Achievements

### Phase 6: Launch Prep (Weeks 11-12)
- Cross-platform testing
- Performance optimization
- Bug fixing
- App store submission

---

## Resources Needed

### Development
- Flutter/Dart IDE (VS Code or Android Studio)
- Device testing (iOS + Android)
- Git for version control

### Assets (Placeholder OK for Phase 2)
- 3-5 vehicle sprites (can use simple shapes)
- Pickup/dropoff zone graphics (circles OK)
- Sound effects (can be silent initially)

### Testing
- 2-3 playtesters for feedback
- Performance profiling tools
- Multiple test devices

---

## Conclusion

Phase 2 transforms the solid foundation from Phase 1 into a fully playable game. By focusing on the critical path (traffic, pickups, pathfinding), we'll have an MVP that demonstrates the core gameplay loop and is ready for user feedback.

**Timeline:** 4-6 weeks
**Current Completion:** 15%
**After Phase 2:** 50% complete
**MVP Status:** ✅ Ready for testing

The architecture is sound, the plan is detailed, and the path forward is clear. Let's build this game! 🚕

---

**Document Version:** 1.0
**Last Updated:** 2025-11-22
**Next Review:** After Week 2 completion
