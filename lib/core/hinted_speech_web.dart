import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

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
      return false;
    });
  }

  static Future<bool> _check() async {
    final c = _class;
    if (c == null) return false;
    final proto = c['prototype'];
    if (proto == null || !(proto as JSObject).has('phrases')) return false;
    if (!globalContext.has('SpeechRecognitionPhrase') || !c.has('available')) return false;
    final state = (await c.callMethod<JSPromise<JSString>>('available'.toJS, _options).toDart).toDart;
    if (state == 'available') return true;
    if ((state == 'downloadable' || state == 'downloading') && !_installTried && c.has('install')) {
      _installTried = true;
      unawaited(c.callMethod<JSPromise<JSAny?>>('install'.toJS, _options).toDart.then((_) {
        _ready = null; // look again next time
      }, onError: (Object e) => debugPrint('Speech pack not installed: $e')));
    }
    return false;
  }

  JSObject? _rec;

  /// Listens for one answer, leaning towards [hints]. False = couldn't start.
  bool listen({
    required List<String> hints,
    required void Function(String words) onWords,
    required void Function(List<String> alternatives) onDone,
  }) {
    final c = _class;
    final phrase = globalContext['SpeechRecognitionPhrase'];
    if (c == null || phrase == null || _refused) return false;
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
      r['processLocally'] = true.toJS;
      r['phrases'] = [
        for (final h in hints) (phrase as JSFunction).callAsConstructor<JSObject>(h.toJS, 3.0.toJS),
      ].toJS;
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
        if (const {'phrases-not-supported', 'language-not-supported', 'service-not-allowed'}.contains(error)) {
          _refused = true;
        }
      }).toJS;
      r['onend'] = ((JSAny? _) => finish(last.trim().isEmpty ? const [] : [last])).toJS;
      r.callMethod<JSAny?>('start'.toJS);
      _rec = r;
      return true;
    } catch (e) {
      debugPrint('Hinted speech failed: $e');
      _refused = true;
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
