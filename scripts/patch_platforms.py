"""Apply Quizinho's native settings to the generated iOS/Android projects.

Idempotent and cross-platform (uses plistlib, not Xcode's PlistBuddy), so it
runs on Linux CI as well as macOS.
"""

import pathlib
import plistlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
DISPLAY_NAME = "Quizinho"

# Join links (the QR code) open the app when it's installed: Universal Links,
# backed by .well-known/apple-app-site-association on this domain.
LINK_DOMAIN = "uncleanthonys.github.io"
BUNDLE_ID = "com.littlefortstudios.quizinho"


def patch_ios() -> None:
    plist_path = ROOT / "ios" / "Runner" / "Info.plist"
    if not plist_path.exists():
        print("no iOS Info.plist, skipping")
        return
    with plist_path.open("rb") as f:
        p = plistlib.load(f)
    p["CFBundleDisplayName"] = DISPLAY_NAME
    # Portrait app; buzzer games unlock landscape ("table mode") from Dart.
    # UIRequiresFullScreen lets iPad accept the restricted set.
    p["UISupportedInterfaceOrientations"] = [
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    ]
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
    # Links are handled in Dart (app_links), not by Flutter's router.
    p["FlutterDeepLinkingEnabled"] = False
    with plist_path.open("wb") as f:
        plistlib.dump(p, f)
    print("patched", plist_path.relative_to(ROOT))

    # Associated Domains entitlement, wired into the Runner target's builds.
    ent_path = ROOT / "ios" / "Runner" / "Runner.entitlements"
    ent = {}
    if ent_path.exists():
        with ent_path.open("rb") as f:
            ent = plistlib.load(f)
    ent["com.apple.developer.associated-domains"] = [f"applinks:{LINK_DOMAIN}"]
    with ent_path.open("wb") as f:
        plistlib.dump(ent, f)
    pbx_path = ROOT / "ios" / "Runner.xcodeproj" / "project.pbxproj"
    pbx = pbx_path.read_text(encoding="utf-8")
    if "CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;" not in pbx:
        target = f"PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};"
        n = pbx.count(target)
        print(f"adding entitlements to {n} Runner build configurations")
        pbx = pbx.replace(target, "CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n\t\t\t\t" + target)
        pbx_path.write_text(pbx, encoding="utf-8")
    print("patched", ent_path.relative_to(ROOT))


