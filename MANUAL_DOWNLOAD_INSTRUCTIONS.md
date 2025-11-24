# Manual Asset Download Instructions

Due to website restrictions, the following assets need to be downloaded manually. Follow these step-by-step instructions.

## Status: Assets to Download

### ✅ Directory Structure Created
All necessary folders have been created in `taxi_game/assets/`

### 📥 Assets You Need to Download Manually

---

## STEP 1: Download Kenney Pixel Vehicle Pack

**URL:** https://kenney.nl/assets/pixel-vehicle-pack

### Instructions:
1. Open the URL in your browser
2. Click the green **"Download"** button on the page
3. The file `pixelvehiclepack.zip` will download
4. Extract the ZIP file to a temporary location
5. From the extracted folder, select **7 player vehicles**:
   - Look for PNG files like: `car_yellow_1.png`, `car_blue_1.png`, `car_red_1.png`, etc.
   - Choose varied types (sedan, compact, SUV, sports)
   
6. Copy those 7 vehicle files to: `d:\git\taxiGame\taxi_game\assets\images\vehicles\player\`

7. Rename them for clarity:
   - `taxi_yellow.png` (classic taxi)
   - `sedan_blue.png`
   - `compact_red.png`
   - `suv_green.png`
   - `sports_black.png`
   - `luxury_white.png`
   - `minivan_gray.png`

8. Select **8 AI traffic vehicles** (different from player vehicles):
   - Choose different colors and sizes
   
9. Copy those 8 files to: `d:\git\taxiGame\taxi_game\assets\images\vehicles\traffic\`

10. Rename them:
    - `sedan_gray.png`
    - `compact_white.png`
    - `suv_blue.png`
    - `truck_red.png`
    - `van_white.png`
    - `bus_yellow.png`
    - `sports_red.png`
    - `motorcycle_black.png` (if available)

---

## STEP 2: Download Kenney UI Pack (OPTIONAL - Can Skip for MVP)

**URL:** https://kenney.nl/assets/ui-pack

### Instructions:
1. Open the URL in your browser
2. Click the **"Download"** button
3. Extract the ZIP file
4. Find these icons:
   - Pause icon
   - Play icon
   - Settings/gear icon
   - Back arrow
   
5. Copy to: `d:\git\taxiGame\taxi_game\assets\images\ui\icons\`

6. Rename them:
   - `pause.png`
   - `play.png`
   - `settings.png`
   - `back.png`

**Alternative:** You can skip this step and use Flutter's built-in Material Icons instead.

---

## STEP 3: Download Kenney Game Icons (OPTIONAL)

**URL:** https://kenney.nl/assets/game-icons

### Instructions:
1. Open the URL in your browser
2. Click the **"Download"** button
3. Extract the ZIP file
4. Find these icons:
   - Coin icon
   - Star icon
   - Lock icon
   - Checkmark icon
   
5. Copy to: `d:\git\taxiGame\taxi_game\assets\images\ui\icons\`

6. Rename them:
   - `coin.png`
   - `star.png`
   - `lock.png`
   - `checkmark.png`

---

## STEP 4: Generate Sound Effects with JSFXR

**URL:** https://sfxr.me/

### Instructions:

#### Sound 1: Button Click
1. Open https://sfxr.me/ in your browser
2. Click the **"PICKUP/COIN"** button (generates random sound)
3. Keep clicking until you find a short, satisfying "click" sound
4. Click **"EXPORT .WAV"**
5. Save the file
6. Rename it to: `button_click.wav`
7. Move it to: `d:\git\taxiGame\taxi_game\assets\audio\sfx\ui\button_click.wav`

#### Sound 2: Coin Collection
1. Still on https://sfxr.me/
2. Click **"PICKUP/COIN"** again
3. Find a pleasant "cha-ching" style sound
4. Click **"EXPORT .WAV"**
5. Save and rename to: `coin_collect.wav`
6. Move to: `d:\git\taxiGame\taxi_game\assets\audio\sfx\ui\coin_collect.wav`

#### Sound 3: Level Complete
1. Still on https://sfxr.me/
2. Click **"POWERUP"** or **"RANDOM"**
3. Find an upbeat, ascending tone
4. Click **"EXPORT .WAV"**
5. Save and rename to: `level_complete.wav`
6. Move to: `d:\git\taxiGame\taxi_game\assets\audio\sfx\ui\level_complete.wav`

---

## STEP 5: Download Background Music from Incompetech

**Recommended Track:** Cipher

### Instructions:
1. Go to: https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100525
2. On the track page, click **"Download MP3"** (usually in the right sidebar)
3. Save the MP3 file
4. Rename it to: `menu_music.mp3`
5. Move it to: `d:\git\taxiGame\taxi_game\assets\audio\music\menu_music.mp3`

**Alternative Tracks** (if Cipher doesn't work):
- **Pixel Peeker Polka:** https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100768
- **Hyperfun:** https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100316

---

## VERIFICATION CHECKLIST

After downloading all assets, verify you have:

### Minimum Required for MVP:
- [ ] 7 vehicle PNG files in `taxi_game/assets/images/vehicles/player/`
- [ ] 8 vehicle PNG files in `taxi_game/assets/images/vehicles/traffic/`
- [ ] `button_click.wav` in `taxi_game/assets/audio/sfx/ui/`
- [ ] `coin_collect.wav` in `taxi_game/assets/audio/sfx/ui/`
- [ ] `level_complete.wav` in `taxi_game/assets/audio/sfx/ui/`
- [ ] `menu_music.mp3` in `taxi_game/assets/audio/music/`

### Optional (Can Skip for MVP):
- [ ] UI icons in `taxi_game/assets/images/ui/icons/` (4-8 PNG files)

---

## After Downloading

1. Run this command to update Flutter's asset registry:
   ```bash
   cd taxi_game
   flutter pub get
   ```

2. Test that the app can load assets:
   ```bash
   flutter run
   ```

---

## Need Help?

### Problem: Can't find specific vehicle
**Solution:** Use any similar vehicle. Exact matches aren't critical - variety matters more.

### Problem: JSFXR sounds aren't good
**Solution:** Keep generating until you find something decent, or skip sound effects for MVP.

### Problem: Files won't download
**Solution:** Try a different browser, or check if you need to disable popup blockers.

### Problem: File format conversions needed
**Solution:** Use https://cloudconvert.com/ to convert between formats (WAV ↔ MP3).

---

## Summary

**Estimated Time:** 30-45 minutes  
**Total Files to Download:** ~20-25 files  
**Total Size:** ~50-100MB

Once complete, you'll have all the assets needed to start coding the taxi game! 🚕🎮
