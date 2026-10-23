import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/games/starting_xi/starting_xi_controller.dart';

import 'fixtures.dart';

Duration secs(double s) => Duration(microseconds: (s * 1e6).round());

void main() {
  StartingXiController make({int teams = 2, int lives = 3, int start = 0}) =>
      StartingXiController(match: tinyMatch(), teamCount: teams, lives: lives, startTeam: start, turnSeconds: 10);

  test('timer only runs after the handover tap', () {
    final c = make();
    expect(c.phase, BombPhase.handover);
    c.advance(secs(30));
    expect(c.phase, BombPhase.handover);
    c.startTurn();
    expect(c.phase, BombPhase.ticking);
  });

  test('correct name fills a slot and passes to the next team', () {
    final c = make()..startTurn();
    expect(c.submit(henry), SubmitResult.correct);
    expect(c.namedBy[henry.id], 0);
    expect(c.currentTeam, 1);
    expect(c.phase, BombPhase.handover);
  });

  test('repeating a named player is rejected without penalty', () {
    final c = make()..startTurn();
    c.submit(henry);
    c.startTurn();
    expect(c.submit(henry), SubmitResult.alreadyNamed);
    expect(c.livesLeft[1], 3);
    expect(c.phase, BombPhase.ticking);
  });

  test('wrong name costs a life', () {
    final c = make()..startTurn();
    expect(c.submit(cr7), SubmitResult.wrong);
    expect(c.phase, BombPhase.exploded);
    expect(c.livesLeft[0], 2);
  });

  test('timer expiry explodes the bomb', () {
    final c = make()..startTurn();
    c.advance(secs(10.1));
    expect(c.phase, BombPhase.exploded);
    expect(c.livesLeft[0], 2);
  });

  test('sudden death: last team standing gets the bonus', () {
    final c = make(lives: 1)..startTurn();
    c.submit(henry); // team 0 +1
    c.startTurn();
    c.pass(); // team 1 out
    c.continueAfterExplosion();
    expect(c.phase, BombPhase.finished);
    expect(c.bonusTeams, [0]);
    final r = c.result();
    expect(r.points[0], 1 + StartingXiController.survivorBonus);
    expect(r.points[1], 0);
  });

  test('eliminated teams are skipped in the rotation', () {
    final c = make(teams: 3, lives: 1)..startTurn();
    c.pass(); // team 0 out
    c.continueAfterExplosion();
    expect(c.currentTeam, 1);
    c.startTurn();
    c.submit(henry);
    expect(c.currentTeam, 2);
    c.startTurn();
    c.submit(fabregas);
    expect(c.currentTeam, 1); // 0 skipped
  });

  test('completing the XI ends the round; most names wins the bonus', () {
    final c = make()..startTurn();
    c.submit(henry); // team 0
    c.startTurn();
    c.submit(fabregas); // team 1
    c.startTurn();
    c.submit(zlatan); // team 0
    expect(c.isComplete, isTrue);
    expect(c.phase, BombPhase.finished);
    expect(c.bonusTeams, [0]);
    expect(c.result().points, {0: 2 + StartingXiController.survivorBonus, 1: 1});
  });
}
