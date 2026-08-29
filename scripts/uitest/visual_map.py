#!/usr/bin/env python3
"""Locate MindFlow node capsules visually in a full-screen capture.

Usage: python3 visual_map.py /tmp/full.png
Prints bounding boxes of colored node capsules in SCREEN POINTS
(pixel/2 on retina), sorted by y. Pure stdlib (zlib PNG decode).
"""
import struct
import sys
import zlib


def decode_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    pos = 8
    idat = b''
    w = h = None
    ctype = None
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        if typ == b'IHDR':
            w, h, _, ctype = struct.unpack('>IIBB', chunk[:10])
        elif typ == b'IDAT':
            idat += chunk
        elif typ == b'IEND':
            break
        pos += 12 + ln
    raw = zlib.decompress(idat)
    ch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    stride = w * ch
    out = bytearray(w * h * ch)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        f = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if f == 1:
            for i in range(ch, stride):
                line[i] = (line[i] + line[i - ch]) & 255
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) // 2)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                b = prev[i]
                c = prev[i - ch] if i >= ch else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, ch, out


def main():
    path = sys.argv[1]
    w, h, ch, px = decode_png(path)

    def pix(x, y):
        o = (y * w + x) * ch
        return px[o], px[o + 1], px[o + 2]

    # Detect "colored" (saturated) pixels = node capsules / branch borders.
    # Sample every 4px for speed.
    step = 4
    mask = {}
    for y in range(0, h, step):
        for x in range(0, w, step):
            r, g, b = pix(x, y)[:3]
            mx, mn = max(r, g, b), min(r, g, b)
            if mx - mn > 40 and mx > 90:  # saturated
                mask[(x, y)] = True

    # Cluster via simple grid flood (union of nearby samples).
    seen = set()
    boxes = []
    pts = set(mask)
    for p in list(pts):
        if p in seen:
            continue
        stack = [p]
        seen.add(p)
        minx = maxx = p[0]
        miny = maxy = p[1]
        count = 0
        while stack:
            cx, cy = stack.pop()
            count += 1
            minx, maxx = min(minx, cx), max(maxx, cx)
            miny, maxy = min(miny, cy), max(maxy, cy)
            for dx in (-step * 3, 0, step * 3):
                for dy in (-step * 3, 0, step * 3):
                    q = (cx + dx, cy + dy)
                    if q in pts and q not in seen:
                        seen.add(q)
                        stack.append(q)
        if count >= 8:  # ignore specks
            # points = pixels / 2 (retina)
            boxes.append((minx // 2, miny // 2, (maxx - minx) // 2, (maxy - miny) // 2, count))
    boxes.sort(key=lambda b: (b[1], b[0]))
    for b in boxes:
        print(f'VIS x={b[0]} y={b[1]} w={b[2]} h={b[3]} density={b[4]}')


if __name__ == '__main__':
    main()
