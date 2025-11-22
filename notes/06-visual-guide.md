# Visual Asset Guide - Current Implementation

This document describes the current visual implementation using geometric shapes and Canvas drawing.

## Game Screen Layout

```
┌────────────────────────────────────┐
│  Sky Gradient (Light Blue → Blue) │
│                                    │
│  [Building] [Road] [Building]     │
│    Gray      │       Gray         │
│   Shapes     │     Shapes         │
│              │                    │
│          ┌───┴───┐                │
│          │ Taxi  │  ← Player      │
│          │ [🚕] │    (Yellow)    │
│          └───────┘                │
│              │                    │
│          ════│════  ← Road        │
│          ----│----    (Dashed     │
│          ════│════     center     │
│              │         line)      │
│                                    │
└────────────────────────────────────┘
```

## Current Visual Elements

### 1. Player Taxi Vehicle
**Rendered as:**
```
┌──────────┐
│ ▓▓▓▓▓▓▓▓ │  ← Dark window (front)
├──────────┤
│          │
│  YELLOW  │  ← Yellow body
│  BODY    │
│          │
├──────────┤
│ ▓▓▓▓▓▓▓▓ │  ← Dark window (rear)
└──────────┘
 ●       ●   ← Black wheels (circles)

 ●       ●   ← Black wheels (circles)
```

**Implementation:**
- Yellow rounded rectangle (RRect with 8px radius)
- 40px wide × 60px tall
- Black semi-transparent windows (30% opacity)
- 4 black circle wheels (4px radius)
- Simple but recognizable as a vehicle

### 2. Road
**Rendered as:**
```
║                                ║
║                                ║
║          ----  ----            ║ ← White dashed
║          ----  ----            ║   center line
║          ----  ----            ║
║                                ║
║                                ║
```

**Implementation:**
- Dark gray rectangle (0xFF404040)
- 200px wide
- White solid edge lines (3px width)
- White dashed center line (20px dash, 15px gap)
- Extends vertically for scrolling

### 3. Background

**Sky:**
```
════════════════════════════
 Light Blue (#87CEEB)
                            ← Linear gradient
 Lighter Blue (#E0F6FF)
════════════════════════════
```

**Buildings:**
```
Left Side:        Right Side:
┌──────┐          ┌──────┐
│      │          │      │
│ Gray │          │ Gray │
│      │          │      │
└──────┘          └──────┘
```

**Implementation:**
- Sky: Linear gradient from top (sky blue) to bottom (lighter)
- Buildings: Simple gray rectangles (60px × 150px)
- 5 buildings on each side
- Spaced 180px apart vertically
- Creates parallax depth illusion

### 4. HUD Elements

**Top Bar:**
```
┌─────────────────────────────────────┐
│ [Level 1]        [💰 100]    [⏸]  │
│  Black bg       Black bg    Pause  │
└─────────────────────────────────────┘
```

**Bottom Instruction:**
```
┌─────────────────────────────────────┐
│      TAP & HOLD TO DRIVE            │
│        (White on Black)             │
└─────────────────────────────────────┘
```

**Implementation:**
- Semi-transparent black backgrounds (54% opacity)
- White text for contrast
- Yellow coin icon
- Material Design icons
- Rounded corners (20px radius)

## Color Palette

### Game Colors
```
Player Vehicle:    #FFEB3B (Yellow)
Road Surface:      #404040 (Dark Gray)
Lane Markings:     #FFFFFF (White)
Sky (Top):         #87CEEB (Sky Blue)
Sky (Bottom):      #E0F6FF (Light Blue)
Buildings:         #616161 (Medium Gray)
Vehicle Windows:   #000000 30% opacity
Wheels:            #000000 (Black)
```

### UI Colors
```
HUD Background:    #000000 54% opacity
HUD Text:          #FFFFFF (White)
Coin Color:        #FFD700 (Gold)
Button Primary:    #FFEB3B (Yellow)
Button Text:       #000000 (Black)
Success Green:     #388E3C
Error Red:         #D32F2F
```

## Screen Examples

### Main Menu
```
┌────────────────────────────────────┐
│                                    │
│         TAXI GAME                  │
│      (Large White Text)            │
│                                    │
│    ⭐ Level 1                      │
│    💰 100 Coins                    │
│                                    │
│    ┌─────────────────┐             │
│    │  ▶  PLAY        │  Yellow     │
│    └─────────────────┘   Button    │
│                                    │
│    ┌─────────────────┐             │
│    │  🚗 GARAGE      │  Yellow     │
│    └─────────────────┘   Button    │
│                                    │
│    ┌─────────────────┐             │
│    │  ⚙  SETTINGS    │  Yellow     │
│    └─────────────────┘   Button    │
│                                    │
└────────────────────────────────────┘
```

