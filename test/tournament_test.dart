import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/football_repository.dart';
import 'package:quizinho/data/in_memory_football_repository.dart';
import 'package:quizinho/data/json_football_repository.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/domain/game_mode.dart';
import 'package:quizinho/domain/tournament.dart';
import 'package:quizinho/domain/warm_up_cup.dart';

import 'fixtures.dart';

TournamentConfig config({int teams = 2, Set<GameModeId>? modes, MatchLength length = MatchLength.short}) =>
    TournamentConfig(
      teams: [for (var i = 0; i < teams; i++) TeamSetup(name: 'T$i', colorIndex: i)],
      modes: modes,
      length: length,
    );

void main() {
  group('face-offs and players', faceOffTests);

  test('round results add up, wildcard doubles', () {
    final t = Tournament(config());
    t.recordRound(RoundResult(mode: GameModeId.careerPath, points: {0: 5, 1: 2}));
    t.recordRound(RoundResult(mode: GameModeId.clubConnections, points: {0: 0, 1: 3}), multiplier: 2);
    expect(t.scores, [5, 8]);
    expect(t.rounds.last.points[1], 6);
    expect(t.standings, [1, 0]);
  });

  test('finishes after the configured number of rounds', () {
    final t = Tournament(config(length: MatchLength.short));
    for (var i = 0; i < MatchLength.short.rounds; i++) {
      expect(t.isFinished, isFalse);
      t.recordRound(RoundResult.empty(GameModeId.careerPath, 2));
    }
    expect(t.isFinished, isTrue);
  });

  test('leaders reports a draw', () {
    final t = Tournament(config(teams: 3));
    t.recordRound(RoundResult(mode: GameModeId.careerPath, points: {0: 4, 1: 4, 2: 1}));
    expect(t.leaders, [0, 1]);
  });

  test('wheel only offers enabled games and never repeats a game back-to-back', () {
    final t = Tournament(
      config(modes: {GameModeId.clubConnections, GameModeId.careerPath}),
      random: Random(1),
    );
    expect(t.wheelSegments, [GameModeId.clubConnections, GameModeId.careerPath]);
    var last = t.spin();
    for (var i = 0; i < 30; i++) {
      final next = t.spin();
      expect(next, isNot(last));
      last = next;
    }
  });

  test('the Warm-Up Cup is three fixed rounds, same order for everyone', () {
    final t = Tournament(config(teams: 3).asWarmUp(), random: Random(7));
    expect(t.totalRounds, 3);
    expect(t.config.difficulty, Difficulty.easy);
    for (final game in WarmUpCup.games) {
      expect(t.spin(), game);
      t.recordRound(RoundResult.empty(game, t.teamCount));
    }
    expect(t.isFinished, isTrue);
  });

  test('every Warm-Up Cup challenge exists in the bundled data', () async {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    for (final id in WarmUpCup.connections) {
      expect((await repo.clubConnectionById(id))?.answerIds.length, greaterThanOrEqualTo(5), reason: id);
    }
    for (final id in WarmUpCup.careers) {
      expect(await repo.careerPathById(id), isNotNull, reason: id);
    }
    expect((await repo.biddingCategoryById(WarmUpCup.bidding))?.answerIds.length, greaterThanOrEqualTo(10));
  });

  test('Warm-Up Cup questions count as seen, so the full game avoids them', () async {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    final source = ChallengeSource(repo);
    await source.fixedConnection(WarmUpCup.connections.first);
    expect(source.history.seen('conn'), contains(WarmUpCup.connections.first));
  });

  test('Heads Up holders: random, but everyone goes once before anyone twice', () {
    final t = Tournament(
      TournamentConfig(teams: [
        TeamSetup(name: 'A', colorIndex: 0, players: ['Ann', 'Bob', 'Cat']),
        TeamSetup(name: 'B', colorIndex: 1),
      ]),
      random: Random(5),
    );
    expect({for (var i = 0; i < 3; i++) t.fairRandomPlayer(0)}, {'Ann', 'Bob', 'Cat'});
    expect(t.fairRandomPlayer(1), isNull);
  });

  test('the first spin is never the wildcard', () {
    for (var seed = 0; seed < 50; seed++) {
      final t = Tournament(config(), random: Random(seed));
      expect(t.spin(), isNot(GameModeId.wildcard));
    }
  });

  test('wildcard resolves to a real enabled game', () {
    final t = Tournament(config(modes: {GameModeId.startingXi, GameModeId.wildcard}), random: Random(3));
    expect(t.wheelSegments, contains(GameModeId.wildcard));
    expect(t.resolveWildcard(), GameModeId.startingXi);
  });

  test('used challenges are not served again within a tournament', () async {
    final repo = InMemoryFootballRepository(
      players: allPlayers,
      connections: [arsenalBarca(), arsenalJuve()],
      random: Random(7),
    );
    final source = ChallengeSource(repo);
    final t = Tournament(config());
    final seen = <String>{};
    for (var i = 0; i < 2; i++) {
      final q = await source.clubConnection(Difficulty.medium, t.usedIds(GameModeId.clubConnections));
      expect(q, isNotNull);
      expect(seen.add(q!.id), isTrue, reason: 'repeated ${q.id}');
      t.markUsed(GameModeId.clubConnections, q.id);
    }
    expect(await source.clubConnection(Difficulty.medium, t.usedIds(GameModeId.clubConnections)), isNull);
  });

  test('difficulty falls back to easier levels rather than stalling', () async {
    final repo = InMemoryFootballRepository(players: allPlayers, connections: [arsenalBarca()]); // level 1 only
    final q = await ChallengeSource(repo).clubConnection(Difficulty.expert, {});
    expect(q?.id, arsenalBarca().id);
  });

  test('never serves anything harder than the chosen difficulty', () async {
    final repo = parseFootballJson(File('assets/db/football.json').readAsStringSync());
    final source = ChallengeSource(repo);
    final used = <String>{};
    for (var i = 0; i < 200; i++) {
      final m = await source.match(Difficulty.medium, used);
      if (m == null) break;
      used.add(m.id);
      expect(m.difficulty, lessThanOrEqualTo(2), reason: m.id);
    }
    for (var i = 0; i < 50; i++) {
      final c = await source.careerPath(Difficulty.easy, {});
      expect(c!.difficulty, 1);
    }
  });
}

