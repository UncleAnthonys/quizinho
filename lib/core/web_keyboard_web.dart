import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

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

web.HTMLInputElement? _primer;
DateTime? _primedAt;
Timer? _release;

/// Opens the keyboard from a tap (the buzzer), before the answer box exists.
/// Phone browsers - iPhone Safari above all - only open the keyboard when a
/// text field is focused during a tap, and the answer box arrives a moment
/// later, after the main phone takes the buzz. So an invisible field takes
/// the keyboard now and the answer box takes it over when it appears
/// ([keyboardPrimed] lets it focus itself). If no answer box comes (the
/// buzz lost), the keyboard closes again.
void primeKeyboard() {
  try {
    final input = _primer ??= (web.document.createElement('input') as web.HTMLInputElement)
      ..type = 'text'
      ..setAttribute('aria-hidden', 'true')
      ..style.cssText = 'position:fixed;top:0;left:0;width:1px;height:1px;opacity:0;'
          'font-size:16px;border:0;padding:0;pointer-events:none;';
    if (input.parentNode == null) web.document.body?.append(input);
    input.focus();
    _primedAt = DateTime.now();
    _release?.cancel();
    _release = Timer(const Duration(seconds: 4), () {
      if (web.document.activeElement == input) input.blur();
    });
  } catch (e) {
    debugPrint('Keyboard not primed: $e');
  }
}

/// The keyboard was opened by a tap in the last few seconds: an answer box
/// that appears now may focus itself and keep it.
bool get keyboardPrimed {
  final at = _primedAt;
  return at != null && DateTime.now().difference(at) < const Duration(seconds: 4);
}
