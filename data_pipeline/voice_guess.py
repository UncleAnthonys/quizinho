"""Guess how speech recognisers mishear footballer names, before real players
hit them: a British computer voice says each name, two free offline
recognisers (Vosk, Whisper tiny) write down what they hear, and the results go
to build/voice_guess.json. A Flutter test then checks which of those Quizinho
would already accept (test/voice_guess_check_test.dart).

Trial first on a few dozen hard names; the recognisers aren't Google's, so
this only shows whether their mistakes look like Chrome's real ones.

  python3 data_pipeline/voice_guess.py --limit 50
"""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import tempfile
import wave

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "data_pipeline"))
from spoken import language  # noqa: E402


def hard_names(limit: int, min_fame: int) -> list[dict]:
    """Well-known players whose names don't follow English spelling."""
    db = json.loads((ROOT / "assets/db/football.json").read_text(encoding="utf-8"))
    out = [p for p in db["players"] if p.get("fame", 0) >= min_fame and language(p["name"], p.get("nat"))]
    out.sort(key=lambda p: (-p.get("fame", 0), p["name"]))
    return out[:limit]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=50)
    ap.add_argument("--min-fame", type=int, default=3)
    ap.add_argument("--voice", default="voices/en_GB-alan-medium.onnx")
    ap.add_argument("--vosk", default="voices/vosk-model-small-en-us-0.15")
    args = ap.parse_args()

    from faster_whisper import WhisperModel
    from piper import PiperVoice
    from vosk import KaldiRecognizer, Model

    voice = PiperVoice.load(args.voice)
    vosk = Model(args.vosk)
    whisper = WhisperModel("tiny.en", compute_type="int8")
    results = []
    tmp = pathlib.Path(tempfile.mkdtemp())
    for p in hard_names(args.limit, args.min_fame):
        raw, wav16 = tmp / "raw.wav", tmp / "16k.wav"
        with wave.open(str(raw), "wb") as w:
            (voice.synthesize_wav if hasattr(voice, "synthesize_wav") else voice.synthesize)(p["name"], w)
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", raw, "-ar", "16000", "-ac", "1", wav16], check=True)
        rec = KaldiRecognizer(vosk, 16000)
        with wave.open(str(wav16), "rb") as w:
            while data := w.readframes(4000):
                rec.AcceptWaveform(data)
        heard_vosk = json.loads(rec.FinalResult()).get("text", "")
        segs, _ = whisper.transcribe(str(wav16), language="en", beam_size=1)
        heard_whisper = " ".join(s.text for s in segs).strip(" .,!?")
        results.append({"id": p["id"], "name": p["name"], "vosk": heard_vosk, "whisper": heard_whisper})
        print(f"{p['name']:<32} vosk: {heard_vosk:<32} whisper: {heard_whisper}")
    out = ROOT / "build" / "voice_guess.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(results, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"wrote {len(results)} to {out}")


if __name__ == "__main__":
    main()
