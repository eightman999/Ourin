#!/usr/bin/env python3
"""Package Rinne's built-in imagegen artwork; Pillow only, no API calls.

Usage:
  python3 scripts/prepare_rinne_generated_art.py --manifest inputs.json
  python3 scripts/prepare_rinne_generated_art.py --verify-only

Manifest: keys "100" through "108", values PNG paths or objects containing
"path", optional "mirror" (bool), and optional "offset" ([dx, dy], final pixels).
100 is the normal master; the others are full-body expression edits of the
normalized 250x480 master. Mirror the original normal master before generating
edits to put the bell on the character's right (viewer's left).

Built-in generation prompt: new male Rinne, calm young older-brother companion;
Sakura surface0 as STYLE reference only; short navy hair with pale sakura-pink
tips, small silver bell on his right, indigo/ivory haori jacket with sakura
embroidery, loose hakama trousers, silver waist bell, lace-up boots. Fine-line
soft anime cel shading, flat colors/subtle gradients, front full body, lowered
arms, transparent background, no floor/shadow/text/border. Expression edits:
101 peaceful closed-eye smile; 102 neutral fully closed eyes, unchanged mouth;
103 blush/averted gaze; 104 wide surprised eyes/open O mouth;
105 worried brows/downturned mouth; 106 cute angry brows/tiny pout;
107 half-open heavy eyelids/parted mouth; 108 confident eyes/asymmetric smirk.
Keep identity, head, hair, pose, clothing and framing unchanged in all prompts.

Resize BEFORE compositing, blend only compact facial islands clipped to the
visible skin interior, then restore the entire original alpha channel. No
resampling after compositing. Verify all four channels, including invisible
RGB, outside the mask. All destinations are exclusive-create (no overwrite).
Coordinates are specific to this selected Rinne master, not arbitrary art.
"""

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "DefaultGhost/sakura/shell/master"
SIZE = (250, 480)
INDICES = tuple(range(100, 109))
# Eye/brow/cheek/mouth islands, in final-canvas coordinates.
PATCHES = (
    (116, 45, 7, 6), (135, 46, 7, 6),
    (118, 40, 5, 3.5), (135, 41, 6, 4),
    (115, 52, 6, 5), (136, 53, 6, 5),
    (125, 60.5, 8, 4.5),
)
# Trace the skin, excluding bangs, face outline, chin, ears and neck.
FACE_INTERIOR = (
    (111, 44), (114, 41), (117, 41), (119, 40), (121, 36),
    (121, 40), (120, 44), (119, 48), (123, 47), (125, 45),
    (127, 44), (129, 41), (131, 39), (132, 35), (133, 37),
    (134, 40), (137, 41), (139, 43), (139, 48), (137, 52),
    (137, 55), (134, 60), (129, 64), (125, 66), (120, 63),
    (116, 60), (113, 56), (111, 51),
)


def pixels(image):
    getter = getattr(image, "get_flattened_data", None)
    return getter() if getter else image.getdata()


def face_mask(blink=False):
    mask = Image.new("L", SIZE)
    # Neutral blink retains the original mouth, cheeks and eyebrows.
    for cx, cy, rx, ry in PATCHES[:2] if blink else PATCHES:
        feather = 0.55 if cy in (52, 53) else 0.20
        for y in range(math.floor(cy - ry), math.ceil(cy + ry) + 1):
            for x in range(math.floor(cx - rx), math.ceil(cx + rx) + 1):
                radius = math.hypot((x - cx) / rx, (y - cy) / ry)
                value = round(255 * max(0, min(1, (1 - radius) / feather)))
                mask.putpixel((x, y), max(mask.getpixel((x, y)), value))
    interior = Image.new("L", SIZE)
    ImageDraw.Draw(interior).polygon(FACE_INTERIOR, fill=255)
    return ImageChops.darker(mask, interior)


def load_source(item):
    if isinstance(item, str):
        item = {"path": item}
    with Image.open(item["path"]) as source:
        if source.mode != "RGBA":
            raise ValueError(f"Source must be RGBA: {item['path']}")
        result = source.copy()
    if item.get("mirror", False):
        result = ImageOps.mirror(result)
    result = result.resize(SIZE, Image.Resampling.LANCZOS)
    dx, dy = item.get("offset", (0, 0))
    if dx or dy:
        result = result.transform(SIZE, Image.Transform.AFFINE,
                                  (1, 0, -dx, 0, 1, -dy), Image.Resampling.BICUBIC)
    return result


def verify_format(image, label):
    if image.mode != "RGBA" or image.size != SIZE:
        raise ValueError(f"{label}: expected 250x480 RGBA")
    if image.getchannel("A").getextrema() != (0, 255):
        raise ValueError(f"{label}: expected transparent and opaque pixels")
    for corner in ((0, 0), (249, 0), (0, 479), (249, 479)):
        if image.getpixel(corner)[3]:
            raise ValueError(f"{label}: nontransparent canvas corner")


def verify(base, result, index):
    label = f"surface{index}.png"
    verify_format(result, label)
    if index == 100:
        print(f"{label}: 250x480 RGBA; alpha=0..255")
        return
    mask = face_mask(blink=index == 102)
    outside = alpha = changed = 0
    for old, new, coverage in zip(pixels(base), pixels(result), pixels(mask)):
        outside += coverage == 0 and old != new
        alpha += old[3] != new[3]
        changed += old != new
    if outside or alpha or not changed:
        raise ValueError(f"{label}: outside={outside}, alpha={alpha}, changed={changed}")
    bbox = ImageChops.difference(base.convert("RGB"), result.convert("RGB")).getbbox()
    print(f"{label}: outside_mask={outside}; alpha_changes={alpha}; "
          f"changed_pixels={changed}; difference_bbox={bbox}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--output-dir", type=Path, default=SHELL)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    outputs = {i: args.output_dir / f"surface{i}.png" for i in INDICES}
    if args.verify_only:
        with Image.open(outputs[100]) as source:
            base = source.copy()
        for index, path in outputs.items():
            with Image.open(path) as saved:
                verify(base, saved, index)
        return
    if not args.manifest:
        parser.error("--manifest is required unless --verify-only is used")
    existing = [str(p) for p in outputs.values() if p.exists()]
    if existing:
        parser.error("Refusing to overwrite: " + ", ".join(existing))
    manifest = json.loads(args.manifest.read_text())
    base = load_source(manifest["100"])
    # Same near-zero-alpha fringe cleanup as the existing Sakura packager.
    base.putdata([(0, 0, 0, 0) if rgba[3] <= 3 else rgba for rgba in pixels(base)])
    verify_format(base, "normal master")
    prepared = {100: base}
    for index in INDICES[1:]:
        edited = load_source(manifest[str(index)])
        mask = face_mask(blink=index == 102)
        if any(a < 240 and coverage for a, coverage
               in zip(pixels(edited.getchannel("A")), pixels(mask))):
            raise ValueError(f"{index}: transparent source inside facial patch")
        result = Image.composite(edited, base, mask)
        result.putalpha(base.getchannel("A"))
        verify(base, result, index)
        prepared[index] = result
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for index, result in prepared.items():
        with outputs[index].open("xb") as destination:
            result.save(destination, format="PNG", optimize=True)
        with Image.open(outputs[index]) as saved:
            verify(base, saved, index)


if __name__ == "__main__":
    main()
