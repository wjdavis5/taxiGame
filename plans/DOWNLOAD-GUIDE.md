# Quick Asset Download Guide - Phase 1 MVP

This guide will help you download the essential assets to get started with development immediately. This is the **minimal viable product (MVP) asset set** that lets you start coding today.

**Estimated Time:** 30-60 minutes  
**Total Storage:** ~100MB  
**Cost:** $0 (100% free)

---

## Phase 1: Critical MVP Assets

### Step 1: Download Kenney Vehicle Pack (PRIMARY VISUAL ASSETS)

**Option A: Individual Pack (Recommended for Quick Start)**

1. **Go to Kenney's Pixel Vehicle Pack:**
   - URL: https://kenney.nl/assets/pixel-vehicle-pack
   
2. **Click "Download" button** (green button on the page)
   
3. **Extract the ZIP file** to your Downloads folder
   
4. **Select 7 player vehicles:**
   - Look for files like: `car_yellow_*.png`, `car_blue_*.png`, `car_red_*.png`, etc.
   - Choose varied vehicle types (sedan, compact, SUV, sports)
   - Copy them to: `taxi_game/assets/images/vehicles/player/`
   - Rename for clarity:
     - `taxi_yellow.png` (classic taxi)
     - `sedan_blue.png`
     - `compact_red.png`
     - `suv_green.png`
     - `sports_black.png`
     - `luxury_white.png`
     - `minivan_gray.png`

5. **Select 8 AI traffic vehicles:**
   - Choose different colors and sizes
   - Copy them to: `taxi_game/assets/images/vehicles/traffic/`
   - Rename for clarity:
     - `sedan_gray.png`
     - `compact_white.png`
     - `suv_blue.png`
     - `truck_red.png`
     - `van_white.png`
     - `bus_yellow.png`
     - `sports_red.png`
     - `motorcycle_black.png` (if available)

**Option B: All-in-1 Bundle (Recommended for Complete Assets)**

1. **Go to Kenney's All-in-1 Bundle:**
   - URL: https://kenney.itch.io/kenney-game-assets
   
2. **Click "Download Now"** (no payment required)
   
3. **Extract the large ZIP file** (~2GB)
   
4. **Navigate to:** `kenney-game-assets/2D assets/Topdown Vehicles/`
   
5. **Copy vehicle PNGs** following the same structure as Option A above

---

### Step 2: Download Kenney UI Pack (UI ICONS)

1. **Go to Kenney's UI Pack:**
   - URL: https://kenney.nl/assets/ui-pack
   
2. **Download the pack**
   
3. **Extract and find these icons:**
   - Pause icon (or use ⏸)
   - Play icon (or use ▶)
   - Settings/gear icon
   - Back arrow
   
4. **Copy to:** `taxi_game/assets/images/ui/icons/`
   
5. **Rename them:**
   - `pause.png`
   - `play.png`
   - `settings.png`
   - `back.png`

**Alternative:** You can skip this step initially and use Flutter's built-in Material Icons. The game will work fine without custom icons for MVP.

---

### Step 3: Download Kenney Game Icons (COINS, STARS, ETC.)

1. **Go to Kenney's Game Icons:**
   - URL: https://kenney.nl/assets/game-icons
   
2. **Download the pack**
   
3. **Extract and find:**
   - Coin icon
   - Star icon
   - Lock icon
   - Checkmark icon
   
4. **Copy to:** `taxi_game/assets/images/ui/icons/`
   
5. **Rename them:**
   - `coin.png`
   - `star.png`
   - `lock.png`
   - `checkmark.png`

---

### Step 4: Generate UI Sounds with JSFXR (BASIC SOUND EFFECTS)

1. **Open JSFXR in your browser:**
   - URL: https://sfxr.me/
   
2. **Generate Button Click sound:**
   - Click "PICKUP/COIN" button (generates random sound)
   - Keep clicking until you find a short, satisfying "click" sound
   - Or click "RANDOM" and adjust settings
   - Click "EXPORT .WAV"
   - Save as: `button_click.wav`
   - Move to: `taxi_game/assets/audio/sfx/ui/button_click.wav`
   
3. **Generate Coin Collection sound:**
   - Click "PICKUP/COIN" again
   - Find a pleasant "cha-ching" style sound
   - Export as: `coin_collect.wav`
   - Move to: `taxi_game/assets/audio/sfx/ui/coin_collect.wav`
   
4. **Generate Level Complete sound:**
   - Click "POWERUP" or "RANDOM"
   - Find an upbeat, ascending tone
   - Export as: `level_complete.wav`
   - Move to: `taxi_game/assets/audio/sfx/ui/level_complete.wav`

**Note:** You can convert WAV to MP3 later if needed. Flutter supports both formats.

---

### Step 5: Download Background Music from Incompetech (MENU MUSIC)

1. **Go to Incompetech:**
   - URL: https://incompetech.com/music/royalty-free/music.html
   
2. **Search for upbeat music:**
   - Use search box: "upbeat electronic"
   - Or browse: Electronic → Upbeat
   
