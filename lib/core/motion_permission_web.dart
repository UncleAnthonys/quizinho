import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// iPhone Safari: asks to read the tilt (must run inside a tap). Elsewhere
/// there's nothing to ask, and this does nothing.
void requestMotionPermission() {
  try {
    final dme = globalContext.getProperty<JSObject?>('DeviceMotionEvent'.toJS);
    if (dme != null && dme.has('requestPermission')) {
      dme.callMethod<JSAny?>('requestPermission'.toJS);
    }
  } catch (_) {}
}
