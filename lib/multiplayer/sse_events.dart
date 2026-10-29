// Server-sent events from the database's streaming REST API: app builds read
// the HTTP stream directly, browsers use EventSource.
export 'sse_events_io.dart' if (dart.library.js_interop) 'sse_events_web.dart';

/// One event: "put" / "patch" with JSON data {"path": "/…", "data": …}.
class SseEvent {
  const SseEvent(this.type, this.data);
  final String type;
  final String data;
}
