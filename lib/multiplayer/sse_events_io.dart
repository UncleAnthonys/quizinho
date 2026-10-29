import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sse_events.dart';

/// Reads [url] as a server-sent event stream until it closes.
Stream<SseEvent> sseEvents(Uri url) async* {
  final client = http.Client();
  try {
    final req = http.Request('GET', url)..headers['Accept'] = 'text/event-stream';
    final res = await client.send(req);
    if (res.statusCode >= 300) throw http.ClientException('HTTP ${res.statusCode}', url);
    String? event;
    final data = StringBuffer();
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data.write(line.substring(5).trim());
      } else if (line.isEmpty) {
        if (event != null) yield SseEvent(event, data.toString());
        event = null;
        data.clear();
      }
    }
  } finally {
    client.close();
  }
}
