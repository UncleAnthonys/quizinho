import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'sse_events.dart';

/// Reads [url] with the browser's EventSource (which reconnects by itself).
Stream<SseEvent> sseEvents(Uri url) {
  web.EventSource? source;
  late final StreamController<SseEvent> out;
  out = StreamController<SseEvent>(
    onListen: () {
      final s = web.EventSource(url.toString());
      source = s;
      for (final type in const ['put', 'patch', 'cancel', 'keep-alive']) {
        s.addEventListener(
          type,
          ((web.Event e) {
            final data = (e as web.MessageEvent).data.dartify();
            out.add(SseEvent(type, data is String ? data : '$data'));
          }).toJS,
        );
      }
    },
    onCancel: () => source?.close(),
  );
  return out.stream;
}
