import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/games/pointless/pointless_controller.dart';

Duration secs(double s) => Duration(microseconds: (s * 1e6).round());
Player pl(String id) => Player(id: id, name: id.toUpperCase(), fame: 3);

BiddingCategory cat() => BiddingCategory(
      id: 'test',
      prompt: 'Test',
      difficulty: 1,
      answerIds: {'famous', 'mid', 'obscure', 'seventy'},
      scores: {'famous': 60, 'mid': 20, 'obscure': 0, 'seventy': 70},
    );

PointlessController two() => PointlessController(category: cat(), teamCount: 2, answerSeconds: 30, revealSeconds: 1)..start();

void main() {
  test('teams alternate A, B, A, B and the round ends after 2 each', () {
    final c = two();
    for (final (team, who) in [(0, 'famous'), (1, 'mid'), (0, 'obscure'), (1, 'nobody')]) {
      expect(c.currentTeam, team);
      c.submit(pl(who));
      expect(c.phase, PtPhase.reveal);
      c.next();
    }
    expect(c.phase, PtPhase.finished);
    expect((c.totalOf(0), c.totalOf(1)), (60, 120));
  });

  test('lowest total wins 3, each pointless answer is +1', () {
    final c = two()..submit(pl('obscure'));
    c.next();
    c.submit(pl('famous'));
    c.next();
    c.submit(pl('mid'));
    c.next();
    c.submit(pl('mid')); // already said: doesn't cost the turn
    expect(c.lastEvent, PtEvent.duplicate);
    expect(c.phase, PtPhase.answering);
    c.giveUp();
    c.next();
    expect(c.winners, {0});
    expect(c.result().points, {0: 3 + 1, 1: 0});
  });

  test('wrong answers and running out of time score 100', () {
    final c = two()..submit(pl('nobody'));
    expect(c.lastAnswer!.score, 100);
    expect(c.lastEvent, PtEvent.wrong);
    c.next();
    c.advance(secs(31));
    expect(c.lastAnswer!.score, 100);
    expect(c.lastEvent, PtEvent.timeUp);
  });

  test('reveal moves on by itself', () {
    final c = two()..submit(pl('mid'));
    c.advance(secs(1.1));
    expect(c.phase, PtPhase.answering);
    expect(c.currentTeam, 1);
  });

  test('a tie shares the win', () {
    final c = two()..submit(pl('mid')); // A 20
    c.next();
    c.submit(pl('mid')); // duplicate: still B's go
    c.submitDisputed('Someone else'); // B 50 (room vote)
    c.next();
    c.giveUp(); // A 100
    c.next();
    c.submit(pl('seventy')); // B 70
    c.next();
    expect((c.totalOf(0), c.totalOf(1)), (120, 120));
    expect(c.winners, {0, 1});
    expect(c.result().points, {0: 3, 1: 3});
  });

  test('bundled categories carry a score for every answer, some pointless', () {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    var pointless = 0;
    for (final b in repo.bidding) {
      expect(b.scores.keys.toSet(), b.answerIds, reason: b.id);
      for (final s in b.scores.values) {
        expect(s, inInclusiveRange(0, 100));
      }
      if (b.scores.values.contains(0)) pointless++;
    }
    expect(pointless, greaterThan(repo.bidding.length ~/ 3));
  });
}
