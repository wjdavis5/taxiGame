# Asset Requirements Document

## Overview
This document outlines all visual and audio assets needed for the taxi game. For the initial implementation, we'll use placeholders and simple SVG graphics that can be replaced later with professional assets.

## Asset Strategy

### Initial Implementation (Phase 1-2)
- **SVG graphics** for all visual elements (scalable, small file size)
- **Simple geometric shapes** for vehicles and environment
- **Solid colors** with minimal details
- **Placeholder audio** or silence
- **No external asset dependencies** for basic prototype

### Future Enhancement (Phase 3+)
- **Professional sprite sheets** or 3D rendered sprites
- **Detailed textures** and effects
- **Custom sound effects** and music
- **Particle effect sprites**

---

## Visual Assets

### 1. VEHICLES

#### Player Taxis (Required: 5-15 vehicles)

**Starter Vehicles:**
- [ ] Classic yellow taxi (default)
  - SVG: Simple rectangle body, black windows, yellow color
  - Size: ~80x40 pixels at base resolution
  - Views needed: Top-down view
  
- [ ] Basic sedan
  - SVG: Rounded rectangle, varied color
  - Size: ~80x40 pixels

**Unlockable Vehicles:**
- [ ] Compact car (small, square-ish)
- [ ] SUV (larger, taller)
- [ ] Sports car (sleek, low profile)
- [ ] Luxury sedan (elongated)
- [ ] Minivan (wide body)

**Asset Specifications:**
- **Format:** SVG (initial), PNG sprite sheets (future)
- **Dimensions:** Base 80x40 pixels, scalable
- **Color variations:** 5-10 colors per vehicle type
- **Components:** Body, windows, wheels (separate layers)
- **Shadows:** Simple drop shadow or none

**Current Status:** Will create using Flutter's Canvas API or simple SVG shapes

---

#### AI Traffic Vehicles (Required: 5-8 types)

- [ ] Generic sedan (most common)
- [ ] Compact car
- [ ] SUV
- [ ] Pickup truck
- [ ] Delivery van
- [ ] Bus (larger obstacle)
- [ ] Sports car (faster traffic)
- [ ] Motorcycle (narrow obstacle)

**Asset Specifications:**
- **Format:** SVG or simple shapes
- **Dimensions:** Varied sizes (60x30 to 120x50 pixels)
- **Colors:** Muted palette (gray, blue, red, white, black)
- **Details:** Minimal - just silhouettes

**Current Status:** Will use colored rectangles with rounded corners

---

### 2. ENVIRONMENT ASSETS

#### Road Elements (Required)

- [ ] **Road texture**
  - Asphalt gray color
  - Lane markings (white dashed lines)
  - Size: Tileable texture
  - Format: Simple gradient or solid color

- [ ] **Intersection**
  - Crosswalk markings
  - Stop lines
  - Traffic light positions marked

- [ ] **Highway lanes**
  - Multiple parallel lanes
  - Merge indicators

**Current Status:** Will render using Flutter Canvas with simple shapes

---

#### Buildings & Scenery (Background elements)

- [ ] **City buildings** (10+ variations)
  - Simple rectangles in varied heights
  - Window grid pattern
  - Colors: Gray, beige, brown tones
  - Low detail for background parallax

- [ ] **Trees** (3-5 types)
  - Simple circles (foliage) on rectangles (trunk)
  - Green, various shades

- [ ] **Street furniture**
  - Traffic cones (orange triangles)
  - Street lights (pole + light)
  - Barriers (striped rectangles)
  - Benches (small rectangles)

**Asset Specifications:**
- **Format:** SVG or Canvas drawing
- **Detail level:** Very low - background elements
- **Colors:** Muted, non-distracting

**Current Status:** Will use simple geometric shapes

---

#### Sky & Background

- [ ] **Sky gradients** (3 variations)
  - Day: Light blue to white
  - Sunset: Orange to purple
  - Night: Dark blue to black

- [ ] **Clouds** (optional)
  - Simple white ovals

**Current Status:** Linear gradients in Flutter

---

### 3. UI GRAPHICS

#### Icons & Buttons

