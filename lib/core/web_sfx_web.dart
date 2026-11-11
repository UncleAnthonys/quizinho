import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web Audio player for the sound effects: every sound is decoded once at
/// start-up, then each play is a fresh buffer source — no loading, no lag,
/// and sounds can overlap.
class WebSfx {
  WebSfx() {
    _keepOnInSilentMode();
    // Browsers start audio suspended until the first tap: wake it then.
    final wake = ((web.Event _) => _resume()).toJS;
    for (final type in ['pointerdown', 'touchend', 'keydown']) {
      web.document.addEventListener(type, wake, true.toJS);
    }
  }

  static const bool supported = true;

  final web.AudioContext _ctx = web.AudioContext();
  final Map<String, web.AudioBuffer> _buffers = {};

  /// iPhone: Web Audio would follow the silent switch; the app's sounds
  /// shouldn't, and the mic must still work for spoken answers.
  void _keepOnInSilentMode() {
    try {
      final session = web.window.navigator.getProperty<JSObject?>('audioSession'.toJS);
      session?.setProperty('type'.toJS, 'play-and-record'.toJS);
    } catch (_) {}
  }

  void _resume() {
    if (_ctx.state != 'running') _ctx.resume();
  }

  Future<void> load(String key, ByteData bytes) async {
    // decodeAudioData takes the buffer over, so hand it a copy.
    final copy = Uint8List.fromList(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    _buffers[key] = await _ctx.decodeAudioData(copy.buffer.toJS).toDart;
  }

  bool play(String key, double volume) {
    final b = _buffers[key];
    if (b == null) return false;
    _resume();
    final src = _ctx.createBufferSource()..buffer = b;
    final gain = _ctx.createGain();
    gain.gain.value = volume;
    src.connect(gain);
    gain.connect(_ctx.destination);
    src.start();
    return true;
  }
}
