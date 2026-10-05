#!/usr/bin/env python3
"""
boundary.py — sand pit boundary for SandBot.

The pit is kidney-shaped and the arm base sits in the notch. The boundary is a
polygon in arm coordinates (mm, X = left/right, Y = out from the base). Any
point below SAFE_Z must be inside the polygon (shrunk by MARGIN_MM); at or
above SAFE_Z the pen is over the rim and can go anywhere the arm can reach.

Stored in boundary.json next to this file so calibration survives restarts.
"""

import json
import math
import os
import threading

import cv2
import numpy as np

BOUNDARY_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "boundary.json")

# Estimated from photos (30 cm wide, ~18 cm deep at the notch, lobes ~5 cm
# below the notch rim). Replace by calibrating: jog the pen around the rim.
_DEFAULT_HALF = [
    (0, 255), (59, 247), (104, 225), (134, 195), (147, 156), (149, 113),
    (142, 73), (127, 40), (104, 24), (79, 27), (59, 44), (39, 63), (19, 73),
]
DEFAULT_POLYGON = (
    [[-x, y] for x, y in _DEFAULT_HALF]
    + [[0, 75]]
    + [[x, y] for x, y in reversed(_DEFAULT_HALF[1:])]
)

DEFAULT_CONFIG = {
    "polygon": DEFAULT_POLYGON,
    "safe_z": 200.0,       # fallback only: used until the drawing surface Z is known
    "rim_clearance_mm": 15.0,  # crossing the rim: this far above the drawing surface
    "margin_mm": 8.0,      # keep this far inside the rim
    "calibrated": False,
}

SAMPLE_STEP_MM = 2.0
MASK_RES_MM = 0.25   # resolution of the precomputed "safe to draw" lookup map

# Arm geometry, mirrored from the Freenove server (arm.py / Parameter.json).
# The server silently ignores moves it can't reach and detours around an
# 80 mm circle at the base, so the bridge must never plan such a move.
L1 = L2 = 150.0
SHOULDER_HEIGHT = 90.0
BASE_KEEPOUT_MM = 82.0
_LIMIT_A = (26, 150)
_LIMIT_1 = (0, 110)
_LIMIT_2 = (-12, 110)


def reachable(x, y, z):
    """Same joint-limit test the Freenove server applies before a G0."""
    d = math.hypot(x, y)
    zh = z - SHOULDER_HEIGHT
    hyp = math.hypot(d, zh)
    if hyp >= L1 + L2 or hyp == 0:
        return False
    a1 = math.degrees(math.acos(hyp / (2 * L1)))
    a2 = math.degrees(math.atan2(abs(zh), d))
    a3 = a1 + a2 if zh > 0 else a1 - a2
    a5 = 180 - (a3 + (180 - 2 * a1))
    la = 180 - a3 - a5
    return (_LIMIT_A[0] < la < _LIMIT_A[1] and _LIMIT_1[0] < a3 < _LIMIT_1[1]
            and _LIMIT_2[0] < a5 < _LIMIT_2[1])


def chaikin(points, iterations=2):
    """Smooth a closed polygon (corner cutting) so a dozen rim points read as a curve."""
    pts = [tuple(p) for p in points]
    for _ in range(iterations):
        out = []
        n = len(pts)
        for i in range(n):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
            out.append((0.75 * x0 + 0.25 * x1, 0.75 * y0 + 0.25 * y1))
            out.append((0.25 * x0 + 0.75 * x1, 0.25 * y0 + 0.75 * y1))
        pts = out
    return [[round(x, 1), round(y, 1)] for x, y in pts]


def _point_in_polygon(x, y, poly):
    inside = False
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y):
            if x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                inside = not inside
        j = i
    return inside


def _dist_to_segment(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L2))
    cx, cy = ax + t * dx, ay + t * dy
    return math.hypot(px - cx, py - cy)


