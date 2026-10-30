import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Chrome's speech recogniser, given the names worth listening for (the right
/// answers) so it leans towards them — like the iPhone app's player model.
/// Only works where Chrome can recognise on the device; anywhere else
/// [ready] is false and the normal browser speech is used instead.
class HintedSpeech {
  static const _lang = 'en-GB';
  static Future<bool>? _ready;
  static bool _installTried = false;

  /// Turned off for the session after the browser refuses hints.
  static bool _refused = false;

  /// For the joined phone's screen: 'checking', 'ready', 'downloading',
  /// 'no on-device speech' (Chrome, but this phone can't) or 'unsupported'
  /// (not Chrome — e.g. any iPhone browser).
  static final ValueNotifier<String> status = ValueNotifier('checking');

  /// Asks for the microphone now, from a tap (picking your name), so the
  /// browser's permission prompt shows at a calm moment — not when the answer
  /// box opens mid-question, where some browsers block or hide it.
  static Future<void> primeMic() async {
    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
          .toDart;
      for (final t in stream.getTracks().toDart) {
        t.stop();
      }
    } catch (e) {
      debugPrint('Mic not allowed: $e');
    }
  }

  static JSObject? get _class {
    for (final name in const ['SpeechRecognition', 'webkitSpeechRecognition']) {
      final c = globalContext[name];
      if (c != null && c.typeofEquals('function')) return c as JSObject;
    }
    return null;
  }

  static JSAny get _options => {'langs': [_lang], 'processLocally': true}.jsify()!;

  /// True when hints will work on this phone. The first check also starts
  /// Chrome fetching its on-device speech pack, so a later match can use it.
  static Future<bool> ready() {
    if (_refused) return Future.value(false);
    return _ready ??= _check().catchError((Object e) {
      debugPrint('Hinted speech check failed: $e');
      status.value = 'unsupported';
      return false;
    });
  }

  static Future<bool> _check() async {
    final c = _class;
    final proto = c?['prototype'];
    if (c == null ||
        proto == null ||
        !(proto as JSObject).has('phrases') ||
        !globalContext.has('SpeechRecognitionPhrase') ||
        !c.has('available')) {
      status.value = 'unsupported';
      return false;
    }
    final state = (await c.callMethod<JSPromise<JSString>>('available'.toJS, _options).toDart).toDart;
    if (state == 'available') {
      status.value = 'ready';
      return true;
    }
    if (state == 'downloadable' || state == 'downloading') {
      status.value = 'downloading';
      if (!_installTried && c.has('install')) {
        _installTried = true;
        unawaited(c.callMethod<JSPromise<JSAny?>>('install'.toJS, _options).toDart.then((_) {
          _ready = null; // look again: it should be ready now
          unawaited(ready());
        }, onError: (Object e) {
          debugPrint('Speech pack not installed: $e');
          status.value = 'no on-device speech';
        }));
      }
      return false;
    }
    status.value = 'no on-device speech';
    return false;
  }

  JSObject? _rec;

  /// Listens for one answer. With [boost] (only once [ready]), on-device and
  /// leaning towards [hints]; without, the browser's normal speech — one
  /// utterance at a time, which avoids Android Chrome repeating words
  /// ("Dwight Dwight Yorke") in continuous mode. False = couldn't start.
  bool listen({
    required List<String> hints,
    required void Function(String words) onWords,
    required void Function(List<String> alternatives) onDone,
    bool boost = true,
  }) {
    final c = _class;
    final phrase = globalContext['SpeechRecognitionPhrase'];
    if (c == null) return false;
    if (boost && (phrase == null || _refused)) return false;
    stop();
    var finished = false;
    var last = '';
    void finish(List<String> alts) {
      if (finished) return;
      finished = true;
      onDone(alts);
    }

    try {
      final r = (c as JSFunction).callAsConstructor<JSObject>();
      r['lang'] = _lang.toJS;
      r['continuous'] = false.toJS;
      r['interimResults'] = true.toJS;
      r['maxAlternatives'] = 5.toJS;
      if (boost) {
        r['processLocally'] = true.toJS;
        r['phrases'] = [
          for (final h in hints) (phrase! as JSFunction).callAsConstructor<JSObject>(h.toJS, 3.0.toJS),
        ].toJS;
      }
      r['onresult'] = ((JSObject e) {
        final results = e['results']! as JSObject;
        final n = (results['length']! as JSNumber).toDartInt;
        var text = '';
        var isFinal = false;
        var alts = <String>[];
        for (var i = 0; i < n; i++) {
          final res = results.callMethod<JSObject>('item'.toJS, i.toJS);
          text += _transcript(res, 0);
          if (i == n - 1) {
            isFinal = (res['isFinal'] as JSBoolean?)?.toDart ?? false;
            final m = (res['length']! as JSNumber).toDartInt;
            alts = [for (var j = 0; j < m; j++) _transcript(res, j)]..removeWhere((a) => a.trim().isEmpty);
          }
        }
        last = text;
        onWords(text);
        if (isFinal) finish(n == 1 && alts.isNotEmpty ? alts : [text]);
      }).toJS;
      r['onerror'] = ((JSObject e) {
        final error = (e['error'] as JSString?)?.toDart ?? '';
        debugPrint('Hinted speech error: $error');
        // The browser won't take hints after all: use normal speech from now on.
        if (boost && const {'phrases-not-supported', 'language-not-supported', 'service-not-allowed'}.contains(error)) {
          _refused = true;
          status.value = 'unsupported';
        }
      }).toJS;
      r['onend'] = ((JSAny? _) => finish(last.trim().isEmpty ? const [] : [last])).toJS;
      r.callMethod<JSAny?>('start'.toJS);
      _rec = r;
      return true;
    } catch (e) {
      debugPrint('Browser speech failed: $e');
      if (boost) _refused = true;
      return false;
    }
  }

  static String _transcript(JSObject result, int i) =>
      (result.callMethod<JSObject>('item'.toJS, i.toJS)['transcript'] as JSString?)?.toDart ?? '';

  void stop() {
    final r = _rec;
    _rec = null;
    if (r == null) return;
    r['onresult'] = null;
    r['onend'] = null;
    r['onerror'] = null;
    try {
      r.callMethod<JSAny?>('abort'.toJS);
    } catch (_) {}
  }
}
