#!/usr/bin/env python3
"""
CursorFinder tracker daemon for Omarchy / Hyprland.

Polls Hyprland's UNIX socket for cursor position with adaptive frequency,
detects rapid back-and-forth pointer shakes (macOS "Shake mouse pointer to
locate" behavior), and streams active frame updates to the Quickshell service
only while the cursor is enlarged.
"""

from __future__ import annotations

import argparse
import atexit
import math
import os
import signal
import socket
import sys
import time
from collections import deque
from dataclasses import dataclass


@dataclass
class Stroke:
    dx: float
    dy: float
    distance: float
    duration_ms: float
    end_ms: float

    @property
    def speed(self) -> float:
        return self.distance / max(1.0, self.duration_ms)


class ShakeDetector:
    """
    Detects rapid oscillatory cursor movement (shakes) while ignoring normal
    unidirectional flicks, smooth curves, and micro-jitters.
    """

    def __init__(
        self,
        sensitivity: float = 1.0,
        max_scale: float = 4.2,
        hold_ms: float = 480.0,
        window_ms: float = 460.0,
        min_reversals: int = 3,
    ) -> None:
        self.sensitivity = max(0.25, min(3.0, float(sensitivity)))
        self.max_scale = max(1.5, min(8.0, float(max_scale)))
        self.hold_ms = max(150.0, min(3000.0, float(hold_ms)))
        self.window_ms = max(200.0, min(1200.0, float(window_ms)))
        self.min_reversals = max(2, int(min_reversals))

        # Thresholds scaled inversely by sensitivity
        self.min_step_px = 2.0
        self.reversal_deadzone_px = max(5.0, 9.0 / math.sqrt(self.sensitivity))
        self.min_stroke_px = max(16.0, 32.0 / self.sensitivity)
        self.min_stroke_speed = max(0.28, 0.58 / self.sensitivity)  # px / ms
        self.min_window_distance = max(75.0, 165.0 / self.sensitivity)

        # Current accumulating stroke
        self._stroke_dx: float = 0.0
        self._stroke_dy: float = 0.0
        self._stroke_dist: float = 0.0
        self._stroke_start_ms: float = 0.0
        self._stroke_last_ms: float = 0.0

        # Previous completed stroke and recent reversals
        self._prev_stroke: Stroke | None = None
        self._reversals: deque[tuple[float, float, float]] = deque()  # (time_ms, dist, speed)

        # Active state & smooth scale animation
        self.active: bool = False
        self.current_scale: float = 1.0
        self.target_scale: float = 1.0
        self.active_until_ms: float = 0.0
        self._last_update_ms: float = 0.0

    def trigger_manual(self, now_ms: float) -> None:
        """Manually trigger the locate animation (e.g. via IPC or test button)."""
        self.active = True
        self.target_scale = self.max_scale
        self.active_until_ms = now_ms + max(750.0, self.hold_ms * 1.5)
        self._last_update_ms = now_ms

    def _prune_reversals(self, now_ms: float) -> None:
        cutoff = now_ms - self.window_ms
        while self._reversals and self._reversals[0][0] < cutoff:
            self._reversals.popleft()

    def _complete_stroke(self, now_ms: float) -> None:
        if self._stroke_dist < self.min_stroke_px:
            self._prev_stroke = None
            return

        duration = max(1.0, self._stroke_last_ms - self._stroke_start_ms)
        stroke = Stroke(
            dx=self._stroke_dx,
            dy=self._stroke_dy,
            distance=self._stroke_dist,
            duration_ms=duration,
            end_ms=now_ms,
        )

        if stroke.speed < self.min_stroke_speed:
            self._prev_stroke = None
            return

        if self._prev_stroke is not None:
            gap_ms = now_ms - self._prev_stroke.end_ms
            if gap_ms <= self.window_ms:
                n1 = math.hypot(self._prev_stroke.dx, self._prev_stroke.dy)
                n2 = math.hypot(stroke.dx, stroke.dy)
                if n1 > 1e-3 and n2 > 1e-3:
                    cos_theta = (self._prev_stroke.dx * stroke.dx + self._prev_stroke.dy * stroke.dy) / (n1 * n2)
                    # Angle > ~102 degrees (cos < -0.20) counts as a direction reversal
                    if cos_theta < -0.20:
                        combined_dist = 0.5 * (self._prev_stroke.distance + stroke.distance)
                        avg_speed = 0.5 * (self._prev_stroke.speed + stroke.speed)
                        self._reversals.append((now_ms, combined_dist, avg_speed))
                        self._prune_reversals(now_ms)
                        self._evaluate_shake(now_ms, stroke.speed)
                    elif cos_theta > 0.35:
                        # Wide curve or same direction: clear old reversals
                        self._reversals.clear()
            else:
                self._reversals.clear()

        self._prev_stroke = stroke

    def _evaluate_shake(self, now_ms: float, latest_speed: float) -> None:
        if len(self._reversals) < self.min_reversals and not self.active:
            return

        total_dist = sum(r[1] for r in self._reversals)
        avg_speed = sum(r[2] for r in self._reversals) / max(1, len(self._reversals))

        if not self.active and total_dist < self.min_window_distance:
            return

        extra_reversals = max(0, len(self._reversals) - self.min_reversals)
        speed_factor = min(1.0, (avg_speed - self.min_stroke_speed) / max(0.5, self.min_stroke_speed * 2.0))
        intensity = min(1.0, 0.55 + 0.15 * extra_reversals + 0.30 * max(0.0, speed_factor))

        min_active = min(self.max_scale, max(2.2, 1.0 + (self.max_scale - 1.0) * 0.65))
        desired_scale = min_active + (self.max_scale - min_active) * intensity

        self.active = True
        self.target_scale = max(self.target_scale, min(self.max_scale, desired_scale))
        self.active_until_ms = now_ms + self.hold_ms

    def update(self, dx: float, dy: float, now_ms: float) -> tuple[bool, float]:
        """
        Feed a relative pointer delta (dx, dy) at timestamp now_ms.
        Returns (is_visible, current_scale).
        """
        dt_ms = max(1.0, now_ms - self._last_update_ms) if self._last_update_ms > 0 else 16.0
        self._last_update_ms = now_ms
        self._prune_reversals(now_ms)

        step_dist = math.hypot(dx, dy)
        inst_speed = step_dist / dt_ms

        if step_dist >= self.min_step_px:
            if self._stroke_dist == 0.0:
                self._stroke_dx = dx
                self._stroke_dy = dy
                self._stroke_dist = step_dist
                self._stroke_start_ms = now_ms - dt_ms
                self._stroke_last_ms = now_ms
            else:
                stroke_norm = math.hypot(self._stroke_dx, self._stroke_dy)
                if stroke_norm > 1e-3:
                    # Projection of current step onto current stroke direction
                    proj = (dx * self._stroke_dx + dy * self._stroke_dy) / stroke_norm
                else:
                    proj = step_dist

                if proj < -self.reversal_deadzone_px or (proj < 0 and step_dist >= self.reversal_deadzone_px):
                    # Pointer reversed against the current stroke
                    self._complete_stroke(now_ms - dt_ms * 0.5)
                    self._stroke_dx = dx
                    self._stroke_dy = dy
                    self._stroke_dist = step_dist
                    self._stroke_start_ms = now_ms - dt_ms
                    self._stroke_last_ms = now_ms
                else:
                    self._stroke_dx += dx
                    self._stroke_dy += dy
                    self._stroke_dist += step_dist
                    self._stroke_last_ms = now_ms

                    # While already active, fast movement keeps it alive
                    if self.active and inst_speed >= self.min_stroke_speed * 0.85:
                        self.active_until_ms = max(self.active_until_ms, now_ms + self.hold_ms * 0.75)
        else:
            # Pointer paused: if pause > 95ms, finalize any pending stroke
            if self._stroke_dist > 0 and (now_ms - self._stroke_last_ms) > 95.0:
                self._complete_stroke(self._stroke_last_ms)
                self._stroke_dx = 0.0
                self._stroke_dy = 0.0
                self._stroke_dist = 0.0

        # Check hold expiration
        if self.active and now_ms >= self.active_until_ms:
            self.target_scale = 1.0
            self._reversals.clear()

        # Smooth exponential interpolation for scale (spring-like feel)
        if self.target_scale > self.current_scale:
            # Fast grow-in (~75ms time constant)
            alpha = 1.0 - math.exp(-dt_ms / 42.0)
            self.current_scale += (self.target_scale - self.current_scale) * alpha
            if abs(self.target_scale - self.current_scale) < 0.02:
                self.current_scale = self.target_scale
        elif self.target_scale < self.current_scale:
            # Smooth shrink-out (~65ms time constant)
            alpha = 1.0 - math.exp(-dt_ms / 55.0)
            self.current_scale += (self.target_scale - self.current_scale) * alpha
            if self.current_scale <= 1.03:
                self.current_scale = 1.0
                self.target_scale = 1.0
                self.active = False

        return self.active, self.current_scale