3. **Recommended tracks for menu music:**
   - **"Cipher"** - Great for main menu (122 BPM, electronic)
     - URL: https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100525
   - **"Pixel Peeker Polka"** - Fun, retro style
     - URL: https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100768
   - **"Hyperfun"** - Electronic dance (140 BPM)
     - URL: https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100316
   
4. **Download ONE track for now:**
   - Click the track title
   - Click "Download MP3"
   - Save to: `taxi_game/assets/audio/music/menu_music.mp3`
   
5. **Important:** Note the track name for attribution in LICENSES.txt

**Attribution Required:** You MUST add this to your game credits:
```
Music by Kevin MacLeod (incompetech.com)
Licensed under Creative Commons: By Attribution 4.0 License
http://creativecommons.org/licenses/by/4.0/
Track: [Insert track name here]
```

---

## Verification Checklist

After downloading, verify you have these files:

### Visual Assets
- [ ] `taxi_game/assets/images/vehicles/player/` → 7 vehicle PNG files
- [ ] `taxi_game/assets/images/vehicles/traffic/` → 8 vehicle PNG files
- [ ] `taxi_game/assets/images/ui/icons/` → 4-8 icon PNG files (optional for MVP)

### Audio Assets
- [ ] `taxi_game/assets/audio/sfx/ui/button_click.wav` (or .mp3)
- [ ] `taxi_game/assets/audio/sfx/ui/coin_collect.wav` (or .mp3)
- [ ] `taxi_game/assets/audio/sfx/ui/level_complete.wav` (or .mp3)
- [ ] `taxi_game/assets/audio/music/menu_music.mp3`

### License Files
- [ ] `taxi_game/assets/licenses/LICENSES.txt` exists and is updated

---

## Update LICENSES.txt

1. **Open:** `taxi_game/assets/licenses/LICENSES.txt`

2. **Update the music section** with the actual track name:
   ```
   Files: 
     - menu_music.mp3 (Track: Cipher)  # Replace with actual track name
   ```

3. **Save the file**

---

## Test Asset Loading

1. **Run Flutter pub get:**
   ```bash
   cd taxi_game
   flutter pub get
   ```

2. **Verify no errors** in pubspec.yaml

3. **Assets are now ready to use in your Flutter/Flame code!**

---

## What You Can Skip for MVP

You can start coding immediately WITHOUT these assets:

- ❌ Vehicle sound effects (engine, brake, crash) - Can add later
- ❌ Multiple gameplay music tracks - One track is enough
- ❌ Environment assets (buildings, trees) - Can use solid colors
- ❌ Road textures - Can draw with Canvas
- ❌ Particle effects - Can add later
- ❌ Custom UI backgrounds - Can use gradients

**The game will work perfectly with just the Phase 1 assets above.**

---

## Next Steps After Phase 1

Once you have Phase 1 assets and want more:

### Phase 2: Enhanced Assets (Week 2-3)
1. Download Sonniss GDC Bundle for professional vehicle sounds
2. Download 2-3 more Incompetech gameplay music tracks
3. Add Kenney environment packs (buildings, scenery)
4. Download additional UI sounds from Freesound

### Phase 3: Polish (Week 4+)
1. Add particle effect sprites
2. Add ambient sound loops
3. Fine-tune asset selection
4. Optimize all file sizes

**See the full `plans/asset-acquisition-plan.md` for details on Phase 2 and 3.**

---

## Troubleshooting

### Problem: Can't find specific vehicle in Kenney pack
**Solution:** Just use any similar vehicle. Exact matches aren't critical - the important thing is having variety (different sizes and colors).

### Problem: JSFXR sounds aren't good enough
**Solution:** Keep clicking the generation buttons until you find something decent. Or skip sound effects entirely for MVP and add them later.

### Problem: Don't want to download 2GB Kenney bundle
**Solution:** Use Option A (individual packs). The Pixel Vehicle Pack is only ~5MB and has everything you need.

### Problem: Audio files are WAV but need MP3
**Solution:** Use an online converter like https://cloudconvert.com/wav-to-mp3 or just use WAV files - Flutter supports both.

### Problem: Asset paths not working in Flutter
**Solution:** Make sure you ran `flutter pub get` after updating pubspec.yaml. Restart your IDE/editor if needed.

---

## Quick Command Reference

```bash
# Navigate to project
cd taxi_game

# Verify directory structure
dir assets /s  # Windows
# or
ls -R assets  # Mac/Linux

# Run pub get after adding assets
flutter pub get

# Test that assets load
flutter run
```

---

## Summary

**Minimum Downloads for MVP:**
1. ✅ Kenney Pixel Vehicle Pack (vehicles)
2. ✅ Kenney UI/Game Icons (optional - can use Flutter icons)
3. ✅ 3 sounds from JSFXR (UI sounds)
4. ✅ 1 music track from Incompetech (menu music)

**Total Download Time:** 20-30 minutes  
**Total Files:** ~20-25 files  
**Total Size:** ~50-100MB  

**You're now ready to start coding the game!** 🎮🚕
