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

    test('easier settings skip obscure-league pairs and need well-known answers', () async {
      final conns = await repo.allClubConnections();
      int fame(String id) => repo.players.byId(id)?.fame ?? 0;
      for (var seed = 0; seed < 10; seed++) {
        final g = generateTicTacToeGrid(conns,
            random: Random(seed), minFame: 4, maxLevel: 2, minKnownAnswers: 2, answerFame: fame)!;
        for (final (i, a) in g.answers.indexed) {
          // Between two English clubs a fame-2 name (Kevin Davies) counts as known.
          final english = g.rows[i ~/ 3].country == 'GBR' && g.cols[i % 3].country == 'GBR';
          expect(a.where((id) => fame(id) >= (english ? 2 : 3)).length, greaterThanOrEqualTo(2));
        }
      }
    });

    test('nation categories: right players, not their own league, two a grid at most', () async {
      String? nat(String id) => repo.players.byId(id)?.nationality;
      final conns = [...await repo.allClubConnections(), ...gridNationPairs(await repo.nationClubPairs())];
      final wales = conns.firstWhere((c) => c.clubA.id == 'nat:WAL' && c.clubB.name == 'Manchester United');
      expect(wales.answerIds, contains('ryan-giggs'));
      expect(wales.answerIds.every((id) => nat(id) == 'WAL'), isTrue);
      expect(conns.any((c) => c.clubA.id == 'nat:ENG' && c.clubB.country == 'GBR'), isFalse);
      var withNation = 0;
      for (var seed = 0; seed < 30; seed++) {
        final g = generateTicTacToeGrid(conns, random: Random(seed), minFame: 4)!;
        final n = [...g.rows, ...g.cols].where(isNationCategory).length;
        expect(n, lessThanOrEqualTo(2));
        if (n > 0) withNation++;
        expect(g.answers.every((a) => a.isNotEmpty), isTrue);
      }
      expect(withNation, greaterThan(0));
    });

    test('grids lean English, with one far-flung club at most', () async {
      final conns = await repo.allClubConnections();
      int fame(String id) => repo.players.byId(id)?.fame ?? 0;
      const europe = {'GBR', 'ESP', 'ITA', 'GER', 'FRA', 'MCO', 'NED', 'POR'};
      var english = 0, total = 0;
      for (var seed = 0; seed < 40; seed++) {
        final g = generateTicTacToeGrid(conns,
            random: Random(seed), minFame: 4, maxLevel: 3, minKnownAnswers: 1, answerFame: fame)!;
        final six = [...g.rows, ...g.cols];
        expect(six.where((c) => !europe.contains(c.country)).length, lessThanOrEqualTo(1));
        english += six.where((c) => c.country == 'GBR').length;
        total += 6;
      }
      expect(english / total, greaterThan(0.5));
    });
  });

  group('rules', () {
    TicTacToeController make() => TicTacToeController(grid: grid(), teamCount: 2, answerSeconds: 10);

    test('correct answer claims the square and passes the turn', () {
      final c = make()..choose(4);
      expect(c.submit(player('p4')), TttSubmit.claimed);
      expect(c.owner[4], 0);
      expect(c.currentTeam, 1);
      expect(c.canChoose(4), isTrue, reason: 'theirs now, so only as a steal');
      expect(c.canSteal(4), isTrue);
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

    test('one steal a game: a different player takes their square, which then locks', () {
      final g = TicTacToeGrid(
        rows: grid().rows,
        cols: grid().cols,
        answers: [for (var i = 0; i < 9; i++) {'p$i', 'q$i'}],
      );
      final c = TicTacToeController(grid: g, teamCount: 2)..choose(0);
      c.submit(player('p0')); // team 0 owns square 0
      expect(c.canSteal(0), isTrue);
      c.choose(0);
      expect(c.stealing, isTrue);
      expect(c.submit(player('p0')), TttSubmit.alreadyUsed);
      expect(c.submit(player('q0')), TttSubmit.claimed);
      expect(c.owner[0], 1);
      expect(c.stealsLeft, [1, 0]);
      expect(c.canSteal(0), isFalse, reason: 'locked once stolen');
      c.choose(4);
      c.submit(player('p4'));
      expect(c.canSteal(4), isFalse, reason: 'team 1 has used its steal');
    });

    test('a missed steal is used up; solo has none', () {
      final c = make()..choose(0);
      c.submit(player('p0'));
      c.choose(0);
      c.submit(player('p8'));
      expect(c.owner[0], 0);
      expect(c.stealsLeft[1], 0);
      expect(TicTacToeController(grid: grid(), teamCount: 1).stealsLeft, [0]);
    });

    test('taking too long to pick a square passes the turn', () {
      final c = TicTacToeController(grid: grid(), teamCount: 2, chooseSeconds: 5);
      c.advance(secs(4));
      expect(c.currentTeam, 0);
      c.advance(secs(1.1));
      expect(c.currentTeam, 1);
      expect(c.phase, TttPhase.choosing);
      expect(c.secondsLeft, 5);
      expect(c.dryTurns, 1);
    });

    test('solo has no clock for picking', () {
      final c = TicTacToeController(grid: grid(), teamCount: 1, chooseSeconds: 5);
      c.advance(secs(60));
      expect(c.phase, TttPhase.choosing);
      expect(c.clockRunning, isFalse);
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

    test('turn limit ends a long game', () {
      final c = TicTacToeController(grid: grid(), teamCount: 2, maxTurns: 4, stallLaps: 99);
      for (var i = 0; i < 4; i++) {
        c.choose(0);
        c.pass();
      }
      expect(c.phase, TttPhase.finished);
      expect(c.winner, isNull);
    });

    test('a team can pass without picking a square', () {
      final c = make()..pass();
      expect(c.phase, TttPhase.choosing);
      expect(c.currentTeam, 1);
    });

    test('two laps with nobody claiming ends it; a claim resets the count', () {
      final c = make(); // 2 teams, stallLaps 2 → 4 dry turns
      c.pass();
      c.choose(0);
      c.submit(player('nobody'));
      c.pass();
      expect(c.turnsUntilStall, 1);
      c.choose(5);
      c.submit(player('p5')); // claim resets
      expect(c.turnsUntilStall, 4);
      for (var i = 0; i < 4; i++) {
        c.pass();
      }
      expect(c.phase, TttPhase.finished);
      expect(c.result().points, {0: 0, 1: 1});
    });
  });
}
