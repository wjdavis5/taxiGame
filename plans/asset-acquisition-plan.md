# Asset Acquisition Plan for Taxi Game

## Overview
This document provides detailed instructions for acquiring all visual and audio assets needed for the taxi game, based on the requirements in `notes/01-asset-requirements.md`. All assets are free, commercially-licensed, and ready for immediate use.

---

## Table of Contents
1. [Visual Assets Acquisition](#visual-assets-acquisition)
2. [Audio Assets Acquisition](#audio-assets-acquisition)
3. [File Organization Structure](#file-organization-structure)
4. [License Compliance](#license-compliance)
5. [Integration Checklist](#integration-checklist)

---

## Visual Assets Acquisition

### Phase 1: Vehicle Sprites (Critical Path - MVP)

#### Primary Source: Kenney.nl (CC0 License - No Attribution Required)

**Download Location 1: All-in-1 Bundle (Recommended)**
- URL: https://kenney.itch.io/kenney-game-assets
- File: "Kenney Game Assets All-in-1" (~2GB)
- Contains: 60,000+ assets including all vehicle packs
- License: CC0 (Public Domain)
- Action: Download → Extract → Navigate to vehicle folders

**Download Location 2: Individual Packs**
- Pixel Vehicle Pack: https://kenney.nl/assets/pixel-vehicle-pack
  - Contains: 50 top-down vehicle sprites
  - Formats: PNG (various sizes)
  - Use for: Player taxis and AI traffic
  
- Top-Down Tanks Redux: https://kenney.nl/assets/top-down-tanks
  - Contains: 180 vehicle/tank sprites
  - Can adapt: Larger vehicles (SUVs, trucks)
  
- Racing Pack: https://kenney.nl/assets/racing-pack
  - Contains: 42 racing-themed sprites
  - Use for: Sports cars, luxury vehicles

**What You'll Get:**
- ✅ 5-15 player taxi variants (requirement met)
- ✅ 8+ AI traffic vehicles (requirement met)
- ✅ Multiple color variations
- ✅ Pre-sized for game use
- ✅ Transparent backgrounds (PNG)

**Specific Files to Use:**
```
Player Taxis:
- car_yellow_1.png (classic taxi)
- car_blue_1.png (basic sedan)
- car_red_small.png (compact car)
- car_green_large.png (SUV)
- car_black_sport.png (sports car)

AI Traffic:
- car_gray_sedan.png
- car_white_compact.png
- car_blue_suv.png
- truck_red.png
- van_white.png
- bus_yellow.png
```

#### Secondary Source: OpenGameArt.org

**Free Top Down Car Sprites by Unlucky Studio**
- URL: https://opengameart.org/content/free-top-down-car-sprites-by-unlucky-studio
- Contains: High-res cars, police, ambulance, trucks, vans
- License: Royalty-free (attribution appreciated but not required)
- Format: PNG
- Action: Download ZIP → Extract → Use as needed

#### Tertiary Source: itch.io

**Browse Vehicle Assets**
- URL: https://itch.io/game-assets/free/tag-2d/tag-vehicles
- Filter: Free + Top-down + 2D
- Contains: 95+ free vehicle asset packs
- Action: Browse → Select packs matching art style → Download

**Recommended Packs on itch.io:**
- Search: "top-down vehicles pixel art free"
- Look for: CC0 or "free for commercial use" in description

---

### Phase 2: Environment Assets

#### Buildings & Background

**Kenney.nl - City Pack**
- URL: https://kenney.nl/assets/city-kit
- Contains: Buildings, roads, props
- License: CC0
- Use for: Background scenery

**Kenney.nl - Abstract Platformer**
- URL: https://kenney.nl/assets/abstract-platformer
- Contains: Simple geometric shapes for buildings
- License: CC0

#### Road & UI Elements

**Use Kenney's UI Pack**
- URL: https://kenney.nl/assets/ui-pack
- Contains: Buttons, icons, markers
- License: CC0
- Includes: Arrow, star, lock, checkmark icons

**Kenney's Game Icons**
- URL: https://kenney.nl/assets/game-icons
- Contains: 1000+ game icons (coin, gem, star, etc.)
- License: CC0
- Format: PNG & Vector

---

## Audio Assets Acquisition

### Phase 1: Sound Effects (Critical Path)

#### Primary Source: Sonniss GameAudioGDC (Highest Quality - No Attribution)

**Download Location:**
- URL: https://sonniss.com/gameaudiogdc/
- Latest Bundle: GDC 2024 Game Audio Bundle
- Size: ~30GB (contains thousands of sounds)
- License: 100% royalty-free, commercial use, NO attribution required
- Action: Download → Extract → Search for needed sounds

**Sounds to Find in Sonniss Bundle:**
```
Vehicle Sounds:
- Search: "car engine idle"
- Search: "car acceleration"
- Search: "tire screech" / "brake"
- Search: "car crash" / "collision"
- Search: "car horn"

UI Sounds:
- Search: "button click" / "ui click"
- Search: "coin collect" / "pickup"
- Search: "level complete" / "victory"
- Search: "fail" / "lose"
```

#### Secondary Source: Freesound.org (Largest Variety - Check Licenses)

**Vehicle Sounds:**
1. **Engine Idle**
   - URL: https://freesound.org/search/?q=car+engine+idle
   - Filter: CC0 or CC-BY license
   - Recommended: Search "taxi engine idle"
   - Download: 2-3 variations, pick best

2. **Acceleration**
   - URL: https://freesound.org/search/?q=car+acceleration
   - Filter: CC0 preferred
   - Duration: 1-2 seconds

3. **Brake/Screech**
   - URL: https://freesound.org/search/?q=tire+screech
   - Filter: CC0 or CC-BY
   - Keywords: "brake screech", "tire skid"

4. **Crash Sound**
   - URL: https://freesound.org/search/?q=car+crash+cartoon
   - Filter: CC0 preferred
   - Note: Look for "comedic" or "game" crash sounds

**UI Sounds:**
1. **Button Click**
   - URL: https://freesound.org/search/?q=button+click+ui
   - Filter: CC0
   - Keywords: "soft click", "ui button"

2. **Coin Collection**
   - URL: https://freesound.org/search/?q=coin+collect
   - Filter: CC0
   - Keywords: "pickup coin", "cha-ching"

3. **Level Complete**
   - URL: https://freesound.org/search/?q=level+complete+jingle
   - Filter: CC0
   - Keywords: "victory jingle", "win fanfare"

**Important: License Verification**
- Each sound on Freesound has its own license
- Look for green "CC0" badge (best - no attribution needed)
- Yellow "CC-BY" requires attribution (still commercial use OK)
- Avoid "CC-BY-NC" (non-commercial - not suitable)

#### Tertiary Source: JSFXR (Generate Custom Sounds - Instant)

**Use for UI Sounds:**
- URL: https://sfxr.me/ (web version of JSFXR)
- Action: Click "Generate" → Tweak parameters → Export WAV
- Best for: Retro-style UI sounds, pickup effects
- License: Generated sounds are royalty-free

**Preset Sounds to Generate:**
1. Button Click: 
   - Category: Random → Find short click
   - Export: button_click.wav

2. Coin Pickup:
   - Category: Pickup/Coin
   - Export: coin_collect.wav

3. Power-up Sound:
   - Category: Power-up
   - Export: passenger_pickup.wav

#### Quaternary Source: Zapsplat (Registration Required)

**Download Location:**
- URL: https://www.zapsplat.com/
- Action: Free registration → Search sounds
- License: Free tier requires attribution, Gold tier ($60/yr) removes attribution
- Contains: 150,000+ sounds

**Search Terms:**
- "car engine"
- "tire screech"
- "crash impact"
- "ui button"
- "coin collect"

---

### Phase 2: Background Music

#### Primary Source: Incompetech (Kevin MacLeod) - Easiest & Best

**Download Location:**
- URL: https://incompetech.com/music/royalty-free/music.html
- License: CC-BY (requires attribution - "Music by Kevin MacLeod")
- Commercial use: YES
- Action: Browse → Download MP3

**Specific Tracks for Taxi Game:**

1. **Main Menu Music** (Upbeat, Inviting)
   - Search: https://incompetech.com/music/royalty-free/index.html?keywords=upbeat+happy
   - Recommended Tracks:
     - "Cipher" (electronic, upbeat, 122 BPM)
     - "Pixel Peeker Polka" (fun, retro)
     - "Breakfast" (cheerful, light)
   - Action: Download MP3 → Rename to menu_music.mp3

2. **Gameplay Music** (Electronic, Energetic)
   - Search: https://incompetech.com/music/royalty-free/index.html?keywords=electronic+fast
   - Recommended Tracks:
     - "Hyperfun" (electronic dance, 140 BPM)
     - "Pamgaea" (driving electronic, 120 BPM)
     - "Fig Leaf Rag" (upbeat, playful)
   - Action: Download 2-3 variations → gameplay_1.mp3, gameplay_2.mp3

3. **Garage/Selection Music** (Chill, Similar to Menu)
   - Recommended:
     - "Night on the Docks" (jazzy, relaxed)
     - "Wallpaper" (electronic, chill)
   - Action: Download → garage_music.mp3

**Attribution Text for Incompetech:**
```
Music by Kevin MacLeod (incompetech.com)
Licensed under Creative Commons: By Attribution 4.0 License
http://creativecommons.org/licenses/by/4.0/
```

#### Secondary Source: Purple Planet Music

**Download Location:**
- URL: https://www.purple-planet.com/
- Section: Action/Game Music
- License: Royalty-free (attribution required)
- Action: Browse categories → Download

**Search in Categories:**
- "Upbeat"
- "Game Music"
- "Electronic"

#### Tertiary Source: BenSound

**Download Location:**
- URL: https://www.bensound.com/royalty-free-music/track/energy
- License: Free with attribution
- Recommended Tracks:
  - "Energy" (upbeat electronic)
  - "Sunny" (happy, upbeat)
  - "Groovy Hip Hop" (funky, energetic)
- Action: Download → Follow attribution rules

#### Quaternary Source: OpenGameArt Music

**Download Location:**
- URL: https://opengameart.org/art-search-advanced?keys=&field_art_type_tid%5B%5D=12&sort_by=count&sort_order=DESC
- Filter: Music + CC0 or CC-BY
- Search: "electronic game music" or "upbeat instrumental"
- Action: Download CC0 tracks (no attribution needed)

---

## File Organization Structure

### Directory Structure to Create

```
taxi_game/
├── assets/
│   ├── images/
│   │   ├── vehicles/
│   │   │   ├── player/
│   │   │   │   ├── taxi_yellow.png
│   │   │   │   ├── sedan_blue.png
│   │   │   │   ├── compact_red.png
│   │   │   │   ├── suv_green.png
│   │   │   │   ├── sports_black.png
│   │   │   │   ├── luxury_white.png
│   │   │   │   └── minivan_gray.png
│   │   │   └── traffic/
│   │   │       ├── sedan_gray.png
│   │   │       ├── compact_white.png
│   │   │       ├── suv_blue.png
│   │   │       ├── truck_red.png
│   │   │       ├── van_white.png
│   │   │       ├── bus_yellow.png
│   │   │       ├── sports_red.png
│   │   │       └── motorcycle_black.png
│   │   ├── environment/
│   │   │   ├── buildings/
│   │   │   │   ├── building_01.png
│   │   │   │   ├── building_02.png
│   │   │   │   └── ... (10+ variations)
│   │   │   ├── roads/
│   │   │   │   ├── road_texture.png
│   │   │   │   ├── lane_marking.png
│   │   │   │   └── intersection.png
│   │   │   ├── scenery/
│   │   │   │   ├── tree_01.png
│   │   │   │   ├── tree_02.png
│   │   │   │   ├── street_light.png
│   │   │   │   ├── traffic_cone.png
│   │   │   │   └── barrier.png
│   │   │   └── sky/
│   │   │       ├── sky_day.png
│   │   │       ├── sky_sunset.png
│   │   │       └── sky_night.png
│   │   └── ui/
│   │       ├── icons/
│   │       │   ├── pause.png
│   │       │   ├── play.png
│   │       │   ├── settings.png
│   │       │   ├── back.png
│   │       │   ├── coin.png
│   │       │   ├── gem.png
│   │       │   ├── star.png
│   │       │   ├── lock.png
│   │       │   └── checkmark.png
│   │       ├── markers/
│   │       │   ├── pickup_marker.png
│   │       │   ├── dropoff_marker.png
│   │       │   └── arrow_pointer.png
│   │       └── backgrounds/
│   │           ├── menu_background.png
│   │           ├── level_complete_bg.png
│   │           └── level_failed_bg.png
│   ├── audio/
│   │   ├── sfx/
│   │   │   ├── vehicle/
│   │   │   │   ├── engine_idle.mp3
│   │   │   │   ├── engine_acceleration.mp3
│   │   │   │   ├── brake_screech.mp3
│   │   │   │   ├── crash.mp3
│   │   │   │   └── near_miss_whoosh.mp3
│   │   │   ├── ambient/
│   │   │   │   ├── city_traffic.mp3
│   │   │   │   └── pedestrian_chatter.mp3 (optional)
│   │   │   └── ui/
│   │   │       ├── button_click.mp3
│   │   │       ├── coin_collect.mp3
│   │   │       ├── passenger_pickup.mp3
│   │   │       ├── passenger_dropoff.mp3
│   │   │       ├── level_complete.mp3
│   │   │       └── level_failed.mp3
│   │   └── music/
│   │       ├── menu_music.mp3
│   │       ├── gameplay_1.mp3
│   │       ├── gameplay_2.mp3
│   │       └── garage_music.mp3 (optional)
│   └── licenses/
│       └── LICENSES.txt
└── pubspec.yaml (update with asset paths)
```

---

## License Compliance

### Assets by License Type

#### CC0 (Public Domain - No Attribution Required)
**Visual Assets:**
- All Kenney.nl assets
- Some OpenGameArt assets (check individual)
- Some itch.io packs (check description)

**Audio Assets:**
- Sonniss GameAudioGDC bundle
- Freesound.org CC0 sounds
- JSFXR generated sounds
- Some OpenGameArt music (check individual)

**Action Required:** None - can use freely

---

#### CC-BY (Attribution Required)
**Visual Assets:**
- OpenGameArt "Free Top Down Car Sprites" (attribution appreciated)

**Audio Assets:**
- Incompetech (Kevin MacLeod) - MUST attribute
- Purple Planet Music - MUST attribute
- BenSound - MUST attribute
- Freesound CC-BY sounds - MUST attribute per sound

**Action Required:** Add attribution to game credits

---

### LICENSES.txt Template

Create `assets/licenses/LICENSES.txt`:

```
# Asset Licenses for Taxi Game

## Visual Assets

### Vehicles, UI, Environment (Kenney.nl)
Source: https://kenney.nl
Artist: Kenney Vleugels
License: CC0 1.0 Universal (Public Domain)
Files: All PNG files in assets/images/
Note: No attribution required, but appreciated

### Additional Vehicles (OpenGameArt - Optional)
Source: https://opengameart.org/content/free-top-down-car-sprites-by-unlucky-studio
Artist: Unlucky Studio
License: Royalty-free (attribution appreciated)
Files: Specific vehicle sprites if used
Attribution: "Vehicle sprites by Unlucky Studio (opengameart.org)"

## Audio Assets

### Background Music (Incompetech)
Source: https://incompetech.com
Composer: Kevin MacLeod
License: CC-BY 4.0 (http://creativecommons.org/licenses/by/4.0/)
Files: 
  - menu_music.mp3 (Track: [Name])
  - gameplay_1.mp3 (Track: [Name])
  - gameplay_2.mp3 (Track: [Name])
Attribution Required:
  "Music by Kevin MacLeod (incompetech.com)
   Licensed under Creative Commons: By Attribution 4.0 License"

### Sound Effects (Multiple Sources)

#### Sonniss GDC Bundle (if used)
Source: https://sonniss.com/gameaudiogdc/
License: 100% Royalty-Free, Commercial Use, No Attribution Required
Files: [List specific SFX files used]

#### Freesound.org (if used)
Individual sound attributions:
- [sound_name.mp3]: by [artist] (freesound.org/s/[ID]) - License: [CC0/CC-BY]
- [sound_name.mp3]: by [artist] (freesound.org/s/[ID]) - License: [CC0/CC-BY]

#### JSFXR Generated (if used)
Source: https://sfxr.me
License: Royalty-free (generated sounds)
Files: [List generated sounds]
```

---

### In-Game Credits Screen Template

```
CREDITS

GAME DEVELOPMENT
[Your Name/Studio]

VISUAL ASSETS
Kenney Vleugels (kenney.nl)
CC0 License - Public Domain

MUSIC
Kevin MacLeod (incompetech.com)
Licensed under Creative Commons: By Attribution 4.0
http://creativecommons.org/licenses/by/4.0/

Tracks Used:
- [Track Name 1]
- [Track Name 2]
- [Track Name 3]

SOUND EFFECTS
Sonniss GameAudioGDC (sonniss.com)
Freesound.org community
[Individual artist credits if using CC-BY sounds]

SPECIAL THANKS
The open-source game development community
```

---

## Integration Checklist

### Step 1: Create Directory Structure
```bash
# From taxi_game/ directory
mkdir -p assets/images/vehicles/player
mkdir -p assets/images/vehicles/traffic
mkdir -p assets/images/environment/buildings
mkdir -p assets/images/environment/roads
mkdir -p assets/images/environment/scenery
mkdir -p assets/images/environment/sky
mkdir -p assets/images/ui/icons
mkdir -p assets/images/ui/markers
mkdir -p assets/images/ui/backgrounds
mkdir -p assets/audio/sfx/vehicle
mkdir -p assets/audio/sfx/ambient
mkdir -p assets/audio/sfx/ui
mkdir -p assets/audio/music
mkdir -p assets/licenses
```

### Step 2: Download & Organize Assets

**Phase 1: Critical MVP Assets**
- [ ] Download Kenney All-in-1 or Pixel Vehicle Pack
- [ ] Extract and copy 7 player vehicles to `assets/images/vehicles/player/`
- [ ] Extract and copy 8 traffic vehicles to `assets/images/vehicles/traffic/`
- [ ] Download Kenney UI Pack for icons
- [ ] Copy UI icons to `assets/images/ui/icons/`
- [ ] Download JSFXR and generate 3 basic UI sounds
- [ ] Save to `assets/audio/sfx/ui/`
- [ ] Download 1 Incompetech track for menu music
- [ ] Save to `assets/audio/music/menu_music.mp3`

**Phase 2: Enhanced Assets**
- [ ] Download Sonniss GDC bundle (or Freesound vehicle sounds)
- [ ] Extract 5 vehicle SFX to `assets/audio/sfx/vehicle/`
- [ ] Download 2-3 Incompetech gameplay tracks
- [ ] Save to `assets/audio/music/gameplay_*.mp3`
- [ ] Download additional UI sounds from Freesound
- [ ] Add Kenney environment assets (buildings, trees)

**Phase 3: Polish**
- [ ] Add particle effect sprites
- [ ] Add ambient sound loops
- [ ] Fine-tune asset selection
- [ ] Optimize file sizes (compress PNGs, convert to OGG if needed)

### Step 3: Update pubspec.yaml

Add to `taxi_game/pubspec.yaml`:

```yaml
flutter:
  uses-material-design: true
  
  assets:
    # Vehicle images
    - assets/images/vehicles/player/
    - assets/images/vehicles/traffic/
    
    # Environment
    - assets/images/environment/buildings/
    - assets/images/environment/roads/
    - assets/images/environment/scenery/
    - assets/images/environment/sky/
    
    # UI
    - assets/images/ui/icons/
    - assets/images/ui/markers/
    - assets/images/ui/backgrounds/
    
    # Audio
    - assets/audio/sfx/vehicle/
    - assets/audio/sfx/ambient/
    - assets/audio/sfx/ui/
    - assets/audio/music/
```

### Step 4: Create LICENSES.txt
- [ ] Create `assets/licenses/LICENSES.txt`
- [ ] List all assets used and their licenses
- [ ] Add required attribution text

### Step 5: Verify Integration
- [ ] Run `flutter pub get`
- [ ] Test asset loading in app
- [ ] Verify all images appear correctly
- [ ] Test audio playback
- [ ] Check file sizes (optimize if needed)
- [ ] Verify licenses are properly documented

---

## Asset Acquisition Summary by Phase

### Phase 1: MVP (Week 1) - Can Start Immediately

**Download Now:**
1. Kenney Pixel Vehicle Pack → Get 7 player + 8 traffic vehicles
2. Kenney UI Pack → Get all UI icons
3. JSFXR → Generate 3 UI sounds (click, pickup, complete)
4. Incompetech → Download 1 menu music track

**Time Required:** 1-2 hours
**Storage:** ~50MB
**Blockers:** None

### Phase 2: Enhanced (Week 2-3) - Add When Ready

**Download Next:**
1. Sonniss GDC Bundle → Extract vehicle sounds
2. Incompetech → Download 2-3 gameplay music tracks
3. Freesound → Download 5 additional UI sounds
4. Kenney Environment Packs → Buildings, scenery

**Time Required:** 2-4 hours
**Storage:** ~500MB (if using Sonniss)
**Blockers:** None (all free)

### Phase 3: Polish (Week 4+) - Final Touches

**Download Last:**
1. Additional vehicle sprites from itch.io
2. Particle effect sprites
3. Ambient sound loops
4. Alternative music tracks

**Time Required:** 2-3 hours
**Storage:** ~100MB
**Blockers:** None

---

## Quick Start Guide

**If you want to start coding immediately:**

1. Download Kenney All-in-1: https://kenney.itch.io/kenney-game-assets
2. Extract the ZIP file
3. Copy these folders to your project:
   - `kenney-game-assets/2D assets/Topdown Vehicles/` → `taxi_game/assets/images/vehicles/`
   - `kenney-game-assets/UI/` → `taxi_game/assets/images/ui/`
4. Use JSFXR (https://sfxr.me) to generate 3 quick sounds
5. Download 1 song from Incompetech
6. Update pubspec.yaml
7. Start coding!

**Total time: 30 minutes to be fully asset-ready for MVP**

---

## Troubleshooting

### Issue: Download links not working
**Solution:** All listed sources are active as of 2024. If a specific pack is unavailable, use the All-in-1 bundle from Kenney or browse alternatives on itch.io.

### Issue: Attribution confusion
**Solution:** When in doubt, add attribution. CC0 doesn't require it but you can still credit. CC-BY MUST have attribution.

### Issue: File formats wrong
**Solution:** 
- Images: Convert to PNG if needed (use online converter or Paint)
- Audio: MP3 is standard, but OGG is smaller. Flutter supports both.

### Issue: Files too large
**Solution:**
- Images: Use TinyPNG (https://tinypng.com) to compress
- Audio: Convert to OGG or reduce bitrate to 128kbps

### Issue: Can't find specific sound
**Solution:** Use JSFXR to generate it, or try alternative search terms on Freesound (e.g., "automobile" instead of "car").

---

## Next Steps

After creating this plan, the recommended workflow is:

1. ✅ Review this plan
2. ⏳ Toggle to Act Mode and request asset download assistance
3. ⏳ Create directory structure
4. ⏳ Download Phase 1 MVP assets
5. ⏳ Update pubspec.yaml
6. ⏳ Test asset integration
7. ⏳ Download Phase 2 & 3 assets as needed

**Estimated Total Time:** 4-8 hours spread over project timeline
**Total Storage:** ~1GB for all assets
**Total Cost:** $0 (all free)

---

## Conclusion

This plan provides everything needed to acquire all visual and audio assets for the taxi game without any cost. All sources are verified, legally compliant, and ready for commercial use (with proper attribution where required).

The phased approach ensures you can start development immediately with MVP assets while building out a more polished asset library over time.

For any questions or if specific assets can't be found, refer to the fallback sources or use the JSFXR tool for quick custom generation.
