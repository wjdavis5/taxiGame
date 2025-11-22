# Taxi Game

A cross-platform taxi game inspired by "Pick Me Up 3D", built with Flutter and Flame.

## Game Overview

Pick Me Up 3D is a casual taxi simulation game featuring:
- **Single-button control**: Tap and hold to accelerate, release to stop
- **Automatic pathfinding**: Vehicle navigates automatically to destinations
- **Timing-based gameplay**: Success depends on when to move, not how to steer
- **Progressive difficulty**: 300+ levels with increasing challenge
- **Vehicle collection**: Unlock and customize various taxi vehicles

## Features

- 🎮 Simple, accessible gameplay (one-handed control)
- 🚗 Multiple unlockable vehicles
- 🎨 Colorful, cartoonish graphics
- 🎵 Sound effects and background music
- 📱 Cross-platform (iOS, Android, Web, Desktop)
- 💾 Progress saving and settings persistence
- 🏆 Level progression system

## Technical Stack

- **Framework**: Flutter 3.x
- **Game Engine**: Flame 1.11+
- **Language**: Dart
- **State Management**: Provider
- **Storage**: SharedPreferences

## Project Structure

```
taxi_game/
├── lib/
│   ├── main.dart                  # Entry point
│   ├── game/                      # Core game logic
│   │   ├── taxi_game.dart         # Main game class
│   │   ├── components/            # Game entities
│   │   ├── systems/               # Game systems
│   │   └── levels/                # Level definitions
│   ├── ui/                        # UI screens & widgets
│   ├── models/                    # Data models
│   ├── services/                  # Services
│   └── utils/                     # Utilities
├── assets/                        # Game assets
└── test/                          # Tests
```

## Getting Started

### Prerequisites

- Flutter SDK 3.0 or higher
- Dart SDK 3.0 or higher

### Installation

1. Clone the repository
```bash
git clone https://github.com/wjdavis5/taxiGame.git
cd taxiGame/taxi_game
```

2. Install dependencies
```bash
flutter pub get
```

3. Run the game
```bash
flutter run
```

### Building for Production

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release

# Desktop (Windows/Mac/Linux)
flutter build windows --release
flutter build macos --release
flutter build linux --release
```

## Development

### Running Tests

```bash
flutter test
```

### Code Style

This project follows the official Dart style guide. Use `flutter analyze` to check for issues:

```bash
flutter analyze
```

## Game Controls

- **Tap and Hold**: Accelerate forward
- **Release**: Stop immediately
- **Pause Button**: Pause the game

## Asset Requirements

See `notes/01-asset-requirements.md` for detailed asset specifications.

Current implementation uses:
- Simple geometric shapes for vehicles
- Canvas-drawn roads and environment
- Placeholder or no audio

Future enhancements will include:
- Professional vehicle sprites
- Detailed environment art
- Sound effects and music
- Particle effects

## Roadmap

- [x] Phase 1: Project setup and planning
- [ ] Phase 2: Core gameplay mechanics
- [ ] Phase 3: Visual elements
- [ ] Phase 4: Game systems
- [ ] Phase 5: UI & menus
- [ ] Phase 6: Content creation
- [ ] Phase 7: Polish & testing

See `notes/02-phase-planning.md` for detailed roadmap.

## Documentation

Detailed planning and technical documentation is available in the `notes/` folder:
- `00-implementation-overview.md` - Project overview
- `01-asset-requirements.md` - Asset specifications
- `02-phase-planning.md` - Development roadmap
- `03-technical-architecture.md` - System architecture
- `04-progress-log.md` - Development log

## License

This project is for educational purposes. Game design inspired by "Pick Me Up 3D".

## Contributing

This is a learning project. Contributions and suggestions are welcome!

## Acknowledgments

- Inspired by "Pick Me Up 3D" by Voodoo
- Built with Flutter and Flame game engine
- See `specification.md` for detailed game design specifications
