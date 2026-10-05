#!/usr/bin/env python3
"""Render TruckRoute's app icon to a 1024x1024 opaque PNG.

No third-party imaging libraries are available in this environment, so this
writes the PNG itself with zlib from the standard library. Deliberately RGB
with no alpha channel: App Store Connect rejects app icons that carry one.

The mark is a route — three stops joined by two legs, the last one dashed to
match the deadhead styling the app uses everywhere else.
"""
import math
import struct
import zlib

SIZE = 1024

# Pulled to match the app's own palette: iOS systemBlue-ish ground, the same
# orange the route list and map use for empty miles.
BG_TOP = (0x15, 0x2B, 0x47)
BG_BOTTOM = (0x0C, 0x18, 0x28)
LOADED = (0x3F, 0x93, 0xF5)
EMPTY = (0xF2, 0x8C, 0x28)
STOP = (0xFF, 0xFF, 0xFF)

# Geometry in icon space. Apple masks the corners and recommends keeping the
# mark inside the middle ~80%, so nothing here reaches the edge.
STOPS = [(242.0, 682.0), (492.0, 342.0), (782.0, 562.0)]
LEG_WIDTH = 52.0
STOP_OUTER = 86.0
STOP_INNER = 40.0
AA = 1.6  # edge softness in pixels


def segment_distance(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    length_sq = vx * vx + vy * vy
    t = 0.0 if length_sq == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / length_sq))
    dx, dy = wx - t * vx, wy - t * vy
    return math.hypot(dx, dy), t


def coverage(distance, radius):
    """Analytic-ish antialiased coverage for a filled disc/capsule edge."""
    return max(0.0, min(1.0, (radius - distance) / AA + 0.5))


def over(base, layer, alpha):
    if alpha <= 0.0:
        return base
    if alpha >= 1.0:
        return layer
    return tuple(int(round(b + (l - b) * alpha)) for b, l in zip(base, layer))


def dash_mask(t, length, period=64.0, duty=0.55):
    """1 inside a dash, 0 in the gap, with soft edges along the leg."""
    pos = (t * length) % period
    on = period * duty
    if pos <= on:
        return min(1.0, min(pos, on - pos) / AA + 0.5)
    return max(0.0, min(1.0, min(pos - on, period - pos) / AA + 0.5)) * 0.0


def render():
    legs = []
    for index in range(len(STOPS) - 1):
        (ax, ay), (bx, by) = STOPS[index], STOPS[index + 1]
        legs.append((ax, ay, bx, by, math.hypot(bx - ax, by - ay), index == 1))

    rows = []
    for y in range(SIZE):
        py = y + 0.5
        ratio = py / SIZE
        base = tuple(
            int(round(t + (b - t) * ratio)) for t, b in zip(BG_TOP, BG_BOTTOM)
        )
        row = bytearray()
        for x in range(SIZE):
            px = x + 0.5
            color = base

            # Legs first, so the stop markers sit on top of them.
            for ax, ay, bx, by, length, dashed in legs:
                distance, t = segment_distance(px, py, ax, ay, bx, by)
                alpha = coverage(distance, LEG_WIDTH / 2)
                if alpha <= 0.0:
                    continue
                if dashed:
                    alpha *= dash_mask(t, length)
                    color = over(color, EMPTY, alpha)
                else:
                    color = over(color, LOADED, alpha)

            for sx, sy in STOPS:
                distance = math.hypot(px - sx, py - sy)
                if distance > STOP_OUTER + AA:
                    continue
                color = over(color, STOP, coverage(distance, STOP_OUTER))
                # Punch the middle back to the background so each stop reads
                # as a ring rather than a blob at small sizes.
                color = over(color, base, coverage(distance, STOP_INNER))

            row += bytes(color)
        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag, payload):
        body = tag + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    # Tag the colour space explicitly. An untagged icon is interpreted as sRGB
    # anyway, but saying so keeps actool and App Store validation from
    # remarking on it, and costs five bytes.
    png += chunk(b"sRGB", bytes([0]))                      # perceptual intent
    png += chunk(b"gAMA", struct.pack(">I", 45455))        # 1/2.2, per the sRGB spec
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


if __name__ == "__main__":
    import sys

    write_png(sys.argv[1], render())
    print("wrote", sys.argv[1])
