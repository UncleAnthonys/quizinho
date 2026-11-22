import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/domain/tournament.dart';
import 'package:quizinho/games/penalties/penalty_kick.dart';
import 'package:quizinho/games/penalties/shootout_controller.dart';

const _kick = PenaltyKick(kind: KickKind.twoClubs, ask: 'NAME A PLAYER', answers: {'yes'}, reveal: 'YES');
const _tap = PenaltyKick(kind: KickKind.overUnder, ask: 'OVER OR UNDER', options: ['OVER 100', 'UNDER 100'], correctOption: 0, reveal: '120');

/// One kick: [scored] or missed, then on to the next.
void kick(ShootoutController c, bool scored) {
  c.start(_kick);
  c.submit(scored ? 'yes' : 'no');
  c.next();
}

void main() {
  test('takers alternate, and a right answer is a goal', () {
    final c = ShootoutController(teams: [0, 1]);
    expect(c.taker, 0);
    kick(c, true);
    expect(c.taker, 1);
    expect(c.kicks[0], [true]);
    expect(c.phase, ShootoutPhase.handover);
  });

  test('over/under: the right button scores', () {
    final c = ShootoutController(teams: [0, 1])..start(_tap);
    c.choose(1);
    expect(c.lastScored, isFalse);
    c.next();
    c
      ..start(_tap)
      ..choose(0);
    expect(c.lastScored, isTrue);
  });

  test('running out of time is a miss', () {
    final c = ShootoutController(teams: [0, 1], kickSeconds: 10)..start(_kick);
    c.advance(const Duration(seconds: 11));
    expect(c.phase, ShootoutPhase.result);
    expect(c.lastScored, isFalse);
  });

  test('ends early when one team can't be caught', () {
    final c = ShootoutController(teams: [0, 1]);
    // 3-0 after three each: team 1 can only reach 2.
    for (var i = 0; i < 3; i++) {
      kick(c, true);
      kick(c, false);
    }
    expect(c.phase, ShootoutPhase.finished);
    expect(c.winner, 0);
  });

  test('level after five each: sudden death until a round splits them', () {
    final c = ShootoutController(teams: [0, 1]);
    for (var i = 0; i < 5; i++) {
      kick(c, true);
      kick(c, true);
    }
    expect(c.phase, ShootoutPhase.handover);
    expect(c.suddenDeath, isTrue);
    kick(c, true);
    kick(c, true); // still level
    expect(c.phase, ShootoutPhase.handover);
    kick(c, false);
    expect(c.phase, ShootoutPhase.handover); // team 1 still to kick
    kick(c, true);
    expect(c.phase, ShootoutPhase.finished);
    expect(c.winner, 1);
  });

  test('three teams level: in sudden death, the ones behind drop out', () {
    final c = ShootoutController(teams: [0, 1, 2], kicksEach: 1);
    kick(c, true);
    kick(c, true);
    kick(c, false);
    expect(c.phase, ShootoutPhase.handover);
    expect(c.alive, [0, 1]);
    kick(c, false);
    kick(c, true);
    expect(c.winner, 1);
  });

  test('the penalty winner is the champion, and survives a save', () {
    final t = Tournament(TournamentConfig(
      teams: [TeamSetup(name: 'Home', colorIndex: 0), TeamSetup(name: 'Away', colorIndex: 1)],
      rounds: 1,
    ));
    t.recordRound(RoundResult(mode: t.config.modes.first, points: {0: 3, 1: 3}));
    expect(t.drawn, isTrue);
    expect(t.champions, [0, 1]);
    t
      ..penaltyWinner = 1
      ..penaltyGoals = {0: 2, 1: 4};
    expect(t.champions, [1]);
    expect(t.penaltyScore, '4–2');
    final back = Tournament.fromJson(t.toJson())!;
    expect(back.champions, [1]);
    expect(back.penaltyScore, '4–2');
  });
}
