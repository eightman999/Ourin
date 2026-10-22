#!/usr/bin/env python3
"""Rin 標準ゴーストのプレースホルダ立ち絵を生成する（標準ライブラリのみ）。
本絵ができたら DefaultGhost/rin/shell/master/surface*.png を差し替えればよい。"""
import math, struct, sys, zlib
from pathlib import Path

def png(path, w, h, pix):
    raw = b''.join(b'\x00' + bytes(sum(([*pix[y*w+x]] for x in range(w)), [])) for y in range(h))
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    Path(path).write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

def canvas(w, h): return [(0, 0, 0, 0)] * (w * h)

def blend(px, w, h, x, y, c, a):
    if 0 <= x < w and 0 <= y < h and a > 0:
        pa = px[y*w+x][3] / 255
        na = a + pa * (1 - a)
        if na <= 0: return
        px[y*w+x] = tuple(int((c[i]*a + px[y*w+x][i]*pa*(1-a)) / na) for i in range(3)) + (int(na*255),)

def ell(px, w, h, cx, cy, rx, ry, c):
    for y in range(int(cy-ry-1), int(cy+ry+2)):
        for x in range(int(cx-rx-1), int(cx+rx+2)):
            d = math.hypot((x-cx)/rx, (y-cy)/ry)
            blend(px, w, h, x, y, c, max(0.0, min(1.0, (1-d) * min(rx, ry) / 1.5)))

def rin(smile=False):
    w, h = 220, 360; px = canvas(w, h)
    ell(px,w,h,110,300,60,48,(255,196,214,255))   # skirt/body
    ell(px,w,h,110,240,40,50,(255,224,232,255))
    ell(px,w,h,110,120,78,84,(88,58,72,255))      # hair back
    ell(px,w,h,110,130,62,68,(255,236,224,255))   # face
    ell(px,w,h,110,78,70,34,(88,58,72,255))       # bangs
    for ex in (88, 132):
        if smile: ell(px,w,h,ex,138,9,4,(60,40,50,255))
        else: ell(px,w,h,ex,138,7,10,(60,40,50,255))
    ell(px,w,h,110,168,8,3,(220,120,130,255))     # mouth
    ell(px,w,h,110,210,9,9,(255,200,60,255))      # 鈴
    return w, h, px

def bell():
    w, h = 140, 180; px = canvas(w, h)
    ell(px,w,h,70,110,48,56,(255,214,120,255)); ell(px,w,h,70,118,38,42,(255,240,200,255))
    ell(px,w,h,40,60,12,18,(255,214,120,255)); ell(px,w,h,100,60,12,18,(255,214,120,255))
    for ex in (54, 86): ell(px,w,h,ex,104,5,7,(60,40,50,255))
    ell(px,w,h,70,124,6,3,(200,110,100,255))
    return w, h, px

out = Path(sys.argv[1] if len(sys.argv) > 1 else 'DefaultGhost/rin/shell/master')
for name, (w, h, px) in {'surface0.png': rin(), 'surface1.png': rin(True), 'surface10.png': bell()}.items():
    png(out / name, w, h, px)
w, h, px = rin(); png(out.parent.parent / 'thumbnail.png', w, h, px)
