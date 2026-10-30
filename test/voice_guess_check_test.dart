import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/json_football_repository.dart';

/// Only runs in the "Voice guess" workflow (needs build/voice_guess.json):
/// which machine mishearings Quizinho already accepts as the right answer.
void main() {
  final file = File('build/voice_guess.json');
  test('generated mishearings vs our matching', () {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    final rows = (jsonDecode(file.readAsStringSync()) as List).cast<Map<String, dynamic>>();
    var ok = 0, total = 0;
    final misses = <Map<String, String>>[];
    for (final r in rows) {
      for (final engine in const ['vosk', 'whisper']) {
        final heard = '${r[engine] ?? ''}'.trim();
        if (heard.isEmpty) continue;
        total++;
        final got = repo.players.resolveSpoken([heard], isAnswer: (p) => p.id == r['id'])?.id;
        if (got == r['id']) {
          ok++;
        } else {
          misses.add({'id': '${r['id']}', 'name': '${r['name']}', 'engine': engine, 'heard': heard});
        }
      }
    }
    File('build/voice_guess_misses.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(misses));
    // ignore: avoid_print
    print('::notice title=Voice guess::$ok of $total machine mishearings already accepted; ${misses.length} would fail');
  }, skip: file.existsSync() ? false : 'no build/voice_guess.json (Voice guess workflow only)');
}
