# Asset Download Checklist for Taxi Game MVP

Use this checklist to track your asset download progress. Check off each item as you complete it.

## 📋 Quick Reference

**Total Estimated Time:** 30-45 minutes  
**Total Files Needed:** 19-25 files  
**Storage Required:** ~50-100MB  
**Cost:** $0 (100% free assets)

---

## ✅ Step-by-Step Checklist

### 1. Player Vehicles (7 files) - REQUIRED
**Location:** `taxi_game/assets/images/vehicles/player/`  
**Source:** https://kenney.nl/assets/pixel-vehicle-pack

- [ ] Downloaded and extracted Kenney Pixel Vehicle Pack
- [ ] `taxi_yellow.png` - Classic yellow taxi
- [ ] `sedan_blue.png` - Blue sedan
- [ ] `compact_red.png` - Red compact car
- [ ] `suv_green.png` - Green SUV
- [ ] `sports_black.png` - Black sports car
- [ ] `luxury_white.png` - White luxury vehicle
- [ ] `minivan_gray.png` - Gray minivan

**Status:** [ ] Complete

---

### 2. Traffic Vehicles (8 files) - REQUIRED
**Location:** `taxi_game/assets/images/vehicles/traffic/`  
**Source:** https://kenney.nl/assets/pixel-vehicle-pack

- [ ] `sedan_gray.png` - Gray sedan
- [ ] `compact_white.png` - White compact car
- [ ] `suv_blue.png` - Blue SUV
- [ ] `truck_red.png` - Red truck
- [ ] `van_white.png` - White van
- [ ] `bus_yellow.png` - Yellow bus
- [ ] `sports_red.png` - Red sports car
- [ ] `motorcycle_black.png` - Black motorcycle (if available)

**Status:** [ ] Complete

---

### 3. UI Sound Effects (3 files) - REQUIRED
**Location:** `taxi_game/assets/audio/sfx/ui/`  
**Source:** https://sfxr.me/

- [ ] Opened JSFXR website (https://sfxr.me/)
- [ ] `button_click.wav` - Generated with PICKUP/COIN preset
- [ ] `coin_collect.wav` - Generated with PICKUP/COIN preset
- [ ] `level_complete.wav` - Generated with POWERUP preset

**Status:** [ ] Complete

---

### 4. Background Music (1 file) - REQUIRED
**Location:** `taxi_game/assets/audio/music/`  
**Source:** https://incompetech.com/

- [ ] `menu_music.mp3` - Downloaded Cipher or alternative track
- [ ] Updated `taxi_game/assets/licenses/LICENSES.txt` with track name

**Track chosen:** ___________________

**Status:** [ ] Complete

---

### 5. UI Icons (4-8 files) - OPTIONAL
**Location:** `taxi_game/assets/images/ui/icons/`  
**Source:** https://kenney.nl/assets/ui-pack OR https://kenney.nl/assets/game-icons

- [ ] `pause.png` (optional - can use Material Icons)
- [ ] `play.png` (optional - can use Material Icons)
- [ ] `settings.png` (optional - can use Material Icons)
- [ ] `back.png` (optional - can use Material Icons)
- [ ] `coin.png` (optional)
- [ ] `star.png` (optional)
- [ ] `lock.png` (optional)
- [ ] `checkmark.png` (optional)

**Status:** [ ] Complete / [ ] Skipped (using Flutter Material Icons)

---

## 🎯 Final Verification

After downloading all assets:

### File Structure Check
- [ ] `taxi_game/assets/images/vehicles/player/` contains 7 vehicle PNG files
- [ ] `taxi_game/assets/images/vehicles/traffic/` contains 8 vehicle PNG files
- [ ] `taxi_game/assets/audio/sfx/ui/` contains 3 sound effect files
- [ ] `taxi_game/assets/audio/music/` contains 1 music file

### License Check
- [ ] `taxi_game/assets/licenses/LICENSES.txt` updated with music track name
- [ ] Music attribution text is correct

### Flutter Integration
- [ ] Ran `flutter pub get` successfully
- [ ] No errors in `pubspec.yaml`
- [ ] Ready to run `flutter run`

---

## 📁 Directory Structure

Your asset directory should look like this:

```
taxi_game/assets/
├── audio/
│   ├── music/
│   │   └── menu_music.mp3 ✓
│   └── sfx/
│       └── ui/
│           ├── button_click.wav ✓
│           ├── coin_collect.wav ✓
│           └── level_complete.wav ✓
├── images/
│   ├── ui/
│   │   └── icons/
│   │       └── (optional icon files)
│   └── vehicles/
│       ├── player/
│       │   ├── taxi_yellow.png ✓
│       │   ├── sedan_blue.png ✓
│       │   ├── compact_red.png ✓
│       │   ├── suv_green.png ✓
│       │   ├── sports_black.png ✓
│       │   ├── luxury_white.png ✓
│       │   └── minivan_gray.png ✓
│       └── traffic/
│           ├── sedan_gray.png ✓
│           ├── compact_white.png ✓
│           ├── suv_blue.png ✓
│           ├── truck_red.png ✓
│           ├── van_white.png ✓
│           ├── bus_yellow.png ✓
│           ├── sports_red.png ✓
│           └── motorcycle_black.png ✓
└── licenses/
    └── LICENSES.txt ✓
```

---

## 🚀 Next Steps After Completion

1. **Run Flutter pub get:**
   ```bash
   cd taxi_game
   flutter pub get
   ```

2. **Test the app:**
   ```bash
   flutter run
   ```

3. **Verify assets load correctly** in the game

4. **Begin coding** - all MVP assets are ready!

---

## 📚 Reference Documents

- **Detailed Instructions:** See `MANUAL_DOWNLOAD_INSTRUCTIONS.md`
- **Asset Plan:** See `plans/DOWNLOAD-GUIDE.md`
- **License Info:** See `taxi_game/assets/licenses/LICENSES.txt`
- **Directory READMEs:** Check each asset directory for specific guidance

---

## ❓ Troubleshooting

### Issue: Can't download from Kenney
- Try a different browser
- Disable popup blockers
- Clear browser cache and try again

### Issue: JSFXR sounds aren't working
- Keep generating until you find good ones
- You can skip for MVP and add later
- Convert WAV to MP3 if needed at https://cloudconvert.com/

### Issue: Music track won't download
- Try alternative tracks listed in instructions
- Ensure you're not using an ad blocker on Incompetech

### Issue: File paths not working in Flutter
- Double-check file names match exactly (case-sensitive)
- Run `flutter pub get` after adding files
- Restart your IDE/editor

---

## 📊 Progress Summary

**Total Required Files:** 19 minimum (7 player + 8 traffic + 3 sounds + 1 music)  
**Total Optional Files:** 0-8 (UI icons)

**Your Progress:**
- Player Vehicles: [ ] 0/7
- Traffic Vehicles: [ ] 0/8
- Sound Effects: [ ] 0/3
- Music: [ ] 0/1
- UI Icons: [ ] 0/0 (optional)

**Overall:** [ ] 0/19 files complete

---

Once all required files are downloaded, you're ready to start building your taxi game! 🚕🎮
