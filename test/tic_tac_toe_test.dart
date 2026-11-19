import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/domain/tournament.dart';
import 'package:quizinho/games/tic_tac_toe/tic_tac_toe_controller.dart';
import 'package:quizinho/games/tic_tac_toe/tic_tac_toe_screen.dart';

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

    test('grids are varied: no name fits three thin squares, no two squares near-duplicates', () async {
      final conns = [...await repo.allClubConnections(), ...await repo.categoryClubPairs()];
      var made = 0;
      for (var seed = 0; seed < 40; seed++) {
        final g = generateTicTacToeGrid(conns, random: Random(seed), minFame: 4);
        if (g == null) continue;
        made++;
        expect(gridIsVaried(g), isTrue, reason: g.id);
      }
      expect(made, greaterThan(30));
    });

    test('a grid where one player fits three thin squares is rejected', () {
      final thin = TicTacToeGrid(
        rows: [club('r0'), club('r1'), club('r2')],
        cols: [club('c0'), club('c1'), club('c2')],
        answers: [
          for (var i = 0; i < 9; i++) i < 3 ? {'rossi', 'a$i', 'b$i', 'c$i', 'd$i'} : {'x$i'},
        ],
      );
      expect(gridIsVaried(thin), isFalse);
    });

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

    test('categories: right players, never their own clubs, two a grid at most', () async {
      String? nat(String id) => repo.players.byId(id)?.nationality;
      final conns = [...await repo.allClubConnections(), ...await repo.categoryClubPairs()];
      final wales = conns.firstWhere((c) => c.clubA.id == 'nat:WAL' && c.clubB.name == 'Manchester United');
      expect(wales.answerIds, contains('ryan-giggs'));
      expect(wales.answerIds.every((id) => nat(id) == 'WAL'), isTrue);
      expect(conns.any((c) => c.clubA.id == 'nat:ENG' && c.clubB.country == 'GBR'), isFalse);
      final fergie = conns.firstWhere((c) => c.clubA.id == 'mgr:sir-alex-ferguson' && c.clubB.name == 'Everton');
      expect(fergie.clubA.name, 'Managed by Ferguson (club)');
      expect(fergie.answerIds, contains('wayne-rooney'));
      expect(conns.any((c) => c.clubA.id == 'with:lionel-messi' && c.clubB.name == 'Barcelona'), isFalse);
      final kinds = <String, int>{};
      var two = 0;
      for (var seed = 0; seed < 80; seed++) {
        final g = generateTicTacToeGrid(conns, random: Random(seed), minFame: 4)!;
        final cats = [...g.rows, ...g.cols].where(isGridCategory).toList();
        // Every grid has one (teammate, nation, manager or trophy); two at most.
        expect(cats.length, inInclusiveRange(1, 2), reason: 'seed $seed');
        if (cats.length == 2) two++;
        for (final c in cats) {
          kinds.update(c.id.split(':').first, (n) => n + 1, ifAbsent: () => 1);
        }
        expect(g.answers.every((a) => a.isNotEmpty), isTrue);
      }
      // All four sorts come up, managers and trophies included.
      expect(kinds.keys, containsAll(['with', 'nat', 'mgr', 'cup']), reason: '$kinds');
      expect(kinds['cup']!, greaterThanOrEqualTo(8), reason: '$kinds');
      expect(kinds['mgr']!, greaterThanOrEqualTo(8), reason: '$kinds');
      expect(two, greaterThan(10));
    });

    test('categories at every difficulty (the game settings)', () async {
      final conns = [...await repo.allClubConnections(), ...await repo.categoryClubPairs()];
      int fame(String id) => repo.players.byId(id)?.fame ?? 0;
      // (minFame, maxLevel, known answers) as the game uses them: Easy to Expert.
      for (final (name, f, level, known) in [('easy', 5, 1, 3), ('medium', 4, 2, 2), ('hard', 4, 3, 1), ('expert', 2, 4, 0)]) {
        final kinds = <String, int>{};
        var none = 0;
        for (var seed = 0; seed < 40; seed++) {
          final g = generateTicTacToeGrid(conns,
              random: Random(seed), minFame: f, maxLevel: level, minKnownAnswers: known, answerFame: fame)!;
          final cats = [...g.rows, ...g.cols].where(isGridCategory).toList();
          if (cats.isEmpty) none++;
          for (final c in cats) {
            kinds.update(c.id.split(':').first, (n) => n + 1, ifAbsent: () => 1);
          }
        }
        // ignore: avoid_print
        print('grid categories $name: clubs-only $none/40, $kinds');
        expect(none, lessThanOrEqualTo(4), reason: '$name: $kinds');
      }
    });

    test('clubs only when there are no categories to use', () async {
      final g = generateTicTacToeGrid(await repo.allClubConnections(), random: Random(2), minFame: 4)!;
      expect([...g.rows, ...g.cols].where(isGridCategory), isEmpty);
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
        expect(g.rows.where((c) => c.country == 'GBR').length, lessThanOrEqualTo(2));
        expect(g.cols.where((c) => c.country == 'GBR').length, lessThanOrEqualTo(2));
        english += six.where((c) => c.country == 'GBR').length;
        total += 6;
      }
      expect(english / total, greaterThan(0.4));
    });
  });

  test('the board sent to phones has no nulls (the rooms database drops them)', () {
    final t = Tournament(TournamentConfig(teams: [TeamSetup(name: 'A', colorIndex: 0), TeamSetup(name: 'B', colorIndex: 1)]));
    final c = TicTacToeController(grid: grid(), teamCount: 2);
    final snap = TttBoard.snapshot(c, t);
    for (final v in snap.values) {
      if (v is List) expect(v.contains(null), isFalse, reason: '$v');
    }
    expect((snap['owner'] as List).length, 9);
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
      expect(c.livesLeft, [2, 3]);
    });

    test('Pack the Box: scored on squares filled, no line bonus', () {
      final c = TicTacToeController(grid: grid(), teamCount: 1);
      for (final i in [0, 1, 2]) {
        c.choose(i);
        c.submit(player('p$i'));
      }
      expect(c.winner, isNull, reason: 'a line means nothing in solo');
      expect(c.phase, TttPhase.choosing);
      expect(c.result().solo, 33);
      for (var i = 3; i < 9; i++) {
        c.choose(i);
        c.submit(player('p$i'));
      }
      expect(c.result().solo, 100);
    });

    test('Pack the Box: one clock for the whole grid; time left and lives add to the score', () {
      final c = TicTacToeController(grid: grid(), teamCount: 1, chooseSeconds: 5, soloSeconds: 180);
      c.advance(secs(60));
      expect(c.phase, TttPhase.choosing, reason: 'no clock just for picking');
      expect(c.clockRunning, isTrue);
      expect(c.secondsLeft, 120);
      for (var i = 0; i < 9; i++) {
        c.choose(i);
        c.submit(player('p$i'));
      }
      // 63 for the grid, 12 for three lives, 25 x 2/3 for the time left.
      expect(c.result().solo, 92);
      final slow = TicTacToeController(grid: grid(), teamCount: 1, soloSeconds: 180);
      slow.advance(secs(181));
      expect(slow.phase, TttPhase.finished, reason: 'time up ends the grid');
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

    test('a team out of lives sits out; all out ends it', () {
      final c = make(); // 2 teams, 3 lives each
      c.pass(); // team 0: 2 left
      c.choose(0);
      c.submit(player('nobody')); // team 1: 2 left
      c.pass(); // 0: 1
      c.pass(); // 1: 1
      c.pass(); // 0: out
      expect(c.livesLeft, [0, 1]);
      expect(c.currentTeam, 1);
      c.choose(4);
      c.submit(player('p4')); // a square; team 0 is out, so 1 goes again
      expect(c.currentTeam, 1);
      c.pass(); // 1: out
      expect(c.phase, TttPhase.finished);
      expect(c.result().points, {0: 0, 1: 1});
    });

    test('a team can pass without picking a square', () {
      final c = make()..pass();
      expect(c.phase, TttPhase.choosing);
      expect(c.currentTeam, 1);
    });

    test('Pack the Box ends after three lives', () {
      final c = TicTacToeController(grid: grid(), teamCount: 1)..choose(0);
      c.submit(player('nobody'));
      c.pass();
      expect(c.phase, TttPhase.choosing);
      c.pass();
      expect(c.phase, TttPhase.finished);
    });
  });
}
