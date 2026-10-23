import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/json_football_repository.dart';

/// The web build reads assets/db/football.json — check the real file parses
/// and every challenge type can be served from it.
void main() {
  test('bundled football.json loads and serves every game', () async {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    expect(repo.players.length, greaterThan(100));

    final conn = await repo.pickClubConnection();
    expect(conn, isNotNull);
    expect(conn!.answerIds, isNotEmpty);
    for (final id in conn.answerIds) {
      expect(repo.players.byId(id), isNotNull, reason: 'answer $id missing from players');
    }

    final career = await repo.pickCareerPath();
    expect(career!.spells.length, greaterThanOrEqualTo(3));

    final match = await repo.pickMatch();
    expect(match!.lineup.length, 11);
  });
}