- [ ] **Pause button** (⏸ icon)
- [ ] **Play button** (▶ icon)
- [ ] **Settings gear** (⚙ icon)
- [ ] **Back arrow** (← icon)
- [ ] **Coin icon** (circular with $ or similar)
- [ ] **Gem icon** (diamond shape)
- [ ] **Star icon** (for ratings)
- [ ] **Lock icon** (for locked content)
- [ ] **Checkmark** (for completion)

**Asset Specifications:**
- **Format:** Flutter Icons package or SVG
- **Size:** 24x24, 32x32, 48x48 dp
- **Style:** Simple, clear, high contrast

**Current Status:** Will use Flutter's Material Icons or custom SVG

---

#### HUD Elements

- [ ] **Distance indicator** (progress bar)
- [ ] **Passenger indicator** (person silhouette)
- [ ] **Pickup marker** (green glowing circle)
- [ ] **Dropoff marker** (yellow/red glowing circle)
- [ ] **Arrow pointer** (directional guide)

**Current Status:** Custom drawn with Flutter Canvas

---

#### Menu Backgrounds

- [ ] Main menu background (city scene or solid color)
- [ ] Level complete background (confetti effect)
- [ ] Level failed background (simple overlay)

**Current Status:** Gradient backgrounds + simple effects

---

### 4. PARTICLE EFFECTS

- [ ] **Tire smoke** (when braking)
  - Simple white/gray circles that fade
  
- [ ] **Crash explosion** (cartoonish)
  - Star burst shape, expanding circles
  - Orange/yellow colors
  
- [ ] **Coin collection sparkle**
  - Small yellow stars
  - Particle burst effect
  
- [ ] **Confetti** (level complete)
  - Colored rectangles falling
  
- [ ] **Pickup/dropoff effect**
  - Glowing circle expanding

**Asset Specifications:**
- **Format:** Procedurally generated or simple sprites
- **Animation:** Flame particle system
- **Colors:** Bright, saturated

**Current Status:** Will use Flame's particle system

---

## Audio Assets

### 1. SOUND EFFECTS (Required)

#### Vehicle Sounds
- [ ] **Engine idle** (loop)
  - Duration: 2-5 seconds, loopable
  - Format: MP3 or OGG
  - Volume: Low, subtle
  - **Status:** NEEDED - placeholder silence for now

- [ ] **Engine acceleration** (oneshot)
  - Duration: 1-2 seconds
  - Format: MP3 or OGG
  - **Status:** NEEDED

- [ ] **Brake/tire screech** (oneshot)
  - Duration: 0.5-1 second
  - **Status:** NEEDED

- [ ] **Crash sound** (oneshot)
  - Duration: 0.5-1 second
  - Type: Comedic, not realistic
  - **Status:** NEEDED

- [ ] **Near-miss whoosh** (oneshot)
  - Duration: 0.3-0.5 seconds
  - **Status:** NEEDED

---

#### Ambient Sounds
- [ ] **City traffic ambience** (loop)
  - Duration: 10-30 seconds, loopable
  - Volume: Very low background
  - **Status:** NEEDED (low priority)

- [ ] **Pedestrian chatter** (loop, optional)
  - Duration: 5-15 seconds
  - **Status:** NEEDED (low priority)

---

#### UI Sounds
- [ ] **Button click/tap**
  - Duration: <0.1 seconds
  - Type: Soft, satisfying click
  - **Status:** NEEDED

- [ ] **Coin collection** ("cha-ching")
  - Duration: 0.3-0.5 seconds
  - **Status:** NEEDED

- [ ] **Passenger pickup** (car door + voice)
  - Duration: 1-2 seconds
  - Voice: "Thanks!" or similar
  - **Status:** NEEDED

- [ ] **Passenger dropoff** (car door + voice)
  - Duration: 1-2 seconds
  - Voice: "Great ride!" or similar
  - **Status:** NEEDED

- [ ] **Level complete jingle**
  - Duration: 3-5 seconds
  - Type: Triumphant, upbeat
  - **Status:** NEEDED

- [ ] **Level failed tone**
  - Duration: 1 second
  - Type: Descending, disappointing
  - **Status:** NEEDED

---

### 2. MUSIC (Required)

