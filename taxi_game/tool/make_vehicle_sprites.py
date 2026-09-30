# Regenerates the fifteen bundled vehicle sprites (issue #47) as top-down
# art facing up the screen — nose at the top, the direction every vehicle
# travels in game — from Kenney's Racing Pack.
#
# Why a script at all: five of the fifteen cars ship in body colours the
# pack does not offer (gray, white), the bus is an elongated van, and every
# canvas must carry the exact proportions of its logical vehicle box so the
# stretch render in PlayerVehicle/TrafficVehicle/GhostCar stays undistorted.
# The transform is fully deterministic — no random elements, no resampling:
# bodies are copied pixel-for-pixel, recolours are exact palette swaps, and
# the only geometry change is transparent padding plus the bus's duplicated
# roof band. Run twice, get byte-identical PNGs.
#
# Usage (from taxi_game/):
#   python tool/make_vehicle_sprites.py <path-to-kenney_racing-pack.zip>
#
# The zip is downloaded from https://kenney.nl/assets/racing-pack (CC0) and
# is not committed; the generated PNGs under assets/images/vehicles/ are.
# The transformation each output file receives is recorded beside it below
# and mirrored in assets/licenses/LICENSES.txt.

import argparse
import colorsys
import io
import sys
import zipfile

from PIL import Image

# Body ramps the pack does not sell. Each triple is the same three-step
# shading the Kenney bodies use (body / mid / dark — the pack's biggest
# body area is its brightest step), chosen to keep the white body distinct
# from the (255,255,255) window glass and the gray body distinct from the
# near-black tyres and trim.
RAMPS = {
    'white': ((226, 230, 235), (204, 209, 216), (158, 164, 173)),
    'gray': ((152, 158, 165), (128, 134, 142), (84, 90, 97)),
}

# Recolouring only ever starts from a yellow body, so one hue window covers
# every recolour. Glass, tyres, trim and shadows are neutral or another hue
# and pass through untouched; semi-transparent edge pixels keep their alpha.
_YELLOW_HUE_LO = 30.0 / 360.0
_YELLOW_HUE_HI = 70.0 / 360.0


def is_yellow_body(r, g, b):
    """True for pixels of the yellow body family (any of its shade steps)."""
    h, s, _v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
    return s >= 0.25 and _YELLOW_HUE_LO <= h <= _YELLOW_HUE_HI


def recolor_yellow(im, ramp):
    """Swap a yellow body for [ramp], preserving the three shade steps and
    every pixel's alpha. All other colours (glass, tyres, trim) are copied."""
    body, mid, dark = ramp
    out = Image.new('RGBA', im.size)
    src, dst = im.load(), out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = src[x, y]
            if a > 0 and is_yellow_body(r, g, b):
                # Bucket by HSV value, matching how the pack shades its
                # bodies: the brightest step is the body itself, the middle
                # step is the shaded flank, the darkest is outline shadow.
                # Anti-aliased in-betweens snap to the nearest step.
                _h, _s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
                if v >= 0.95:
                    rgb = body
                elif v >= 0.75:
                    rgb = mid
                else:
                    rgb = dark
                dst[x, y] = (*rgb, a)
            else:
                dst[x, y] = (r, g, b, a)
    return out


def elongate(im, extra_rows):
    """Stretch a body vertically by duplicating a band of plain roof rows —
    how the bus is built from the van. The band is the longest run of rows
    containing nothing but body-colour and transparent pixels, so no window
    or shadow is ever cloned; [extra_rows] tiled copies of it are inserted
    at the run's centre."""
    clean = []
    for y in range(im.height):
        ok = True
        for x in range(im.width):
            r, g, b, a = im.load()[x, y]
            if a > 0 and not is_yellow_body(r, g, b):
                ok = False
                break
        clean.append(ok)
    # The longest run of clean rows is the plain roof band to duplicate.
    best_start, best_len, i = 0, 0, 0
    while i < len(clean):
        if clean[i]:
            j = i
            while j < len(clean) and clean[j]:
                j += 1
            if j - i > best_len:
                best_start, best_len = i, j - i
            i = j
        else:
            i += 1
    if best_len == 0:
        raise SystemExit('elongate: no plain body-colour band found to copy')
    band = im.crop((0, best_start, im.width, best_start + best_len))
    at = best_start + best_len // 2
    out = Image.new('RGBA', (im.width, im.height + extra_rows))
    out.paste(im.crop((0, 0, im.width, at)), (0, 0))
    for k in range(extra_rows):
        out.paste(band.crop((0, k % best_len, im.width, k % best_len + 1)),
                  (0, at + k))
    out.paste(im.crop((0, at, im.width, im.height)), (0, at + extra_rows))
    return out


