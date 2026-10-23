#!/usr/bin/env python3
"""Composite built-in image-generation expressions onto the shipped Rin sprites.

Requires Pillow. No network/API calls. Existing output files are never replaced.
Usage:
  python3 scripts/prepare_rin_expression_art.py --manifest /path/to/inputs.json
  python3 scripts/prepare_rin_expression_art.py --verify-only

The JSON manifest maps surface numbers to generated PNG paths. An entry may also
be {"path": "...", "offset": [dx, dy]} for translation after resizing. Sources
are full-canvas edits of surface0 (3..8) or surface10 (11..13), made with the
built-in imagegen tool, transparent background, original identity/pose/colors.
Prompts: 3 blush/averted gaze/closed lips; 4 wide eyes/small open mouth;
5 worried brows/watery eyes/downturned mouth; 6 cute angry brows/puffed cheeks;
7 half-open sleepy eyes/tiny open mouth; 8 confident eyes/cheeky grin;
11 peacefully closed eyes/tiny mouth; 12 round eyes/open mouth;
13 smiling narrowed eyes/happy mouth. No added objects, symbols or writing.

Like prepare_rin_generated_art.py, blend only feathered facial patches and copy
the original alpha. Unlike the original packager, resize BEFORE compositing so
resampling cannot change even invisible RGB outside the approved face mask.
"""

import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SHELL = ROOT / "DefaultGhost/sakura/shell/master"
INDICES = (3, 4, 5, 6, 7, 8, 11, 12, 13)
# (center x, center y, radius x, radius y), in final sprite coordinates.
# Separate islands protect the intervening bangs, chin and face outline.
RIN_PATCHES = (
    (114.5, 55.0, 9.0, 7.0), (138.0, 53.0, 8.5, 7.0),
    (114.0, 47.5, 4.5, 3.5), (135.5, 46.0, 4.5, 3.0),
    (114.5, 62.5, 5.5, 3.5), (140.0, 61.0, 4.5, 3.5),
    (128.0, 69.0, 7.0, 4.0),
)
BELL_PATCHES = (
    (62.0, 69.0, 20.0, 19.0), (119.0, 69.0, 20.0, 19.0),
    (63.0, 52.0, 10.0, 7.0), (116.0, 52.0, 10.0, 7.0),
    (90.0, 81.0, 13.0, 10.0),
)
# Visible facial interior, traced on surface0 at final resolution. This clips
# the eye/brow islands away from the tips of the bangs and the cheek outline.
RIN_INTERIOR = (
    (108, 50), (111, 45), (114, 43), (116, 45), (117, 48),
    (119, 51), (122, 54), (129, 55), (131, 53), (131, 45),
    (134, 44), (139, 47), (143, 49), (146, 52), (145, 57),
    (143, 61), (141, 65), (137, 69), (133, 72), (128, 74),
    (120, 71), (115, 68), (111, 64), (109, 60), (107, 56),
)


def pixels(image):
    getter = getattr(image, "get_flattened_data", None)
    return getter() if getter else image.getdata()


def face_mask(base, bell=False):
    """Compact-support feather: exactly zero outside these facial ellipses."""
    mask = Image.new("L", base.size)
    for cx, cy, rx, ry in BELL_PATCHES if bell else RIN_PATCHES:
        for y in range(math.floor(cy - ry), math.ceil(cy + ry) + 1):
            for x in range(math.floor(cx - rx), math.ceil(cx + rx) + 1):
                radius = math.hypot((x - cx) / rx, (y - cy) / ry)
                value = round(255 * max(0, min(1, (1 - radius) / 0.20)))
                mask.putpixel((x, y), max(mask.getpixel((x, y)), value))
    if not bell:
        interior = Image.new("L", base.size)
        ImageDraw.Draw(interior).polygon(RIN_INTERIOR, fill=255)
        mask = ImageChops.darker(mask, interior)
    return mask


def verify(base, result, mask, label):
    if result.mode != "RGBA" or result.size != base.size:
        raise ValueError(f"{label}: unexpected mode/size")
    outside = alpha = changed = 0
    for old, new, coverage in zip(pixels(base), pixels(result), pixels(mask)):
        outside += coverage == 0 and old != new
        alpha += old[3] != new[3]
        changed += old != new
    if outside or alpha or not changed:
        raise ValueError(f"{label}: outside={outside}, alpha={alpha}, changed={changed}")
    bbox = ImageChops.difference(base.convert("RGB"), result.convert("RGB")).getbbox()
    print(f"{label}: {result.width}x{result.height} RGBA; "
          f"outside_mask={outside}, alpha_changes={alpha}, "
          f"changed_pixels={changed}, difference_bbox={bbox}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--output-dir", type=Path, default=SHELL)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    if not args.verify_only and not args.manifest:
        parser.error("--manifest is required unless --verify-only is used")
    manifest = {} if args.verify_only else json.loads(args.manifest.read_text())
    outputs = [args.output_dir / f"surface{i}.png" for i in INDICES]
    if not args.verify_only:
        existing = [str(p) for p in outputs if p.exists()]
        if existing:
            parser.error("Refusing to overwrite: " + ", ".join(existing))
    prepared = []
    for index, path in zip(INDICES, outputs):
        bell = index >= 11
        with Image.open(SHELL / f"surface{10 if bell else 0}.png") as source:
            base = source.copy()
        if base.mode != "RGBA" or base.size != ((180, 180) if bell else (250, 480)):
            raise ValueError("Unexpected reference sprite")
        mask = face_mask(base, bell)
        if args.verify_only:
            with Image.open(path) as saved:
                verify(base, saved, mask, path.name)
            continue
        item = manifest[str(index)]
        if isinstance(item, str):
            item = {"path": item}
        with Image.open(item["path"]) as source:
            if source.mode != "RGBA":
                raise ValueError(f"{index}: generated source must be RGBA")
            edited = source.resize(base.size, Image.Resampling.LANCZOS)
        dx, dy = item.get("offset", (0, 0))
        if dx or dy:
            edited = edited.transform(base.size, Image.Transform.AFFINE,
                                      (1, 0, -dx, 0, 1, -dy), Image.Resampling.BICUBIC)
        # Do not mix a transparent generated pixel into opaque facial skin.
        for a, coverage in zip(pixels(edited.getchannel("A")), pixels(mask)):
            if coverage and a < 240:
                raise ValueError(f"{index}: transparent source inside facial patch")
        result = Image.composite(edited, base, mask)
        result.putalpha(base.getchannel("A"))
        verify(base, result, mask, path.name)
        prepared.append((path, base, result, mask))
    if prepared:
        args.output_dir.mkdir(parents=True, exist_ok=True)
    for path, base, result, mask in prepared:
        with path.open("xb") as destination:
            result.save(destination, format="PNG", optimize=True)
        with Image.open(path) as saved:
            verify(base, saved, mask, f"saved {path.name}")


if __name__ == "__main__":
    main()