#### Background Music Tracks
- [ ] **Main menu music**
  - Duration: 60-120 seconds, loopable
  - Style: Upbeat, casual, inviting
  - Tempo: ~100-120 BPM
  - Format: MP3 or OGG
  - **Status:** NEEDED

- [ ] **Gameplay music** (2-3 variations)
  - Duration: 60-90 seconds each, loopable
  - Style: Electronic/pop instrumental
  - Tempo: 120-140 BPM
  - Format: MP3 or OGG
  - **Status:** NEEDED

- [ ] **Garage/vehicle selection music** (optional)
  - Duration: 60-90 seconds, loopable
  - Style: Similar to menu but slightly different
  - **Status:** NEEDED (low priority)

**Music Specifications:**
- **Format:** MP3 (128-192 kbps) or OGG
- **Length:** 1-2 minutes per track
- **Style:** Cheerful, non-intrusive, loopable
- **No lyrics** (instrumental only)

---

## Asset Creation Plan

### Phase 1: Basic Placeholders (Week 1)
- Simple SVG vehicles (rectangles with rounded corners)
- Solid color roads and backgrounds
- Basic UI icons from Flutter's icon set
- No sound effects (silent)
- No music (silent)

### Phase 2: Improved Placeholders (Week 2-3)
- More detailed SVG vehicles with wheels
- Textured roads with lane markings
- Simple particle effects
- Basic sound effects (free sources or generated)
- Simple background music (royalty-free)

### Phase 3: Professional Assets (Week 4+)
- Custom designed vehicles (commission or create)
- Detailed environment art
- Professional sound design
- Original music composition
- Polished particle effects

---

## Free Asset Resources (Temporary Use)

### Sound Effects
- **Freesound.org** - Creative Commons sounds
- **Zapsplat.com** - Free sound effects library
- **OpenGameArt.org** - Game audio
- **JSFXR** - Generate simple game sounds

### Music
- **Incompetech.com** - Royalty-free music by Kevin MacLeod
- **Purple Planet Music** - Free game music
- **BenSound** - Royalty-free tracks
- **OpenGameArt.org** - Game music

### Graphics (Reference/Inspiration)
- **OpenGameArt.org** - CC-licensed game art
- **Kenney.nl** - Free game assets
- **itch.io** - Game asset bundles

**Important:** All free assets must be properly attributed and licensed for commercial use if game is monetized.

---

## Asset Tracking

### Critical Path Assets (Needed for MVP)
1. ✅ Player taxi vehicle (simple rectangle) - Can create
2. ✅ AI traffic vehicles (simple shapes) - Can create
3. ✅ Road rendering (canvas drawing) - Can create
4. ✅ Pickup/dropoff markers (circles) - Can create
5. ✅ Basic UI icons (Flutter icons) - Available
6. ⏳ Engine/brake sounds - NEEDED (can proceed without)
7. ⏳ Crash sound - NEEDED (can proceed without)
8. ⏳ UI button sound - NEEDED (can proceed without)

### Nice-to-Have Assets (Post-MVP)
- Detailed vehicle models
- Animated particles
- Environmental details
- Professional audio
- Music tracks
- Multiple vehicle skins

---

## Asset Integration Checklist

- [ ] Create assets/ directory structure
- [ ] Add sample SVG vehicle
- [ ] Create road texture/pattern
- [ ] Add UI icons
- [ ] Set up audio player service
- [ ] Create asset loading system
- [ ] Implement asset preloading
- [ ] Add asset caching
- [ ] Test on multiple screen sizes
- [ ] Optimize asset sizes

---

## Summary

**Can Proceed Immediately With:**
- Simple geometric shapes for all visuals
- Flutter Canvas drawing for roads/environment
- Flutter Icons for UI elements
- Silent audio (game functional without sound)

**Will Need Eventually:**
- Custom vehicle designs (SVG or sprites)
- Sound effects (8-12 unique sounds)
- Music tracks (2-3 background tracks)
- Professional UI graphics

**Recommended Approach:**
1. Build entire game with placeholder assets
2. Test and refine gameplay mechanics
3. Replace placeholders incrementally
4. Commission or create final assets last

This approach allows rapid development without being blocked on asset creation.
