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

  test('a shared 10th place takes any of its players, once', () {
    final list = Top10List(id: 'y', prompt: 'T', level: 1, entries: [
      for (var i = 0; i < 9; i++) Top10Entry(rank: i + 1, playerId: 'p$i', name: 'P$i'),
      const Top10Entry(rank: 10, playerId: 'beattie', name: 'James Beattie', alternates: [('keane', 'Robbie Keane')]),
    ]);
    final c = Top10Controller(list: list);
    expect(c.submit(p('keane')), Top10Answer.found);
    expect(c.found[9], 'keane');
    expect(c.submit(p('beattie')), Top10Answer.alreadyFound);
    expect(c.score, 10);
  });

  test('teams take turns: a point each, lives, ends when all are out', () {
    final c = Top10Controller(list: _list, teamCount: 2, answerSeconds: 10);
    expect(c.submit(p('p0')), Top10Answer.found);
    expect(c.currentTeam, 1, reason: 'the turn moves on after a right answer');
    c.submit(p('nope'));
    expect(c.livesLeft, [3, 2]);
    expect(c.currentTeam, 0);
    c.advance(const Duration(seconds: 11)); // too slow
    expect(c.livesLeft, [2, 2]);
    for (var i = 0; i < 4; i++) {
      c.pass();
    }
    expect(c.finished, isTrue);
    expect(c.result().points, {0: 1, 1: 0});
    expect(c.result().solo, isNull);
  });

  test('Top 10 is on the party wheel too, men only', () {
    expect(GameModeId.concreteGames, contains(GameModeId.top10));
    expect(GameModeId.top10.hasWomensGame, isFalse);
  });
}
