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
  Stream<Object?> watch(String path) async* {
    // Reconnects after a dropped connection (tunnels, lifts, bad pub signal).
    while (true) {
      Object? tree;
      try {
        await for (final e in sseEvents(_url(path))) {
          if (e.type == 'put' || e.type == 'patch') {
            final msg = jsonDecode(e.data) as Map;
            tree = writeAt(tree, pathParts('${msg['path']}'), msg['data'], merge: e.type == 'patch');
            yield tree;
          } else if (e.type == 'cancel') {
            break;
          }
        }
      } catch (e) {
        debugPrint('Room stream dropped: $e');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
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
