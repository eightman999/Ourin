#!/usr/bin/env python3
"""標準ゴースト用の簡易バルーン画像と descript.txt を生成する（Pillow 使用）。"""
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "DefaultGhost/sakura/balloon"
SS = 3  # スーパーサンプリング

def bubble(w, h, border, fill=(255, 252, 250), tint=(255, 226, 232)):
    img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = 14 * SS
    d.rounded_rectangle([2 * SS, 2 * SS, w * SS - 2 * SS, h * SS - 2 * SS], r, fill=fill, outline=border, width=3 * SS)
    return img.resize((w, h), Image.LANCZOS)

def arrow(up):
    w, h = 14, 10
    img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pts = [(1, 8), (13, 8), (7, 1)] if up else [(1, 1), (13, 1), (7, 8)]
    d.polygon([(x * SS, y * SS) for x, y in pts], fill=(214, 120, 140, 255))
    return img.resize((w, h), Image.LANCZOS)

OUT.mkdir(parents=True, exist_ok=True)
bubble(335, 169, (232, 150, 170, 255)).save(OUT / "balloons0.png")                       # さくら
bubble(335, 169, (92, 110, 168, 255), tint=(205, 214, 240)).save(OUT / "balloonk0.png")   # りんね
bubble(400, 63, (232, 150, 170, 255)).save(OUT / "balloonc0.png")                         # 入力用
arrow(True).save(OUT / "arrow0.png")
arrow(False).save(OUT / "arrow1.png")
(OUT / "descript.txt").write_text("""charset,UTF-8
type,balloon
name,Ourin Default Balloon
craftman,Ourin

origin.x,20
origin.y,14
wordwrappoint.x,-24
wordwrappoint.y,0
validrect.left,0
validrect.top,0
validrect.right,0
validrect.bottom,-14

font.height,12
font.color.r,90
font.color.g,50
font.color.b,60
anchor.font.color.r,190
anchor.font.color.g,60
anchor.font.color.b,90
cursor.blendmethod,none
cursor.style,square
cursor.brush.color.r,232
cursor.brush.color.g,150
cursor.brush.color.b,170
cursor.pen.color.r,200
cursor.pen.color.g,110
cursor.pen.color.b,135
cursor.font.color.r,255
cursor.font.color.g,255
cursor.font.color.b,255

arrow0.x,310
arrow0.y,8
arrow1.x,310
arrow1.y,-20
""", encoding="utf-8")
print("balloon generated:", OUT)
