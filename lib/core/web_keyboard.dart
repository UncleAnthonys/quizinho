// How much of the screen the on-screen keyboard covers, in a browser where
// the keyboard slides over the page (Android Chrome) — so the page can lift
// the answer box above it, like the app does. Always 0 in the apps.
export 'web_keyboard_stub.dart' if (dart.library.js_interop) 'web_keyboard_web.dart';
