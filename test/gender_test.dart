import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/data/in_memory_football_repository.dart';
import 'package:quizinho/data/models.dart';
import 'package:quizinho/domain/game_mode.dart';
import 'package:quizinho/domain/tournament.dart';

const arsenal = Club(id: 'ars', name: 'Arsenal', fame: 5);
const chelsea = Club(id: 'che', name: 'Chelsea', fame: 5);
const arsenalW = Club(id: 'arsw', name: 'Arsenal Women', fame: 5, women: true);
const chelseaW = Club(id: 'chew', name: 'Chelsea Women', fame: 5, women: true);

const men = ClubConnection(id: 'm', clubA: arsenal, clubB: chelsea, answerIds: {'ashley-cole'}, difficulty: 1);
const women = ClubConnection(id: 'w', clubA: arsenalW, clubB: chelseaW, answerIds: {'some-one'}, difficulty: 1);

void main() {
  final repo = InMemoryFootballRepository(
    players: const [Player(id: 'ashley-cole', name: 'Ashley Cole', fame: 4)],
    connections: [men, women],
  );

  test("men's, women's and both pick from the right pool", () async {
    for (var i = 0; i < 20; i++) {
      expect((await repo.pickClubConnection(genders: FootballGender.men.mask))!.id, 'm');
      expect((await repo.pickClubConnection(genders: FootballGender.women.mask))!.id, 'w');
    }
    final both = {for (var i = 0; i < 40; i++) (await repo.pickClubConnection(genders: FootballGender.both.mask))!.id};
    expect(both, {'m', 'w'});
  });

  test('women-only never falls back to a men\'s question', () async {
    expect(await repo.pickClubConnection(genders: FootballGender.women.mask, exclude: {'w'}), isNull);
    expect(await repo.pickMatch(genders: FootballGender.women.mask), isNull);
  });

  test("women's mode leaves out games with no women's questions yet", () {
    final config = TournamentConfig(teams: [TeamSetup(name: 'A', colorIndex: 0), TeamSetup(name: 'B', colorIndex: 1)], gender: FootballGender.women);
    expect(config.enabledGames, isNot(contains(GameModeId.startingXi)));
    expect(config.enabledGames, isNot(contains(GameModeId.headsUp)));
    expect(config.enabledGames, contains(GameModeId.clubConnections));
    final mens = TournamentConfig(teams: [TeamSetup(name: 'A', colorIndex: 0), TeamSetup(name: 'B', colorIndex: 1)]);
    expect(mens.enabledGames, contains(GameModeId.startingXi));
  });
}
