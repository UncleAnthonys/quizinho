import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../multiplayer/rooms_config.dart';

/// Real mishearings, learnt from games: when a spoken answer didn't match
/// and the player then typed or tapped the right answer, what the phone heard
/// is saved against that player (e.g. "deli for you" → Deulofeu). Collected
/// into data_pipeline/seed/spoken_overrides.json, so voice gets better for
/// everyone. Only the heard words and the player — nothing about who said it.
class VoiceMissLog {
  VoiceMissLog({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// Same free database as rooms, under voicemisses/ (write-only for apps).
  static bool get enabled => roomsDatabaseUrl.isNotEmpty;

  static String get _source => kIsWeb ? 'web' : defaultTargetPlatform.name;

  void report({required List<String> heard, required String playerId}) {
    final h = [for (final a in heard) a.trim()]..removeWhere((a) => a.isEmpty);
    if (!enabled || h.isEmpty) return;
    _client
        .post(
          Uri.parse('$roomsDatabaseUrl/voicemisses.json'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'h': h.take(5).map((a) => a.length > 80 ? a.substring(0, 80) : a).toList(),
            'p': playerId,
            's': _source,
            'at': {'.sv': 'timestamp'},
          }),
        )
        .then((r) {
      if (r.statusCode >= 300) debugPrint('Voice miss not saved: HTTP ${r.statusCode}');
    }, onError: (Object e) => debugPrint('Voice miss not saved: $e'));
  }
}