### Game Screen
```
┌────────────────────────────────────┐
│ [Lvl 1]  [💰 100]           [⏸]  │ ← HUD Top
│                                    │
│        Sky Gradient                │
│                                    │
│  [Bld]     Road        [Bld]      │
│            ║                       │
│          ──║──                     │
│            ║                       │
│         [🚕]  ← Taxi               │
│            ║                       │
│          ──║──                     │
│            ║                       │
│                                    │
│                                    │
│   ┌──────────────────────┐         │
│   │ TAP & HOLD TO DRIVE  │         │ ← HUD Bottom
│   └──────────────────────┘         │
└────────────────────────────────────┘
```

### Level Complete Overlay
```
┌────────────────────────────────────┐
│                                    │
│         ┌─────────────┐             │
│         │             │             │
│         │     ✓       │  Green     │
│         │             │  Background │
│         │  LEVEL      │             │
│         │ COMPLETE!   │             │
│         │             │             │
│         │  +50 Coins  │  Yellow    │
│         │   (Gold)    │  Text      │
│         │             │             │
│         │ ┌─────────┐ │             │
│         │ │  NEXT   │ │  White     │
│         │ │  LEVEL  │ │  Button    │
│         │ └─────────┘ │             │
│         └─────────────┘             │
│                                    │
└────────────────────────────────────┘
```

### Level Failed Overlay
```
┌────────────────────────────────────┐
│                                    │
│         ┌─────────────┐             │
│         │             │             │
│         │     ✗       │  Red       │
│         │             │  Background │
│         │   CRASH!    │             │
│         │             │             │
│         │             │             │
│         │ ┌─────────┐ │             │
│         │ │  RETRY  │ │  White     │
│         │ └─────────┘ │  Button    │
│         │             │             │
│         │ MAIN MENU   │  White     │
│         │  (text)     │  Link      │
│         └─────────────┘             │
│                                    │
└────────────────────────────────────┘
```

## Animation Notes

### Current Animations
1. **Vehicle Movement:** Position updates at 60 FPS
2. **Smooth Scrolling:** Background/road scrolls with camera
3. **Button Press:** Scale effect (not yet implemented)
4. **Overlays:** Fade in (not yet implemented)

### Future Animations
- [ ] Wheel rotation when moving
- [ ] Particle effects (smoke, sparkles)
- [ ] Screen shake on collision
- [ ] Coin collection animation
- [ ] Vehicle bounce on stop
- [ ] Menu transitions

## Comparison: Current vs. Future

### Current (Phase 1)
- ✅ Functional
- ✅ Clear and readable
- ✅ Fast to render
- ✅ No external dependencies
- ⚠️ Very basic appearance
- ⚠️ Placeholder quality

### Future (Phase 3+)
- 🎨 Professional sprite artwork
- 🎨 Detailed vehicle models
- 🎨 Textured environments
- 🎨 Particle effects
- 🎨 Animated elements
- 🎨 Polished UI graphics

## Asset Replacement Strategy

When professional assets are ready:

1. **Vehicle Sprites:**
   - Replace `PlayerVehicle.render()` Canvas drawing
   - Load SVG or PNG sprite
   - Same hitbox dimensions (maintain gameplay)

2. **Environment:**
   - Replace `Background.render()` with sprite layers
   - Add parallax scrolling logic
   - Multiple building/tree variations

3. **Road:**
   - Replace `RoadSegment.render()` with textured sprite
   - Keep lane marking logic
   - Add wear/detail textures

4. **UI:**
   - Replace button backgrounds
   - Add custom fonts
   - Animated icons

## Benefits of Current Approach

✅ **No Blocking:**
- Can develop full gameplay without art
- Test mechanics immediately
- Iterate on game feel

✅ **Performance:**
- Very fast rendering
- Small memory footprint
- Smooth 60 FPS

✅ **Flexibility:**
- Easy to adjust sizes/colors
- Quick to iterate
- No asset pipeline delays

✅ **Clarity:**
- Everything is visible and clear
- No visual noise
- Focus on gameplay

## Summary

The current geometric implementation provides:
- A fully functional game
- Clear, readable visuals
- Good performance
- No external dependencies
- Easy to replace later

It allows development to proceed at full speed while professional assets are created or sourced separately.

---

**Visual Status:** Functional placeholders ✅
**Next Visual Phase:** Professional sprites (Phase 3)
**Blocking Status:** Non-blocking - can proceed with all gameplay development

