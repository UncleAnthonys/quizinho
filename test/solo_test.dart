import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/games/club_connections/club_connections_controller.dart';
import 'package:quizinho/games/starting_xi/starting_xi_controller.dart';

import 'fixtures.dart';

Duration secs(double s) => Duration(microseconds: (s * 1e6).round());

void main() {
  test('solo Connections: right answers score, quicker scores more, out of 100', () {
    final c = ClubConnectionsController(teamCount: 1, questions: [arsenalBarca(), arsenalBarca()]);
    c.buzz(0); // straight away: full speed points
    c.submit(henry); // famous: no rare-pick bonus
    c.next();
    c.giveUp(); // second one missed
    c.next();
    final solo = c.result().solo!;
    // 12 + 6 for speed on one of two questions (20 each) = 18/40.
    expect(solo, 45);
  });

  test('solo XI Bomb plays on until your lives are gone, scored on how much you named', () {
    final c = StartingXiController(match: tinyMatch(), teamCount: 1, lives: 2, turnSeconds: 10)..startTurn();
    c.submit(henry);
    expect(c.phase, BombPhase.handover); // back to you
    c.startTurn();
    c.pass(); // a life gone
    c.continueAfterExplosion();
    expect(c.phase, isNot(BombPhase.finished));
    c.startTurn();
    c.pass();
    c.continueAfterExplosion();
    expect(c.phase, BombPhase.finished);
    expect(c.result().solo, (100 / c.match.lineup.length).round());
  });

  test('solo answers straight in, no buzzer; the clock left counts for speed', () {
    final c = ClubConnectionsController(teamCount: 1, questions: [arsenalBarca()]);
    c.advance(secs(c.openSeconds / 2)); // half the clock gone
    c.submitSolo(henry);
    expect(c.outcome?.scored, isTrue);
    expect(c.lastSolo, 15); // 12 + 6 × half
  });

  test('team games have no solo score', () {
    final c = ClubConnectionsController(teamCount: 2, questions: [arsenalBarca()]);
    expect(c.result().solo, isNull);
  });
}