def patch_android() -> None:
    manifest = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        print("no AndroidManifest.xml, skipping")
        return
    s = manifest.read_text(encoding="utf-8")
    s = re.sub(r'android:label="[^"]*"', f'android:label="{DISPLAY_NAME}"', s, count=1)
    # The internet: joining on phones, the weekly data, purchases. Flutter only
    # adds it to debug builds, so release builds had none.
    for perm in ('android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE'):
        if perm not in s:
            s = s.replace('<application', f'<uses-permission android:name="{perm}"/>\n    <application', 1)
    # Microphone + speech recogniser (voice answers)
    if 'android.permission.RECORD_AUDIO' not in s:
        s = s.replace('<application', '<uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <application', 1)
    if 'android.speech.RecognitionService' not in s:
        q = '    <queries>\n        <intent>\n            <action android:name="android.speech.RecognitionService" />\n        </intent>\n'
        s = s.replace('    <queries>\n', q, 1) if '    <queries>\n' in s else s.replace('</manifest>', q + '    </queries>\n</manifest>', 1)
    # No advertising ID (Play is told the app doesn't use one): strip it even
    # if a library asks for it.
    if 'com.google.android.gms.permission.AD_ID' not in s:
        if 'xmlns:tools=' not in s:
            s = s.replace('<manifest ', '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
        s = s.replace('<application', '<uses-permission android:name="com.google.android.gms.permission.AD_ID" tools:node="remove"/>\n    <application', 1)
    # Orientation is controlled from Dart (portrait, plus landscape in buzzer games).
    s = s.replace('            android:screenOrientation="portrait"\n', '')
    manifest.write_text(s, encoding="utf-8")
    print("patched", manifest.relative_to(ROOT))
    patch_android_signing()


# Release builds signed with the Play upload key when Codemagic provides it
# (android_signing: quizinho_upload sets CM_KEYSTORE_PATH etc.); otherwise
# the debug key, so CI's debug builds and local runs work as before.
SIGNING = '''    signingConfigs {
        create("upload") {
            val ks = System.getenv("CM_KEYSTORE_PATH")
            if (ks != null) {
                storeFile = file(ks)
                storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("CM_KEY_ALIAS")
                keyPassword = System.getenv("CM_KEY_PASSWORD")
            }
        }
    }

'''


def patch_android_signing() -> None:
    gradle = ROOT / "android" / "app" / "build.gradle.kts"
    if not gradle.exists():
        print("no android/app/build.gradle.kts, skipping signing")
        return
    s = gradle.read_text(encoding="utf-8")
    if 'create("upload")' in s:
        return
    debug = 'signingConfig = signingConfigs.getByName("debug")'
    if s.count(debug) != 1 or s.count("    buildTypes {") != 1:
        raise SystemExit("build.gradle.kts doesn't look like Flutter's template: can't add release signing")
    s = s.replace("    buildTypes {", SIGNING + "    buildTypes {", 1)
    s = s.replace(debug, 'signingConfig = signingConfigs.getByName(if (System.getenv("CM_KEYSTORE_PATH") != null) "upload" else "debug")', 1)
    gradle.write_text(s, encoding="utf-8")
    print("patched", gradle.relative_to(ROOT), "(release signing)")
    patch_android_lint()


def patch_android_lint() -> None:
    """Release builds run Android lint over every plugin, and lint itself
    crashes on in_app_purchase's Java (a bug in lint, not in the code), which
    fails the whole build. The checks only report; switch them off."""
    root_gradle = ROOT / "android" / "build.gradle.kts"
    if not root_gradle.exists():
        print("no android/build.gradle.kts, skipping lint")
        return
    s = root_gradle.read_text(encoding="utf-8")
    if "lintVital" in s:
        return
    s += '''
// Quizinho: release builds skip lint (it crashes on a plugin; see patch_platforms.py).
subprojects {
    tasks.matching { it.name.startsWith("lintVital") }.configureEach { enabled = false }
}
'''
    root_gradle.write_text(s, encoding="utf-8")
    print("patched", root_gradle.relative_to(ROOT), "(no release lint)")


def patch_web() -> None:
    index = ROOT / "web" / "index.html"
    if not index.exists():
        print("no web/index.html, skipping")
        return
    s = index.read_text(encoding="utf-8")
    s = re.sub(r"<title>[^<]*</title>", f"<title>{DISPLAY_NAME}</title>", s, count=1)
    s = re.sub(r'(<meta name="apple-mobile-web-app-title" content=")[^"]*"', rf'\g<1>{DISPLAY_NAME}"', s, count=1)
    # Android Chrome: the keyboard slides over the page instead of shrinking
    # it — no jerky full-screen re-layout while typing an answer. (Answer
    # boxes sit near the top, above the keyboard.)
    if "virtualKeyboard" not in s:
        s = s.replace(
            "</head>",
            '  <script>if ("virtualKeyboard" in navigator) navigator.virtualKeyboard.overlaysContent = true;</script>\n</head>',
            1,
        )
    # The page behind the game in the game's darkest green: while Safari's
    # keyboard and toolbar slide away, the strip it hasn't handed back to the
    # game yet shows this instead of a black/white flash.
    if "quizinho-bg" not in s:
        s = s.replace(
            "</head>",
            '  <meta name="theme-color" content="#051F15">\n'
            '  <style id="quizinho-bg">html, body { background: #051F15; }</style>\n</head>',
            1,
        )
    index.write_text(s, encoding="utf-8")
    print("patched", index.relative_to(ROOT))


if __name__ == "__main__":
    patch_ios()
    patch_android()
    patch_web()
