"""Apply Quizinho's native settings to the generated iOS/Android projects.

Idempotent and cross-platform (uses plistlib, not Xcode's PlistBuddy), so it
runs on Linux CI as well as macOS.
"""

import pathlib
import plistlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
DISPLAY_NAME = "Quizinho"


def patch_ios() -> None:
    plist_path = ROOT / "ios" / "Runner" / "Info.plist"
    if not plist_path.exists():
        print("no iOS Info.plist, skipping")
        return
    with plist_path.open("rb") as f:
        p = plistlib.load(f)
    p["CFBundleDisplayName"] = DISPLAY_NAME
    # Portrait-only party game. UIRequiresFullScreen lets iPad accept that.
    p["UISupportedInterfaceOrientations"] = ["UIInterfaceOrientationPortrait"]
    p["UISupportedInterfaceOrientations~ipad"] = [
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationPortraitUpsideDown",
    ]
    p["UIRequiresFullScreen"] = True
    # No custom encryption → skips the export-compliance question on every TestFlight build.
    p["ITSAppUsesNonExemptEncryption"] = False
    # Phase 2 (speech answers) needs these; harmless to declare early.
    p["NSMicrophoneUsageDescription"] = "Say your answer out loud instead of typing it."
    p["NSSpeechRecognitionUsageDescription"] = "Recognises footballer names you say during a game."
    with plist_path.open("wb") as f:
        plistlib.dump(p, f)
    print("patched", plist_path.relative_to(ROOT))


def patch_android() -> None:
    manifest = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        print("no AndroidManifest.xml, skipping")
        return
    s = manifest.read_text(encoding="utf-8")
    s = re.sub(r'android:label="[^"]*"', f'android:label="{DISPLAY_NAME}"', s, count=1)
    # Microphone + speech recogniser (voice answers)
    if 'android.permission.RECORD_AUDIO' not in s:
        s = s.replace('<application', '<uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <application', 1)
    if 'android.speech.RecognitionService' not in s:
        q = '    <queries>\n        <intent>\n            <action android:name="android.speech.RecognitionService" />\n        </intent>\n'
        s = s.replace('    <queries>\n', q, 1) if '    <queries>\n' in s else s.replace('</manifest>', q + '    </queries>\n</manifest>', 1)
    if 'android:screenOrientation' not in s:
        s = s.replace('<activity\n', '<activity\n            android:screenOrientation="portrait"\n', 1)
    manifest.write_text(s, encoding="utf-8")
    print("patched", manifest.relative_to(ROOT))


def patch_web() -> None:
    index = ROOT / "web" / "index.html"
    if not index.exists():
        print("no web/index.html, skipping")
        return
    s = index.read_text(encoding="utf-8")
    s = re.sub(r"<title>[^<]*</title>", f"<title>{DISPLAY_NAME}</title>", s, count=1)
    s = re.sub(r'(<meta name="apple-mobile-web-app-title" content=")[^"]*"', rf'\g<1>{DISPLAY_NAME}"', s, count=1)
    index.write_text(s, encoding="utf-8")
    print("patched", index.relative_to(ROOT))


if __name__ == "__main__":
    patch_ios()
    patch_android()
    patch_web()
