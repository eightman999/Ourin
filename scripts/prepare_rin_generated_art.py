#!/usr/bin/env python3
"""Package AI-generated Rin artwork; no API calls or procedural character drawing.

Usage (from repository root, Python with Pillow):
  python3 scripts/prepare_rin_generated_art.py normal.png smile.png blink.png bell.png

Generation prompt: front-facing full-body Rin; plum-brown bob with sakura-pink
inner hair; small gold bell on her left; pastel pink kimono short dress, white
obi bow and gold bell; lowered arms; fine-line soft anime cel shading; alpha
background. Smile: happy closed eyes and smiling mouth. Blink: relaxed fully
closed eyes, unchanged mouth. Bell: fluffy gold/cream bell-shaped chibi cat,
sleepy eyes, sakura petal on head, red ribbon collar and pink accents.

Face coordinates correspond to the selected 906x1736 normal master. The image
generation edit outputs must preserve that alignment (a one-row height change
at the bottom is tolerated). Original master images are supplied as arguments.
"""
import argparse
import math
from pathlib import Path

from PIL import Image, ImageChops


def expression(base, edited, smile):
    assert base.size == (906, 1736), "Unexpected normal master size"
    assert edited.width == base.width and abs(edited.height - base.height) <= 1
    # Keep the entire original image, changing only feathered eye/mouth areas.
    patches = [(416, 201, 32, 25), (502, 194, 31, 25)]
    if smile:
        patches.append((465, 251, 25, 17))
    mask = Image.new("L", base.size)
    for cx, cy, rx, ry in patches:
        for y in range(cy - ry, cy + ry + 1):
            for x in range(cx - rx, cx + rx + 1):
                radius = math.hypot((x - cx) / rx, (y - cy) / ry)
                mask.putpixel((x, y), round(255 * max(0, min(1, (1 - radius) / 0.18))))
    aligned = Image.new("RGBA", base.size)
    aligned.paste(edited, (0, 0))
    result = Image.composite(aligned, base, mask)
    result.putalpha(base.getchannel("A"))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("normal", "smile", "blink", "bell"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    base, smile, blink, bell = [Image.open(getattr(args, name)).convert("RGBA")
                               for name in ("normal", "smile", "blink", "bell")]
    root = Path("DefaultGhost/rin")
    shell = root / "shell/master"
    resample = Image.Resampling.LANCZOS
    variants = [base, expression(base, smile, True), expression(base, blink, False)]
    surfaces = [im.resize((250, 480), resample) for im in variants]
    outputs = {shell / f"surface{i}.png": im for i, im in enumerate(surfaces)}
    outputs[shell / "surface10.png"] = bell.resize((180, 180), resample)
    outputs[root / "thumbnail.png"] = surfaces[0].resize((125, 240), resample)
    for path, im in outputs.items():
        # Lanczos can amplify meaningless RGB at near-zero alpha. Remove only
        # these invisible fringe pixels, retaining the visible antialiased edge.
        im.putdata([(0, 0, 0, 0) if rgba[3] <= 3 else rgba
                    for rgba in im.get_flattened_data()])
        im.save(path, optimize=True)
        saved = Image.open(path)
        assert saved.mode == "RGBA" and saved.size == im.size
        assert saved.getchannel("A").getextrema() == (0, 255)
        assert saved.getpixel((0, 0))[3] == 0
        # Detect green chroma-key spill in visible pixels, including edges.
        green = sum(a > 0 and g > 150 and g > r + 30 and g > b + 30
                    for r, g, b, a in saved.get_flattened_data())
        assert green == 0, f"Green spill: {path}"
        print(f"{path}: {saved.width}x{saved.height} RGBA, alpha 0..255, green spill=0")
    normal = Image.open(shell / "surface0.png")
    for index in (1, 2):
        other = Image.open(shell / f"surface{index}.png")
        assert ImageChops.difference(normal.getchannel("A"), other.getchannel("A")).getbbox() is None
        bbox = ImageChops.difference(normal.convert("RGB"), other.convert("RGB")).getbbox()
        assert bbox and bbox[0] >= 103 and bbox[1] >= 43 and bbox[2] <= 152 and bbox[3] <= 79
        print(f"surface{index}: identical alpha/body, face-only difference bbox={bbox}")


if __name__ == "__main__":
    main()
