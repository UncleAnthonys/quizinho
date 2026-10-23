import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/football_repository.dart';
import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/data/models.dart';

void main() {
  final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
  final source = ChallengeSource(repo);

  test('mask round-trips', () {
    final eras = {Era.noughties, Era.twenties};
    expect(Era.fromMask(Era.maskOf(eras)), eras);
    expect(Era.maskOf(Era.values), Era.allMask);
  });

  test('matches respect the chosen eras', () async {
    final mask = Era.tens.bit;
    final used = <String>{};
    for (var i = 0; i < 5; i++) {
      final m = await repo.pickMatch(eras: mask, exclude: used);
      if (m == null) break;
      used.add(m.id);
      expect(m.year, inInclusiveRange(2010, 2019));
    }
  });

  test('career paths and connections respect the chosen eras', () async {
    final mask = Era.twenties.bit;
    for (var i = 0; i < 10; i++) {
      expect((await repo.pickCareerPath(eras: mask))!.eras & mask, isNot(0));
      expect((await repo.pickClubConnection(eras: mask))!.eras & mask, isNot(0));
    }
  });

  test('a thin era widens instead of running dry', () async {
    // Only one pre-92 match exists; the second request must still get a match.
    final first = await source.match(Difficulty.medium, {}, eras: Era.classic.bit);
    final second = await source.match(Difficulty.medium, {first!.id}, eras: Era.classic.bit);
    expect(second, isNotNull);
  });
}
