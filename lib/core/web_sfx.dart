// Sound effects in a browser through Web Audio: decoded once, then played
// instantly and on top of each other. (The browser's <audio> elements lag,
// most of all on iPhones.) The apps use audioplayers instead.
export 'web_sfx_stub.dart' if (dart.library.js_interop) 'web_sfx_web.dart';