TournamentConfig namedConfig() => TournamentConfig(teams: [
      TeamSetup(name: 'Home', colorIndex: 0, players: ['Sam', 'Ali', 'Jo']),
      TeamSetup(name: 'Away', colorIndex: 1, players: ['Kim', 'Raj']),
    ]);

void faceOffTests() {
  test('no names → never a face-off, no turn players', () {
    final t = Tournament(config(), random: Random(1));
    expect(t.hasPlayerNames, isFalse);
    for (var i = 0; i < 20; i++) {
      expect(t.maybeFaceOff(), isNull);
    }
    expect(t.nextTurnPlayer(0), isNull);
  });

  test('face-offs happen sometimes and pick one named player per team', () {
    final t = Tournament(namedConfig(), random: Random(2));
    final rolls = [for (var i = 0; i < 40; i++) t.maybeFaceOff()];
    final faceOffs = rolls.whereType<FaceOff>().toList();
    expect(faceOffs.length, inInclusiveRange(8, 32));
    for (final f in faceOffs) {
      expect(['Sam', 'Ali', 'Jo'], contains(f.nameFor(0)));
      expect(['Kim', 'Raj'], contains(f.nameFor(1)));
    }
  });

  test('face-off picks rotate fairly through each team', () {
    final t = Tournament(namedConfig(), random: Random(3));
    final picked = <String, int>{};
    var n = 0;
    while (n < 6) {
      final f = t.maybeFaceOff();
      if (f == null) continue;
      n++;
      picked.update(f.nameFor(0), (v) => v + 1, ifAbsent: () => 1);
    }
    expect(picked, {'Sam': 2, 'Ali': 2, 'Jo': 2});
  });

  test('turn players cycle in order', () {
    final t = Tournament(namedConfig());
    expect([for (var i = 0; i < 4; i++) t.nextTurnPlayer(1)], ['Kim', 'Raj', 'Kim', 'Raj']);
  });

  test('player table sums credits, best first', () {
    final t = Tournament(namedConfig());
    t.creditPlayer(0, 'Sam', 2);
    t.creditPlayer(1, 'Kim', 3);
    t.creditPlayer(0, 'Sam', 2);
    t.creditPlayer(0, 'Ali', 0); // ignored
    expect([for (final p in t.playerTable) '${p.name}:${p.points}'], ['Sam:4', 'Kim:3']);
  });
}
