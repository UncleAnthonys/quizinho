import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/games/tic_tac_toe/tic_tac_toe_controller.dart';

Duration secs(double s) => Duration(microseconds: (s * 1e6).round());

Club club(String id) => Club(id: id, name: id, fame: 5);
Player player(String id) => Player(id: id, name: id, fame: 4);

/// Square i accepts only player "p<i>".
TicTacToeGrid grid() => TicTacToeGrid(
      rows: [club('r0'), club('r1'), club('r2')],
      cols: [club('c0'), club('c1'), club('c2')],
      answers: [for (var i = 0; i < 9; i++) {'p$i'}],
    );

void main() {
  group('grid generation', () {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());

    test('every square has a valid answer, all six clubs distinct', () async {
      final conns = await repo.allClubConnections();
      for (var seed = 0; seed < 20; seed++) {
        final g = generateTicTacToeGrid(conns, random: Random(seed), minFame: 4)!;
        expect({...g.rows.map((c) => c.id), ...g.cols.map((c) => c.id)}.length, 6);
        expect(g.answers.every((a) => a.isNotEmpty), isTrue);
      }
    });

    test('works within a narrow era selection', () async {
      final conns = await repo.allClubConnections(eras: Era.tens.bit | Era.twenties.bit);
      expect(generateTicTacToeGrid(conns, random: Random(1), minFame: 4), isNotNull);
    });

    test('avoids grids already played', () async {
      final conns = await repo.allClubConnections();
      final first = generateTicTacToeGrid(conns, random: Random(5))!;
      final second = generateTicTacToeGrid(conns, random: Random(5), avoid: {first.id});
      expect(second?.id, isNot(first.id));
    });
  });

  group('rules', () {
    TicTacToeController make() => TicTacToeController(grid: grid(), teamCount: 2, answerSeconds: 10);

    test('correct answer claims the square and passes the turn', () {
      final c = make()..choose(4);
      expect(c.submit(player('p4')), TttSubmit.claimed);
      expect(c.owner[4], 0);
      expect(c.currentTeam, 1);
      expect(c.canChoose(4), isFalse);
    });

    test('wrong answer or timeout ends the turn without claiming', () {
      final c = make()..choose(0);
      expect(c.submit(player('p8')), TttSubmit.missed);
      expect(c.owner[0], isNull);
      expect(c.currentTeam, 1);
      c.choose(0);
      c.advance(secs(10.1));
      expect(c.owner[0], isNull);
      expect(c.currentTeam, 0);
    });

    test('a player can only be used once per grid', () {
      final g = TicTacToeGrid(
        rows: grid().rows,
        cols: grid().cols,
        answers: [for (var i = 0; i < 9; i++) {'star'}],
      );
      final c = TicTacToeController(grid: g, teamCount: 2)..choose(0);
      c.submit(player('star'));
      c.choose(1);
      expect(c.submit(player('star')), TttSubmit.alreadyUsed);
      expect(c.phase, TttPhase.answering); // no penalty, try again
    });

    test('three in a row wins with a bonus', () {
      final c = make();
      for (final (sq, ok) in [(0, true), (3, true), (1, true), (4, true), (2, true)]) {
        c.choose(sq);
        c.submit(player(ok ? 'p$sq' : 'nobody'));
      }
      expect(c.phase, TttPhase.finished);
      expect(c.winner, 0);
      expect(c.winningLine, [0, 1, 2]);
      expect(c.result().points, {0: 3 + TicTacToeController.lineBonus, 1: 2});
    });

    test('turn limit ends a stalemate', () {
      final c = TicTacToeController(grid: grid(), teamCount: 2, maxTurns: 4);
      for (var i = 0; i < 4; i++) {
        c.choose(0);
        c.pass();
      }
      expect(c.phase, TttPhase.finished);
      expect(c.winner, isNull);
    });

    test('changing square before answering costs nothing', () {
      final c = make()..choose(0);
      c.unchoose();
      expect(c.phase, TttPhase.choosing);
      expect(c.currentTeam, 0);
    });
  });
}