class Boundary:
    def __init__(self, path=BOUNDARY_FILE):
        self.path = path
        self.lock = threading.Lock()
        self.config = dict(DEFAULT_CONFIG)
        self._mask = None
        self.surface_z = None  # pen-down Z of the drawing surface, set by the bridge
        self.load()

    # ── persistence ────────────────────────────────────────────────
    def load(self):
        if os.path.exists(self.path):
            try:
                with open(self.path) as f:
                    data = json.load(f)
                cfg = dict(DEFAULT_CONFIG)
                cfg.update(data)
                self._validate(cfg["polygon"])
                self.config = cfg
                self._mask = None
                print(f"[Boundary] Loaded {len(cfg['polygon'])} points from {self.path}")
                return
            except Exception as e:
                print(f"[Boundary] Could not load {self.path}: {e} — using default")
        self.config = dict(DEFAULT_CONFIG)

    def save(self):
        self._mask = None  # outline/margin may have changed
        with open(self.path, "w") as f:
            json.dump(self.config, f, indent=2)

    @staticmethod
    def _validate(polygon):
        if len(polygon) < 3:
            raise ValueError("Boundary needs at least 3 points")
        for p in polygon:
            if len(p) != 2 or not all(isinstance(v, (int, float)) for v in p):
                raise ValueError(f"Bad point: {p}")

    def set_polygon(self, polygon, smooth=False, calibrated=True):
        self._validate(polygon)
        with self.lock:
            self.config["polygon"] = chaikin(polygon) if smooth else [list(map(float, p)) for p in polygon]
            self.config["calibrated"] = calibrated
            self.save()

    def update_settings(self, safe_z=None, margin_mm=None, rim_clearance_mm=None):
        with self.lock:
            if safe_z is not None:
                self.config["safe_z"] = float(safe_z)
            if rim_clearance_mm is not None:
                self.config["rim_clearance_mm"] = max(3.0, float(rim_clearance_mm))
            if margin_mm is not None:
                self.config["margin_mm"] = float(margin_mm)
            self.save()

    def reset(self):
        with self.lock:
            self.config = dict(DEFAULT_CONFIG)
            self.save()

    # ── accessors ──────────────────────────────────────────────────
    @property
    def polygon(self):
        return self.config["polygon"]

    @property
    def safe_z(self):
        """
        Z at/above which the pen clears the rim: the drawing surface plus the
        rim clearance, so it follows the pen height (paper, notebook, sand).
        """
        if self.surface_z is None:
            return self.config["safe_z"]
        return round(self.surface_z + self.config.get("rim_clearance_mm", 15.0), 1)

    @property
    def margin(self):
        return self.config["margin_mm"]

    def bbox(self):
        xs = [p[0] for p in self.polygon]
        ys = [p[1] for p in self.polygon]
        return min(xs), min(ys), max(xs), max(ys)

    def to_dict(self):
        min_x, min_y, max_x, max_y = self.bbox()
        d = dict(self.config)
        d["safe_z"] = self.safe_z
        d.setdefault("rim_clearance_mm", 15.0)
        d["bbox"] = {"min_x": min_x, "min_y": min_y, "max_x": max_x, "max_y": max_y}
        return d

    # ── geometry ───────────────────────────────────────────────────
    def _build_mask(self):
        """
        Rasterise "safe to draw" once: inside the pit, at least `margin` mm
        from the rim (distance transform), and outside the base keep-out.
        Point checks become an array lookup instead of a loop over every
        outline edge (hundreds of times faster on the Pi).
        """
        min_x, min_y, max_x, max_y = self.bbox()
        pad = 2.0
        x0, y0 = min_x - pad, min_y - pad
        w = int(math.ceil((max_x - min_x + 2 * pad) / MASK_RES_MM)) + 1
        h = int(math.ceil((max_y - min_y + 2 * pad) / MASK_RES_MM)) + 1
        inside = np.zeros((h, w), np.uint8)
        pts = np.array([[(x - x0) / MASK_RES_MM, (y - y0) / MASK_RES_MM] for x, y in self.polygon])
        cv2.fillPoly(inside, [np.round(pts).astype(np.int32)], 1)
        if self.margin > 0:
            dist_mm = cv2.distanceTransform(inside, cv2.DIST_L2, cv2.DIST_MASK_PRECISE) * MASK_RES_MM
            # +0.5 mm covers grid rounding, so the lookup never allows a point
            # closer than `margin` to the rim (it's at most 0.5 mm stricter).
            safe = dist_mm >= self.margin + 0.5
        else:
            safe = inside.astype(bool)
        gx = x0 + np.arange(w) * MASK_RES_MM
        gy = y0 + np.arange(h) * MASK_RES_MM
        safe &= (gx[None, :] ** 2 + gy[:, None] ** 2) >= BASE_KEEPOUT_MM ** 2
        self._mask = (safe, x0, y0)
        return self._mask

    def contains_many(self, xs, ys):
        """Vectorised contains() for numpy arrays of x and y (mm)."""
        safe, x0, y0 = self._mask or self._build_mask()
        h, w = safe.shape
        j = np.round((np.asarray(xs, float) - x0) / MASK_RES_MM).astype(int)
        i = np.round((np.asarray(ys, float) - y0) / MASK_RES_MM).astype(int)
        ok = (i >= 0) & (i < h) & (j >= 0) & (j < w)
        out = np.zeros(ok.shape, bool)
        out[ok] = safe[i[ok], j[ok]]
        return out

    def contains(self, x, y):
        """Inside the pit, at least `margin` mm from the rim, clear of the base."""
        return bool(self.contains_many(np.array([x]), np.array([y]))[0])

    def check_move(self, start, end):
        """
        Is a straight move start→end (x, y, z) safe? `start` may be None
        (position unknown), in which case only the target is checked.
        Returns None if safe, otherwise a human-readable reason.
        """
        sz = self.safe_z
        ex, ey, ez = end
        if not reachable(ex, ey, ez):
            return f"target X{ex} Y{ey} Z{ez} is out of the arm's reach"
        if ez >= sz and math.hypot(ex, ey) < BASE_KEEPOUT_MM:
            return f"target X{ex} Y{ey} is inside the base keep-out circle"
        if ez < sz and not self.contains(ex, ey):
            return f"target X{ex} Y{ey} Z{ez} is outside the pit (below safe Z {sz})"
        if start is None:
            return None
        sx, sy, szz = start
        length = math.dist((sx, sy), (ex, ey))
        steps = max(1, int(math.ceil(length / SAMPLE_STEP_MM)))
        if steps < 2:
            return None
        t = np.arange(1, steps) / steps
        xs, ys, zs = sx + (ex - sx) * t, sy + (ey - sy) * t, szz + (ez - szz) * t
        bad = (zs < sz) & ~self.contains_many(xs, ys)
        if bad.any():
            k = int(np.argmax(bad))
            return (f"path X{sx} Y{sy} → X{ex} Y{ey} leaves the pit near "
                    f"X{round(float(xs[k]), 1)} Y{round(float(ys[k]), 1)} at Z{round(float(zs[k]), 1)} (below safe Z {sz})")
        return None

    def lift_point(self, x, y, z_travel):
        """
        Nearest spot (sliding radially outward from x, y, staying in the pit)
        where the arm can actually reach safe Z. None if there isn't one.
        """
        r0 = math.hypot(x, y)
        if r0 == 0:
            return None
        for step in range(0, 100):
            r = r0 + step * SAMPLE_STEP_MM
            qx, qy = round(x * r / r0, 1), round(y * r / r0, 1)
            if not self.contains(qx, qy):
                break
            if reachable(qx, qy, self.safe_z):
                if step == 0 or self.check_move((x, y, z_travel), (qx, qy, z_travel)) is None:
                    return qx, qy
        return None

    def clip_stroke(self, pts):
        """
        Split a polyline (list of (x, y)) into the runs that lie inside the pit.
        Keeps original vertices and adds a point where each run crosses the
        boundary, so the output stays close to the input's point count.
        """
        runs = []
        if not pts:
            return runs
        cur = [pts[0]] if self.contains(*pts[0]) else []
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            length = math.dist((ax, ay), (bx, by))
            steps = max(1, int(math.ceil(length / SAMPLE_STEP_MM)))
            was_inside = bool(cur)
            last_in = (ax, ay) if was_inside else None
            ts = np.arange(1, steps + 1) / steps
            inside_all = self.contains_many(ax + (bx - ax) * ts, ay + (by - ay) * ts)
            if was_inside and inside_all.all():
                cur.append((bx, by))  # common case: whole segment inside
                continue
            for i in range(1, steps + 1):
                t = i / steps
                x, y = ax + (bx - ax) * t, ay + (by - ay) * t
                inside = bool(inside_all[i - 1])
                if inside and not was_inside:
                    cur = [(round(x, 1), round(y, 1))]
                elif not inside and was_inside:
                    if last_in and (not cur or cur[-1] != last_in):
                        cur.append((round(last_in[0], 1), round(last_in[1], 1)))
                    if len(cur) >= 2:
                        runs.append(cur)
                    cur = []
                if inside:
                    last_in = (x, y)
                was_inside = inside
            if was_inside:
                cur.append((bx, by))
        if len(cur) >= 2:
            runs.append(cur)
        return runs
