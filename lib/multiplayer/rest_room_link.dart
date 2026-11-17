import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'room_link.dart';
import 'sse_events.dart';

/// Firebase Realtime Database over its REST API: writes are plain HTTPS
/// requests, reads are a live event stream. No SDK, so it behaves the same in
/// the app and in a phone's browser.
class RestRoomLink extends RoomLink {
  RestRoomLink(String databaseUrl) : _base = databaseUrl.replaceAll(RegExp(r'/+$'), '');

  final String _base;
  final _client = http.Client();

  Uri _url(String path) => Uri.parse('$_base/${pathParts(path).join('/')}.json');

  @override
  Stream<Object?> watch(String path) {
    // Built on a controller, not an async* loop: cancelling an async*
    // generator only takes effect at its next yield, and a finished room
    // never sends another update - so every game a joined phone left kept
    // its connections open. Browsers allow about six to one server, so after
    // a few tournaments the phone's own answers queued behind dead streams.
    late final StreamController<Object?> out;
    StreamSubscription<SseEvent>? sub;
    Timer? retry;
    var closed = false;
    late final void Function() reconnect;

    void connect() {
      if (closed) return;
      Object? tree;
      // The database sends a keep-alive every ~30 s: hearing nothing for
      // longer means a dead connection (phone slept, Wi-Fi switched) that
      // never reported an error - drop it and reconnect.
      sub = sseEvents(_url(path)).timeout(const Duration(seconds: 45)).listen(
        (e) {
          if (e.type == 'put' || e.type == 'patch') {
            final msg = jsonDecode(e.data) as Map;
            tree = writeAt(tree, pathParts('${msg['path']}'), msg['data'], merge: e.type == 'patch');
            if (!closed) out.add(tree);
          } else if (e.type == 'cancel') {
            reconnect();
          }
        },
        onError: (Object e) {
          debugPrint('Room stream dropped: $e');
          reconnect();
        },
        onDone: reconnect,
        cancelOnError: true,
      );
    }

    // Reconnects after a dropped connection (tunnels, lifts, bad pub signal).
    reconnect = () {
      final old = sub;
      sub = null;
      unawaited(old?.cancel());
      retry?.cancel();
      if (!closed) retry = Timer(const Duration(seconds: 1), connect);
    };

    out = StreamController<Object?>(
      onListen: connect,
      onCancel: () async {
        closed = true;
        retry?.cancel();
        final old = sub;
        sub = null;
        await old?.cancel(); // closes the connection now
      },
    );
    return out.stream;
  }

  Future<http.Response> _send(String method, String path, Object? body) async {
    final req = http.Request(method, _url(path))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    final res = await http.Response.fromStream(await _client.send(req));
    if (res.statusCode >= 300) {
      throw http.ClientException('Room $method failed: HTTP ${res.statusCode} ${res.body}', req.url);
    }
    return res;
  }

  @override
  Future<void> put(String path, Object? value) => _send('PUT', path, value);

  @override
  Future<void> patch(String path, Map<String, Object?> values) => _send('PATCH', path, values);

  @override
  Future<String> push(String path, Object? value) async {
    final res = await _send('POST', path, value);
    return '${(jsonDecode(res.body) as Map)['name']}';
  }

  @override
  void close() => _client.close();
}