def build(source, box_aspect, ramp=None, extra_rows=0):
    """Load a Racing Pack PNG and turn it into a shipped sprite: optional
    recolour, optional elongation, then transparent side padding until the
    canvas carries [box_aspect] (width/height). The body is never resampled
    and never cropped; it fills the canvas height exactly, so stretching the
    canvas over the logical vehicle box renders the body undistorted."""
    im = source.convert('RGBA')
    if ramp is not None:
        im = recolor_yellow(im, RAMPS[ramp])
    if extra_rows:
        im = elongate(im, extra_rows)
    im = im.crop(im.getbbox())  # normalise any transparent margin first
    w, h = im.size
    if box_aspect is None:
        return im
    canvas_w = int(h * box_aspect + 0.5)
    if canvas_w < w:
        raise SystemExit(f'body wider ({w}) than its box aspect allows '
                         f'({canvas_w}); refusing to crop art')
    out = Image.new('RGBA', (canvas_w, h), (0, 0, 0, 0))
    out.paste(im, ((canvas_w - w) // 2, 0))
    return out


# What each shipped PNG is made of. source: file inside the pack; box:
# (w, h) of the logical vehicle box the sprite is stretched over (None for
# the three traffic files no TrafficVehicleType maps to — they mirror a
# sibling's geometry purely for visual consistency in the folder); ramp and
# extra_rows: recolour / elongation, recorded in LICENSES.txt.
SPEC = [
    # player fleet (boxes from lib/data/vehicle_catalog.dart)
    ('player/taxi_yellow.png', 'PNG/Cars/car_yellow_1.png', (40, 60), None, 0),
    ('player/compact_red.png', 'PNG/Cars/car_red_2.png', (34, 50), None, 0),
    ('player/sedan_blue.png', 'PNG/Cars/car_blue_1.png', (40, 62), None, 0),
    ('player/minivan_gray.png', 'PNG/Cars/car_yellow_5.png', (48, 72), 'gray', 0),
    ('player/sports_black.png', 'PNG/Cars/car_black_3.png', (36, 56), None, 0),
    ('player/suv_green.png', 'PNG/Cars/car_green_5.png', (46, 70), None, 0),
    ('player/luxury_white.png', 'PNG/Cars/car_yellow_1.png', (46, 76), 'white', 0),
    # traffic fleet (boxes from lib/models/traffic_pattern.dart)
    ('traffic/sedan_gray.png', 'PNG/Cars/car_yellow_1.png', (40, 60), 'gray', 0),
    ('traffic/truck_red.png', 'PNG/Cars/car_red_4.png', (45, 80), None, 0),
    ('traffic/sports_red.png', 'PNG/Cars/car_red_3.png', (38, 55), None, 0),
    ('traffic/suv_blue.png', 'PNG/Cars/car_blue_5.png', (42, 70), None, 0),
    # The bus: the pack has no bus, so the van body is elongated to the
    # 50x100 box by duplicating plain roof rows (CC0 permits the derivative).
    ('traffic/bus_yellow.png', 'PNG/Cars/car_yellow_5.png', (50, 100), None, 29),
    # Not referenced by trafficSpritePath; kept top-down for folder consistency.
    ('traffic/compact_white.png', 'PNG/Cars/car_yellow_2.png', (34, 50), 'white', 0),
    ('traffic/van_white.png', 'PNG/Cars/car_yellow_5.png', (48, 72), 'white', 0),
    ('traffic/motorcycle_black.png', 'PNG/Motorcycles/motorcycle_black.png',
     None, None, 0),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('zip', help='path to the downloaded kenney_racing-pack.zip')
    ap.add_argument('--out', default='assets/images/vehicles',
                    help='output folder (default: assets/images/vehicles)')
    args = ap.parse_args()

    zf = zipfile.ZipFile(args.zip)
    for rel, src, box, ramp, extra in SPEC:
        source = Image.open(io.BytesIO(zf.read(src)))
        sprite = build(source,
                       None if box is None else box[0] / box[1],
                       ramp, extra)
        path = f'{args.out}/{rel}'
        sprite.save(path, optimize=True)
        print(f'{rel}: {sprite.width}x{sprite.height}'
              f'{" (recolour " + ramp + ")" if ramp else ""}'
              f'{" (+%d rows)" % extra if extra else ""}')


if __name__ == '__main__':
    sys.exit(main())
