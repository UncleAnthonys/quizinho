import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/games/heads_up/heads_up_controller.dart';

Duration secs(double s) => Duration(microseconds: (s * 1e6).round());

void main() {
  HeadsUpController make({int teams = 2}) => HeadsUpController(teamCount: teams, turnSeconds: 30, countdownSeconds: 3);
  const deck = ['A', 'B', 'C', 'D', 'E'];

  test('countdown then first card', () {
    final c = make()..startTurn(deck);
    expect(c.phase, HeadsUpPhase.countdown);
    expect(c.currentCard, isNull);
    c.advance(secs(3.1));
    expect(c.phase, HeadsUpPhase.playing);
    expect(c.currentCard, 'A');
  });

  test('correct scores, pass does not, both move to next card', () {
    final c = make()..startTurn(deck);
    c.advance(secs(3.1));
    c.correct();
    expect(c.currentCard, 'B');
    c.pass();
    expect(c.currentCard, 'C');
    c.correct();
    expect(c.correctByTeam[0], 2);
    expect(c.turnResults.map((r) => r.correct), [true, false, true]);
  });

  test('timer ends the turn; teams rotate; round finishes after everyone', () {
    final c = make()..startTurn(deck);
    c.advance(secs(3.1));
    c.correct();
    c.advance(secs(30.1));
    expect(c.phase, HeadsUpPhase.turnOver);
    c.nextTurn();
    expect(c.phase, HeadsUpPhase.ready);
    expect(c.currentTeam, 1);
    c.startTurn(deck);
    c.advance(secs(3.1));
    c.correct();
    c.correct();
    c.advance(secs(30.1));
    c.nextTurn();
    expect(c.phase, HeadsUpPhase.finished);
    expect(c.result().points, {0: 0, 1: HeadsUpController.winPoints});
  });

  test('running out of cards ends the turn early', () {
    final c = make()..startTurn(['A', 'B']);
    c.advance(secs(3.1));
    c.correct();
    c.correct();
    expect(c.phase, HeadsUpPhase.turnOver);
  });

  test('taps are ignored outside play', () {
    final c = make();
    c.correct();
    c.startTurn(deck);
    c.correct(); // during countdown
    expect(c.correctByTeam[0], 0);
  });

  test('bundled packs parse and have no duplicate cards within a pack', () {
    final packs = parseHeadsUpPacks(File('assets/packs/heads_up.json').readAsStringSync());
    expect(packs.length, greaterThanOrEqualTo(5));
    for (final p in packs) {
      expect(p.cards.length, greaterThanOrEqualTo(30), reason: p.title);
      expect(p.cards.toSet().length, p.cards.length, reason: 'duplicate in ${p.title}');
    }
  });
}
