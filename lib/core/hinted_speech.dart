// Browser speech that's told which names to listen for (Chrome's contextual
// biasing, on-device). Elsewhere — apps, other browsers — it's never used.
export 'hinted_speech_stub.dart' if (dart.library.js_interop) 'hinted_speech_web.dart';