class HyprlandSocket:
    def __init__(self) -> None:
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        rdir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        self.sock_path = f"{rdir}/hypr/{sig}/.socket.sock" if sig else ""

    def request(self, payload: bytes) -> str:
        if not self.sock_path:
            return ""
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                s.settimeout(0.25)
                s.connect(self.sock_path)
                s.sendall(payload)
                return s.recv(512).decode("utf-8", errors="replace").strip()
        except OSError:
            return ""

    def cursor_pos(self) -> tuple[int, int] | None:
        raw = self.request(b"cursorpos")
        if not raw or "," not in raw:
            return None
        try:
            parts = raw.split(",", 1)
            return int(parts[0].strip()), int(parts[1].strip())
        except ValueError:
            return None

    def set_cursor_invisible(self, invisible: bool) -> None:
        val = "true" if invisible else "false"
        self.request(f"eval hl.config({{ cursor = {{ invisible = {val} }} }})".encode("utf-8"))

    def ensure_layer_rule(self) -> None:
        self.request(
            b'eval hl.layer_rule({ match = { namespace = "omarchy-cursor-finder" }, no_anim = true, animation = "none" })'
        )


def run_self_test() -> int:
    det = ShakeDetector(sensitivity=1.0, max_scale=4.2, hold_ms=450.0)
    t = 1000.0

    # 1. Test normal fast movement in one direction (2000px across screen) -> should NOT trigger
    for _ in range(30):
        t += 12.0
        active, scale = det.update(65.0, 10.0, t)
        assert not active, f"False positive on unidirectional flick at t={t}"

    # Pause
    t += 600.0
    det.update(0.0, 0.0, t)

    # 2. Test rapid back-and-forth shake (4 strokes: +120px, -120px, +120px, -120px)
    triggered = False
    peak_scale = 1.0
    for direction in (1, -1, 1, -1, 1):
        for _ in range(5):
            t += 12.0
            active, scale = det.update(direction * 26.0, direction * 4.0, t)
            if active:
                triggered = True
                peak_scale = max(peak_scale, scale)

    assert triggered, "Failed to trigger on rapid back-and-forth shake"
    assert peak_scale > 2.0, f"Expected scale > 2.0, got {peak_scale:.2f}"

    # 3. Test smooth decay back to 1.0 after hold_ms
    for _ in range(100):
        t += 12.0
        active, scale = det.update(0.0, 0.0, t)
    assert not active and scale == 1.0, f"Expected decay back to inactive 1.0, got active={active}, scale={scale}"

    print(f"SELF_TEST_OK peak_scale={peak_scale:.2f}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="CursorFinder shake detector daemon")
    parser.add_argument("--sensitivity", type=float, default=1.0)
    parser.add_argument("--max-scale", type=float, default=4.2)
    parser.add_argument("--hold-ms", type=float, default=480.0)
    parser.add_argument("--hide-native", type=int, default=1)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return run_self_test()

    hypr = HyprlandSocket()
    detector = ShakeDetector(
        sensitivity=args.sensitivity,
        max_scale=args.max_scale,
        hold_ms=args.hold_ms,
    )
    hide_native = bool(args.hide_native)
    native_hidden = False
    manual_trigger_requested = False

    def restore_native_cursor() -> None:
        nonlocal native_hidden
        if hide_native or native_hidden:
            hypr.set_cursor_invisible(False)
            native_hidden = False

    atexit.register(restore_native_cursor)

    def handle_exit_signal(signum: int, _frame: object) -> None:
        restore_native_cursor()
        sys.exit(0)

    def handle_usr1(_signum: int, _frame: object) -> None:
        nonlocal manual_trigger_requested
        manual_trigger_requested = True

    signal.signal(signal.SIGTERM, handle_exit_signal)
    signal.signal(signal.SIGINT, handle_exit_signal)
    signal.signal(signal.SIGHUP, handle_exit_signal)
    signal.signal(signal.SIGUSR1, handle_usr1)

    hypr.ensure_layer_rule()
    hypr.set_cursor_invisible(False)

    sys.stdout.write(f"READY {os.getpid()}\n")
    sys.stdout.flush()

    last_pos = hypr.cursor_pos()
    last_move_mono = time.monotonic()
    was_visible = False
    last_emitted = ""
    frames_visible = 0

    try:
        while True:
            # Exit cleanly if parent omarchy-shell process exited
            if os.getppid() == 1:
                break

            now_mono = time.monotonic()
            now_ms = now_mono * 1000.0

            pos = hypr.cursor_pos()
            if pos is None:
                time.sleep(0.05)
                continue

            x, y = pos
            if last_pos is None:
                last_pos = (x, y)

            dx = float(x - last_pos[0])
            dy = float(y - last_pos[1])
            last_pos = (x, y)

            if dx != 0.0 or dy != 0.0:
                last_move_mono = now_mono

            if manual_trigger_requested:
                manual_trigger_requested = False
                detector.trigger_manual(now_ms)

            is_visible, scale = detector.update(dx, dy, now_ms)

            if is_visible:
                if not was_visible:
                    hypr.ensure_layer_rule()
                frames_visible += 1
                msg = f"FRAME {x} {y} {scale:.3f}"
                if msg != last_emitted:
                    sys.stdout.write(msg + "\n")
                    sys.stdout.flush()
                    last_emitted = msg

                # Hide native cursor on the frame after the overlay renders so
                # there is never a gap without a cursor on screen.
                if hide_native and not native_hidden and frames_visible >= 2:
                    hypr.set_cursor_invisible(True)
                    native_hidden = True
                was_visible = True
            elif was_visible:
                # Restore hardware cursor BEFORE hiding the overlay
                if native_hidden:
                    hypr.set_cursor_invisible(False)
                    native_hidden = False
                sys.stdout.write("HIDE\n")
                sys.stdout.flush()
                last_emitted = "HIDE"
                was_visible = False
                frames_visible = 0

            # Adaptive sleep interval
            if is_visible:
                time.sleep(0.008)  # ~125 FPS while active
            elif (now_mono - last_move_mono) < 0.25:
                time.sleep(0.012)  # ~83 Hz while moving
            else:
                time.sleep(0.040)  # 25 Hz when stationary
    finally:
        restore_native_cursor()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
