# Quick Reference Guide

## Project Overview
**Taxi Game** - A Flutter implementation of "Pick Me Up 3D" taxi game
- **Status:** Phase 1 Complete ✅
- **Language:** Dart
- **Framework:** Flutter + Flame
- **Platforms:** iOS, Android, Web, Desktop

## Directory Structure
```
taxiGame/
├── notes/                  # All planning and documentation
├── specification.md        # Original game specification
├── taxi_game/              # Flutter project
│   ├── lib/               # Source code
│   └── assets/            # Game assets (empty, using placeholders)
└── README.md              # This overview
```

## Key Documents

### Planning & Architecture
1. **notes/00-implementation-overview.md** - Start here for project overview
2. **notes/01-asset-requirements.md** - All assets needed (visual + audio)
3. **notes/02-phase-planning.md** - 12-week development roadmap
4. **notes/03-technical-architecture.md** - Technical design details
5. **notes/04-progress-log.md** - Development history and decisions
6. **notes/05-phase-1-summary.md** - Phase 1 completion summary
7. **notes/06-visual-guide.md** - Visual implementation guide

### Quick Access
- **Game Spec:** `specification.md` (31KB, comprehensive game design)
- **Project README:** `README.md` (high-level overview)
- **Game README:** `taxi_game/README.md` (how to run)

## File Count
- **Documentation:** 9 markdown files (~40,000 words)
- **Code Files:** 13 Dart files (~500+ lines)
- **Config Files:** 5 files (pubspec, README, .gitignore, etc.)
- **Total:** 27 files committed

## Running the Game

### Prerequisites
```bash
flutter --version  # Verify Flutter installed (3.0+)
```

### Commands
```bash
cd taxi_game
flutter pub get    # Install dependencies
flutter run        # Run on connected device/emulator
flutter build apk  # Build Android APK
```

### Expected Behavior
1. Main menu with yellow PLAY button
2. Tap PLAY → Game screen loads
3. Yellow taxi on gray road
4. Sky gradient background
5. Tap and hold → taxi moves up
6. Release → taxi stops

## Code Structure

### Core Game (`lib/game/`)
- `taxi_game.dart` - Main game class (Flame)
- `components/` - Game entities (player, road, background)
- `systems/` - Game systems (input, collision)
- `levels/` - Level data structures

### Services (`lib/services/`)
- `game_state_service.dart` - Global state management
- `storage_service.dart` - Save/load functionality
- `audio_service.dart` - Sound system (placeholder)

### UI (`lib/ui/`)
- `screens/` - Main menu, game screen
- `widgets/` - Reusable UI components
- `overlays/` - In-game overlays (HUD, pause, etc.)

### Models (`lib/models/`)
- `save_data.dart` - Player progress data structure

## Dependencies (pubspec.yaml)
```yaml
flame: ^1.11.0              # Game engine
flame_audio: ^2.1.0         # Audio (not yet used)
flutter_svg: ^2.0.9         # SVG rendering (future)
provider: ^6.1.1            # State management
shared_preferences: ^2.2.2  # Save data
path_provider: ^2.1.1       # File paths
vector_math: ^2.1.4         # Math utilities
```

## Asset Status

### Current (Placeholders)
- ✅ Vehicles: Geometric shapes (Canvas)
- ✅ Roads: Canvas drawing
- ✅ Background: Gradients + simple shapes
- ✅ UI: Material Icons
- ✅ Audio: Silent (game works without)

### Needed Later
- ⏳ Vehicle sprites (8-12 designs)
- ⏳ Sound effects (12+ files)
- ⏳ Music tracks (2-3 files)
- ⏳ Environment art
- ⏳ Particle effects

## Development Phases

### ✅ Phase 1: Project Setup (Complete)
- All infrastructure and documentation

### ⏳ Phase 2: Core Gameplay (Next)
- Collision detection
- Traffic AI
- Pickup/dropoff system
- First playable level

### Future Phases
- Phase 3: Visual elements
- Phase 4: Game systems
- Phase 5: UI & menus
- Phase 6: Content creation
- Phase 7: Polish & testing

## Common Tasks

### Adding a New Component
1. Create file in `lib/game/components/`
2. Extend `PositionComponent` or `SpriteComponent`
3. Implement `onLoad()` and `update()`
4. Add to game in `taxi_game.dart`

### Adding a New Screen
1. Create file in `lib/ui/screens/`
2. Extend `StatelessWidget` or `StatefulWidget`
3. Add navigation in previous screen
4. Use Provider to access game state

### Adding a New Level
1. Create JSON file in `assets/data/levels/`
2. Define pickups, dropoffs, traffic patterns
3. Load with `level_loader.dart` (to be implemented)

## Testing

### Run Tests
```bash
flutter test
```

### Test on Device
```bash
flutter devices              # List devices
flutter run -d <device-id>   # Run on specific device
```

## Git Workflow
```bash
git status                   # Check current changes
git add .                    # Stage all changes
git commit -m "message"      # Commit with message
git push origin <branch>     # Push to GitHub
```

## Useful Links
- Flutter Docs: https://docs.flutter.dev/
- Flame Docs: https://docs.flame-engine.org/
- Dart Docs: https://dart.dev/guides
- Game Spec: https://github.com/wjdavis5/taxiGame/blob/main/specification.md

## Key Contacts
- Repository: https://github.com/wjdavis5/taxiGame
- Owner: @wjdavis5

## Quick Stats
- **Lines of Code:** ~500+
- **Documentation:** ~40,000 words
- **Development Time (Phase 1):** 1 session
- **Estimated Total Time:** 8-12 weeks
- **Target Release:** TBD

## Current Blockers
**None!** ✅
- All infrastructure complete
- No dependencies blocking progress
- Ready for gameplay development

## Next Actions
1. Review Phase 2 planning (`notes/02-phase-planning.md`)
2. Implement collision detection
3. Create traffic vehicle component
4. Test first gameplay loop
5. Iterate based on playtesting

## Tips
- Read documentation in order (00-06)
- Start with `notes/00-implementation-overview.md`
- Check `notes/04-progress-log.md` for decisions made
- See `notes/06-visual-guide.md` for current visuals
- All code is well-commented

## Success Criteria Met ✅
- [x] Complete project structure
- [x] Comprehensive documentation
- [x] Working game foundation
- [x] No blocking dependencies
- [x] Clear roadmap
- [x] Cross-platform setup
- [x] Service layer complete
- [x] UI framework in place

---

**Status:** Ready for Phase 2 development
**Last Updated:** 2025-11-22
**Phase 1 Complete:** ✅

