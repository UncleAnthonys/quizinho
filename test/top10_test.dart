import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/data/question_history.dart';
import 'package:quizinho/data/top10.dart';
import 'package:quizinho/domain/game_mode.dart';
import 'package:quizinho/games/top10/top10_controller.dart';

Player p(String id) => Player(id: id, name: id, fame: 3);

final _list = Top10List(id: 'x', prompt: 'Test', level: 1, entries: [
  for (var i = 0; i < 10; i++) Top10Entry(rank: i + 1, playerId: 'p$i', name: 'P$i'),
]);

void main() {
  test('each one found is worth 10; three wrong and it is over', () {
    final c = Top10Controller(list: _list);
    expect(c.submit(p('p3')), Top10Answer.found);
    expect(c.submit(p('p3')), Top10Answer.alreadyFound);
    expect(c.submit(p('nope1')), Top10Answer.wrong);
    expect(c.submit(p('nope2')), Top10Answer.wrong);
    expect(c.finished, isFalse);
    c.submit(p('nope3'));
    expect(c.finished, isTrue);
    expect(c.result().solo, 10);
  });

  test('all ten is 100', () {
    final c = Top10Controller(list: _list);
    for (var i = 0; i < 10; i++) {
      c.submit(p('p$i'));
    }
    expect(c.finished, isTrue);
    expect(c.score, 100);
  });

  test('giving up shows the rest', () {
    final c = Top10Controller(list: _list)..submit(p('p0'));
    c.giveUp();
    expect(c.finished, isTrue);
    expect(c.score, 10);
  });

  test('the bank: lists of ten, no repeats until it runs dry', () {
    final bank = Top10Bank.parse(File('assets/db/top10.json').readAsStringSync());
    expect(bank.lists.length, greaterThan(15));
    expect(bank.lists.every((l) => l.entries.length == 10), isTrue);
    final h = QuestionHistory();
    final seen = <String>{};
    for (var i = 0; i < bank.lists.length; i++) {
      seen.add(bank.pick(difficulty: Difficulty.expert, history: h)!.id);
    }
    expect(seen.length, greaterThan(5));
  });

  test('Top 10 is solo only', () {
    expect(GameModeId.concreteGames, isNot(contains(GameModeId.top10)));
    expect(GameModeId.top10.soloOnly, isTrue);
  });
}
