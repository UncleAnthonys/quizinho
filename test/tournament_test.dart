import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/football_repository.dart';
import 'package:quizinho/data/in_memory_football_repository.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/domain/game_mode.dart';
import 'package:quizinho/domain/tournament.dart';

import 'fixtures.dart';

TournamentConfig config({int teams = 2, Set<GameModeId>? modes, MatchLength length = MatchLength.short}) =>
    TournamentConfig(
      teams: [for (var i = 0; i < teams; i++) TeamSetup(name: 'T$i', colorIndex: i)],
      modes: modes,
      length: length,
    );

void main() {
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

  test('difficulty falls back to any level rather than stalling', () async {
    final repo = InMemoryFootballRepository(players: allPlayers, connections: [arsenalBarca()]); // level 1 only
    final q = await ChallengeSource(repo).clubConnection(Difficulty.expert, {});
    expect(q?.id, arsenalBarca().id);
  });
}
