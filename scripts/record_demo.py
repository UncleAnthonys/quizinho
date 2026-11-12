#!/usr/bin/env python3
"""Records the ?demo=1 autoplay round as a 1080x1920 social video.

Needs a running X display (Xvfb, 1080x1920) in $DISPLAY (see
.github/workflows/demo-video.yml).

Without a graphics card Chrome draws only ~5 frames a second at this size, so
the page runs slowed down (?slow=6: every animation and timer 6x slower), is
filmed in real time, and the video is sped back up: smooth 30 fps. Sounds
aren't recorded; the page logs each one with its (demo) time and they are
mixed back in from the asset files.

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
    ap.add_argument("--slow", type=float, default=6, help="Slow-down factor (matches ?slow= in the URL)")
    ap.add_argument("--assets", default="assets", help="The app's assets folder (for the sounds)")
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
        url = args.url + ("&" if "?" in args.url else "?") + f"slow={args.slow:g}"
        page.goto(url)
        wait_for("ready", 120)

        cmd = ["ffmpeg", "-y", "-loglevel", "error",
               "-f", "x11grab", "-draw_mouse", "0", "-framerate", "15",
               "-video_size", f"{W}x{H}", "-i", os.environ.get("DISPLAY", ":99") + ".0"]
        cmd += ["-c:v", "libx264", "-preset", "ultrafast", "-crf", "16", "-pix_fmt", "yuv420p", raw]
        rec = subprocess.Popen(cmd, stdin=subprocess.PIPE)
        t0 = time.time()

        t_go = wait_for("go", 10 * args.slow)
        t_end = wait_for("end", 240 * args.slow)
        page.wait_for_timeout(int(500 * args.slow))
        rec.communicate(b"q", timeout=30)
        page.screenshot(path=os.path.join(args.out, "last_frame.png"))
        browser.close()

    errors = [ev for _, ev in events if ev.get("e") == "error"]
    for ev in errors:
        print("demo error:", ev, file=sys.stderr)

    # Real seconds in the raw recording -> demo (= final video) seconds.
    start = max(0.0, t_go - t0)
    length = (t_end - t_go) / args.slow + 0.4
    go_ms = next(ev for _, ev in events if ev.get("e") == "go").get("t", 0)
    sounds = [ev for _, ev in events if ev.get("e") == "sfx"]
    sounds = [(ev["t"] - go_ms, ev["a"], ev.get("v", 1)) for ev in sounds
              if 0 <= ev["t"] - go_ms < length * 1000 and os.path.exists(os.path.join(args.assets, ev["a"]))]

    video = os.path.join(args.out, "quizinho-demo.mp4")
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{start:.2f}", "-i", raw]
    for _, asset, _ in sounds:
        cmd += ["-i", os.path.join(args.assets, asset)]
    filters = [f"[0:v]setpts=(PTS-STARTPTS)/{args.slow:g},fps=30,trim=duration={length:.2f},format=yuv420p[v]"]
    if sounds:
        for i, (ms, _, vol) in enumerate(sounds, start=1):
            filters.append(f"[{i}:a]aformat=sample_rates=44100:channel_layouts=stereo,volume={vol:.2f},"
                           f"adelay={ms}|{ms}[s{i}]")
        mix = "".join(f"[s{i}]" for i in range(1, len(sounds) + 1))
        filters.append(f"{mix}amix=inputs={len(sounds)}:normalize=0:duration=longest,"
                       f"apad,atrim=duration={length:.2f},alimiter=limit=0.9[a]")
    cmd += ["-filter_complex", ";".join(filters), "-map", "[v]"]
    cmd += ["-map", "[a]", "-c:a", "aac", "-b:a", "160k"] if sounds else ["-an"]
    cmd += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-profile:v", "high",
            "-r", "30", "-movflags", "+faststart", video]
    subprocess.run(cmd, check=True)
    print(f"sounds mixed in: {len(sounds)}", flush=True)
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
