import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sse_events.dart';

/// Reads [url] as a server-sent event stream until it closes. Cancelling
/// closes the connection at once (an async* reader would wait for the next
/// event to notice).
Stream<SseEvent> sseEvents(Uri url) {
  final client = http.Client();
  late final StreamController<SseEvent> out;
  Future<void> read() async {
    try {
      final req = http.Request('GET', url)..headers['Accept'] = 'text/event-stream';
      final res = await client.send(req);
      if (res.statusCode >= 300) throw http.ClientException('HTTP ${res.statusCode}', url);
      String? event;
      final data = StringBuffer();
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (out.isClosed) break;
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          data.write(line.substring(5).trim());
        } else if (line.isEmpty) {
          if (event != null) out.add(SseEvent(event, data.toString()));
          event = null;
          data.clear();
        }
      }
    } catch (e) {
      if (!out.isClosed) out.addError(e);
    } finally {
      client.close();
      if (!out.isClosed) await out.close();
    }
  }

  out = StreamController<SseEvent>(onListen: () => unawaited(read()), onCancel: client.close);
  return out.stream;
}
