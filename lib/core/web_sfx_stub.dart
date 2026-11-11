import 'dart:typed_data';

/// Not a browser: nothing here (see SoundService).
class WebSfx {
  static const bool supported = false;
  Future<void> load(String key, ByteData bytes) async {}
  bool play(String key, double volume) => false;
}
