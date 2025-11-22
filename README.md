# Taxi Game Project

A cross-platform 3D taxi game inspired by "Pick Me Up 3D", built with Flutter.

## Project Structure

```
taxiGame/
├── notes/                      # Development notes and planning
│   ├── 00-implementation-overview.md
│   ├── 01-asset-requirements.md
│   ├── 02-phase-planning.md
│   ├── 03-technical-architecture.md
│   └── 04-progress-log.md
├── specification.md            # Complete game specification
├── taxi_game/                  # Flutter game project
│   ├── lib/                    # Source code
│   ├── assets/                 # Game assets
│   ├── test/                   # Tests
│   └── pubspec.yaml           # Dependencies
└── README.md                   # This file
```

## Documentation

All planning and technical documentation is in the `notes/` folder:

- **00-implementation-overview.md**: Project goals, technology stack, and development approach
- **01-asset-requirements.md**: Complete list of visual and audio assets needed
- **02-phase-planning.md**: 12-week development roadmap with detailed tasks
- **03-technical-architecture.md**: Technical design and system architecture
- **04-progress-log.md**: Development progress tracking

## Game Overview

Pick Me Up 3D is a casual taxi simulation game featuring:
- **Single-button control**: Tap and hold to accelerate, release to stop
- **Automatic pathfinding**: Vehicle navigates automatically to destinations
- **Timing-based gameplay**: Success depends on when to move, not how to steer
- **Progressive difficulty**: 300+ planned levels
- **Vehicle collection**: Unlockable taxi vehicles
- **Cross-platform**: iOS, Android, Web, Desktop support

## Current Status

**Phase 1: Project Setup & Core Architecture** ✅
- Project structure created
- Core game files implemented
- Basic game loop established
- Service layer implemented
- UI screens created
- Planning documentation complete

**Next Phase: Core Gameplay Mechanics**
- Implement full tap-hold-release control
- Add collision detection
- Create pickup/dropoff system
- Build first playable level

## Technology Stack

- **Framework**: Flutter 3.x
- **Game Engine**: Flame 1.11+
- **Language**: Dart
- **State Management**: Provider
- **Storage**: SharedPreferences

## Getting Started

### Prerequisites
- Flutter SDK 3.0 or higher
- Dart SDK 3.0 or higher

### Installation

1. Navigate to the game project:
```bash
cd taxi_game
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the game:
```bash
flutter run
```

## Asset Strategy

Currently using placeholder assets:
- Simple geometric shapes for vehicles
- Canvas-drawn roads and environment
- Flutter Material Icons for UI
- No audio (silent for now)

See `notes/01-asset-requirements.md` for complete asset specifications.

### Assets Needed (Future)
- **Visual**: 8-12 vehicle designs, environment sprites, particle effects
- **Audio**: 12+ sound effects, 2-3 music tracks

## Development Roadmap

1. ✅ **Phase 1**: Project Setup (Complete)
2. ⏳ **Phase 2**: Core Gameplay Mechanics (In Progress)
3. **Phase 3**: Visual Elements
4. **Phase 4**: Game Systems
5. **Phase 5**: UI & Menus
6. **Phase 6**: Content Creation
7. **Phase 7**: Polish & Testing

Full roadmap in `notes/02-phase-planning.md`

## Key Features Implemented

- [x] Project structure and organization
- [x] Flutter + Flame game engine setup
- [x] Main menu screen
- [x] Game screen with HUD overlay
- [x] Basic game loop
- [x] Player vehicle component
- [x] Input system (tap/hold controls)
- [x] Road and background rendering
- [x] Service layer (storage, audio, game state)
- [x] State management with Provider
- [x] Save/load functionality structure

## Key Features In Progress

- [ ] Full collision detection
- [ ] Pickup/dropoff mechanics
- [ ] Traffic AI system
- [ ] Level loading system
- [ ] Particle effects

## Contributing

This is a learning and development project. Contributions and feedback are welcome!

## License

Educational project inspired by "Pick Me Up 3D" by Voodoo.

## Contact

Project repository: https://github.com/wjdavis5/taxiGame
