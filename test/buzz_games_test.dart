import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/games/buzz_race_controller.dart';
import 'package:quizinho/games/career_path/career_path_controller.dart';
import 'package:quizinho/games/club_connections/club_connections_controller.dart';

import 'fixtures.dart';

Duration secs(double s) => Duration(microseconds: (s * 1e6).round());

void main() {
  group('Club Connections', () {
    ClubConnectionsController make({int teams = 2}) =>
        ClubConnectionsController(teamCount: teams, questions: [arsenalBarca(), arsenalJuve()]);

    test('first buzz wins the right to answer', () {
      final c = make();
      c.buzz(1);
      expect(c.phase, BuzzPhase.answering);
      expect(c.answeringTeam, 1);
      c.buzz(0); // too late
      expect(c.answeringTeam, 1);
    });

    test('correct answer scores 2 and resolves', () {
      final c = make();
      c.buzz(0);
      c.submit(henry);
      expect(c.phase, BuzzPhase.resolved);
      expect(c.roundPoints[0], 2);
      expect(c.outcome!.player!.id, henry.id);
      expect(c.lastEvent, GameEvent.correct);
    });

    test('wrong answer locks out and the other team can steal', () {
      final c = make();
      c.buzz(0);
      c.submit(zlatan);
      expect(c.phase, BuzzPhase.open);
      expect(c.lockedOut, {0});
      expect(c.canBuzz(0), isFalse);
      expect(c.secondsLeft, greaterThanOrEqualTo(c.stealSeconds));
      c.buzz(1);
      c.submit(fabregas);
      expect(c.roundPoints, {0: 0, 1: 2});
      expect(c.lastEvent, GameEvent.steal);
    });

    test('everyone wrong → nobody scores', () {
      final c = make();
      c.buzz(0);
      c.submit(zlatan);
      c.buzz(1);
      c.submit(cr7);
      expect(c.phase, BuzzPhase.resolved);
      expect(c.outcome!.scored, isFalse);
      expect(c.roundPoints.values.every((p) => p == 0), isTrue);
    });

    test('lesser-known correct answer earns deep-cut bonus', () {
      final c = ClubConnectionsController(teamCount: 2, questions: [arsenalJuve()]);
      c.buzz(0);
      c.submit(gallas); // fame 3
      expect(c.roundPoints[0], 3);
      expect(c.outcome!.bonus, isTrue);
    });

    test('answer clock running out counts as wrong', () {
      final c = make();
      c.buzz(0);
      c.advance(secs(c.answerSeconds + 0.1));
      expect(c.lockedOut, {0});
      expect(c.phase, BuzzPhase.open);
    });

    test('open clock running out ends the question with no score', () {
      final c = make();
      c.advance(secs(c.openSeconds + 0.1));
      expect(c.phase, BuzzPhase.resolved);
      expect(c.lastEvent, GameEvent.timeUp);
    });

    test('room-approved disputed answer scores base points', () {
      final c = make();
      c.buzz(1);
      c.submitDisputed(allowed: true);
      expect(c.roundPoints[1], ClubConnectionsController.basePoints);
      expect(c.outcome!.disputed, isTrue);
    });

    test('next() walks through questions then finishes', () {
      final c = make();
      c.giveUp();
      c.next();
      expect(c.questionIndex, 1);
      expect(c.phase, BuzzPhase.open);
      expect(c.lockedOut, isEmpty);
      c.giveUp();
      c.next();
      expect(c.phase, BuzzPhase.finished);
    });
  });

  group('Career Path', () {
    CareerPathController make() => CareerPathController(teamCount: 2, questions: [zlatanPath()]);

    test('starts with one clue worth max points', () {
      final c = make();
      expect(c.revealed, 1);
      expect(c.pointsAvailable, CareerPathController.maxPoints);
    });

    test('clues reveal over time and points drop', () {
      final c = make();
      c.advance(secs(c.revealSeconds + 0.01));
      expect(c.revealed, 2);
      expect(c.pointsAvailable, 4);
      expect(c.lastEvent, GameEvent.reveal);
    });

    test('reveals pause while a team is answering', () {
      final c = make();
      c.buzz(0);
      c.advance(secs(c.revealSeconds * 2));
      expect(c.revealed, 1);
    });

    test('early correct guess scores more than a late one', () {
      final early = make()
        ..buzz(0)
        ..submit(zlatan);
      final late = make();
      for (var i = 0; i < 3; i++) {
        late.advance(secs(late.revealSeconds + 0.01));
      }
      late
        ..buzz(1)
        ..submit(zlatan);
      expect(early.roundPoints[0], 5);
      expect(late.roundPoints[1], 2);
    });

    test('never drops below 1 point', () {
      final c = CareerPathController(teamCount: 2, questions: [zlatanPath()]);
      c.revealed = 20;
      expect(c.pointsAvailable, 1);
    });

    test('times out after the final clue', () {
      final c = make();
      for (var i = 0; i < c.clueCount - 1; i++) {
        c.advance(secs(c.revealSeconds + 0.01));
      }
      expect(c.allRevealed, isTrue);
      c.advance(secs(c.finalSeconds + 0.01));
      expect(c.phase, BuzzPhase.resolved);
    });

    test('wrong player is wrong even with similar fame', () {
      final c = make();
      c.buzz(0);
      c.submit(henry);
      expect(c.lockedOut, {0});
    });
  });
}
