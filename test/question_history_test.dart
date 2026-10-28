import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/football_repository.dart';
import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/data/models.dart';

void main() {
  final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());

  test('a new match does not repeat questions from earlier matches', () async {
    final history = QuestionHistory();
    final source = ChallengeSource(repo, history: history);
    // Match 1 and match 2 each start with nothing used, like real matches.
    final first = {for (var i = 0; i < 10; i++) (await source.match(Difficulty.easy, {}))!.id};
    final second = <String>{};
    for (var i = 0; i < 3; i++) {
      second.add((await source.match(Difficulty.easy, second))!.id);
    }
    expect(second.intersection(first), isEmpty);
  });

  test('when everything has been seen, repeats come back rather than running dry', () async {
    final history = QuestionHistory();
    final source = ChallengeSource(repo, history: history);
    for (var i = 0; i < 40; i++) {
      expect(await source.match(Difficulty.easy, {}), isNotNull);
    }
  });

  test('history is stored and read back through the given storage', () {
    final store = <String, List<String>>{};
    QuestionHistory(read: (k) => store[k], write: (k, v) => store[k] = [...v]).add('conn', 'a|b');
    expect(QuestionHistory(read: (k) => store[k]).seen('conn'), {'a|b'});
  });
}
