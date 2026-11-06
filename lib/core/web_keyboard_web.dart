import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

/// Keyboard height (CSS px = logical px) from Chrome's VirtualKeyboard API.
/// web/index.html sets overlaysContent = true, so the page isn't squashed
/// (jerky); instead the guest screen pads itself by this much.
final ValueNotifier<double> keyboardInset = _watch();

ValueNotifier<double> _watch() {
  final out = ValueNotifier<double>(0);
  try {
    final nav = globalContext['navigator'];
    final vk = nav is JSObject ? nav['virtualKeyboard'] : null;
    if (vk is JSObject) {
      vk.callMethod<JSAny?>(
        'addEventListener'.toJS,
        'geometrychange'.toJS,
        ((JSAny? _) {
          final rect = vk['boundingRect'];
          final h = rect is JSObject ? (rect['height'] as JSNumber?)?.toDartDouble ?? 0 : 0.0;
          out.value = h;
        }).toJS,
      );
    }
  } catch (e) {
    debugPrint('Keyboard size not available: $e');
  }
  return out;
}
