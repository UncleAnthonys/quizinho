#!/usr/bin/env python3
"""Records the ?demo=1 autoplay round as a 1080x1920 social video.

Needs a running X display (Xvfb, 1080x1920) in $DISPLAY and, for sound, a
PulseAudio sink called "qdemo" (see .github/workflows/demo-video.yml).

Writes to --out:
  quizinho-demo.mp4   the video (H.264 + AAC, 30 fps, 9:16)
  caption.txt         post text for TikTok / Reels / Shorts
  meta.json           seed, game, teams, answers
  thumb.jpg           a frame from the middle
"""
import argparse
import json
import os
import subprocess
import sys
import time

from playwright.sync_api import sync_playwright

W, H = 1080, 1920

HASHTAGS = "#football #footballquiz #soccer #quiz #footballtiktok #premierleague #quiznight"

HOOKS = {
    "careerPath": "Guess the player from his clubs 👀 Did you get it before they buzzed?",
    "clubConnections": "Name a player who played for both clubs ⚽ Could you beat the buzzer?",
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--audio", default="qdemo.monitor", help="PulseAudio source ('' = no sound)")
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    raw = os.path.join(args.out, "raw.mkv")

    events: list[tuple[float, dict]] = []

    def on_console(msg):
        text = msg.text
        if text.startswith("QDEMO "):
            try:
                ev = json.loads(text[6:])
            except json.JSONDecodeError:
                return
            events.append((time.time(), ev))
            print("event:", ev, flush=True)
        elif msg.type == "error":
            print("console error:", text[:300], flush=True)

    def wait_for(name: str, timeout: float) -> float:
        end = time.time() + timeout
        while time.time() < end:
            for t, ev in events:
                if ev.get("e") == name:
                    return t
            page.wait_for_timeout(100)
        raise SystemExit(f"Timed out waiting for '{name}' from the demo")

    with sync_playwright() as p:
        browser = p.chromium.launch(
            headless=False,
            args=[
                f"--window-size={W // 2},{H // 2}",
                "--window-position=0,0",
                "--force-device-scale-factor=2",
                "--autoplay-policy=no-user-gesture-required",
                "--no-first-run",
                "--disable-infobars",
                "--hide-scrollbars",
            ],
        )
        ctx = browser.new_context(no_viewport=True)
        page = ctx.new_page()
        page.on("console", on_console)
        page.on("pageerror", lambda e: print("page error:", e, flush=True))
        page.on("response", lambda r: print("missing:", r.url, flush=True) if r.status >= 400 else None)
        # True fullscreen: no tabs or address bar in shot.
        cdp = ctx.new_cdp_session(page)
        wid = cdp.send("Browser.getWindowForTarget")["windowId"]
        cdp.send("Browser.setWindowBounds", {"windowId": wid, "bounds": {"windowState": "fullscreen"}})
        page.wait_for_timeout(500)
        print("page size:", page.evaluate("[innerWidth, innerHeight, devicePixelRatio]"), flush=True)
        page.goto(args.url)
        wait_for("ready", 120)

        cmd = ["ffmpeg", "-y", "-loglevel", "error",
               "-f", "x11grab", "-draw_mouse", "0", "-framerate", "30",
               "-video_size", f"{W}x{H}", "-i", os.environ.get("DISPLAY", ":99") + ".0"]
        if args.audio:
            cmd += ["-f", "pulse", "-i", args.audio]
        cmd += ["-c:v", "libx264", "-preset", "ultrafast", "-crf", "16", "-pix_fmt", "yuv420p"]
        if args.audio:
            cmd += ["-c:a", "aac", "-b:a", "192k"]
        cmd.append(raw)
        rec = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        t0 = time.time()

        t_go = wait_for("go", 30)
        t_end = wait_for("end", 240)
        page.wait_for_timeout(600)
        rec.communicate(b"q", timeout=30)
        page.screenshot(path=os.path.join(args.out, "last_frame.png"))
        browser.close()

    errors = [ev for _, ev in events if ev.get("e") == "error"]
    for ev in errors:
        print("demo error:", ev, file=sys.stderr)

    start = max(0.0, t_go - t0 - 0.2)
    length = (t_end - t0 + 0.4) - start
    video = os.path.join(args.out, "quizinho-demo.mp4")
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{start:.2f}", "-i", raw, "-t", f"{length:.2f}",
         "-vf", "fps=30,format=yuv420p", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
         "-profile:v", "high", "-movflags", "+faststart"]
        + (["-c:a", "aac", "-b:a", "160k", "-ar", "44100"] if args.audio else ["-an"])
        + [video],
        check=True,
    )
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{length / 2:.2f}", "-i", video,
                    "-frames:v", "1", "-q:v", "3", os.path.join(args.out, "thumb.jpg")], check=True)
    # How smooth it is: share of frames that actually changed.
    dec = subprocess.run(["ffmpeg", "-i", video, "-vf", "mpdecimate", "-an", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    import re
    kept = re.findall(r"frame=\s*(\d+)", dec)
    total = int(length * 30)
    if kept:
        print(f"smoothness: {int(kept[-1])} distinct of ~{total} frames ({int(kept[-1]) / total:.0%})", flush=True)
    # Contact sheet: 12 frames across the video, for a quick look.
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", video, "-vf",
                    f"fps={12 / length:.4f},scale=270:-1,tile=6x2", "-frames:v", "1", "-q:v", "4",
                    os.path.join(args.out, "sheet.jpg")], check=True)
    os.remove(raw)

    ready = next(ev for _, ev in events if ev.get("e") == "ready")
    questions = [ev for _, ev in events if ev.get("e") == "question"]
    game = ready.get("game", "")
    caption = (
        f"{HOOKS.get(game, 'Football quiz night on one phone ⚽')} Comment your score 👇\n\n"
        "Quizinho: the football party game for you and your mates.\n\n"
        f"{HASHTAGS}\n"
    )
    with open(os.path.join(args.out, "caption.txt"), "w") as f:
        f.write(caption)
    end_ev = next(ev for _, ev in events if ev.get("e") == "end")
    meta = {
        "fps": end_ev.get("fps"),
        "slowFrames": end_ev.get("slowFrames"),
        "seed": ready.get("seed"),
        "game": game,
        "teams": ready.get("teams"),
        "questions": questions,
        "seconds": round(length, 1),
        "errors": errors,
    }
    with open(os.path.join(args.out, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2, ensure_ascii=False)
    print(json.dumps(meta, ensure_ascii=False))
    return 1 if errors or not questions else 0


if __name__ == "__main__":
    sys.exit(main())
