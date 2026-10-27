import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/data/models.dart';

void main() {
  test('weighted pick favours heavier items in proportion', () {
    final random = Random(7);
    final counts = <String, int>{'classic': 0, 'rare': 0};
    for (var i = 0; i < 20000; i++) {
      final x = HistoricMatch.weightedPick(['classic', 'rare'], (s) => s == 'classic' ? 1.0 : 0.2, random);
      counts[x] = counts[x]! + 1;
    }
    final share = counts['rare']! / 20000;
    expect(share, closeTo(0.2 / 1.2, 0.02)); // ~17%
  });

  test('bundled line-ups: classics outweigh the sprinkled-in ones', () {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    final full = repo.matches.where((m) => m.weight == 1).length;
    expect(full, greaterThanOrEqualTo(40));
    for (final m in repo.matches) {
      expect(m.weight, inInclusiveRange(0.1, 1.0), reason: m.id);
    }
  });
}
