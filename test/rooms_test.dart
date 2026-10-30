import 'package:flutter_test/flutter_test.dart';
import 'package:quizinho/domain/player_index.dart';
import 'package:quizinho/domain/tournament.dart';
import 'package:quizinho/games/buzz_race_controller.dart';
import 'package:quizinho/games/club_connections/club_connections_controller.dart';
import 'package:quizinho/multiplayer/buzz_bridge.dart';
import 'package:quizinho/multiplayer/memory_room_link.dart';
import 'package:quizinho/multiplayer/room.dart';
import 'package:quizinho/multiplayer/room_link.dart';

import 'fixtures.dart';

Future<void> settle([int ms = 0]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('the shared tree', () {
    test('writes, merges and removes like the database', () {
      Object? t = writeAt(null, ['a', 'b'], 1);
      t = writeAt(t, ['a'], {'c': 2}, merge: true);
      expect(t, {'a': {'b': 1, 'c': 2}});
      t = writeAt(t, ['a', 'b'], null);
      expect(t, {'a': {'c': 2}});
      expect(readAt(t, ['a', 'c']), 2);
      expect(asList({'0': 'x', '1': 'y'}), ['x', 'y']);
    });
  });

  group('a buzzer game across phones', () {
    late MemoryRoomLink link;
    late HostRoom host;
    late GuestRoom ann;
    late GuestRoom bob;
    late ClubConnectionsController game;
    late BuzzBridge bridge;
    late Tournament tournament;
    var clock = 1000;

    setUp(() async {
      link = MemoryRoomLink(clock: () => clock);
      final teams = [
        TeamSetup(name: 'Home', colorIndex: 0, players: ['Ann', 'Al']),
        TeamSetup(name: 'Away', colorIndex: 1, players: ['Bob']),
      ];
      tournament = Tournament(TournamentConfig(teams: teams));
      host = await HostRoom.open(link, teams);
      ann = GuestRoom(link, host.code, 'phone-ann')..start();
      bob = GuestRoom(link, host.code, 'phone-bob')..start();
      await settle();
      await ann.claim(0, 'Ann');
      await bob.claim(1, 'Bob');
      await settle();
      game = ClubConnectionsController(teamCount: 2, questions: [arsenalBarca()]);
      bridge = BuzzBridge(
        room: host,
        controller: game,
        tournament: tournament,
        players: PlayerIndex(const [henry, fabregas, gallas]),
        title: 'CLUB CONNECTIONS',
        prompt: 'Name a player who played for both',
        question: () => {'clubs': [game.current.clubA.name, game.current.clubB.name]},
        answerIds: () => game.current.answerIds,
        reveal: () => ['Thierry Henry'],
        faceOff: () => null,
        paused: () => false,
      )..start();
      await settle();
    });

    tearDown(() {
      bridge.dispose();
      host.dispose();
      ann.dispose();
      bob.dispose();
    });

    test('phones join by name and see the question', () {
      expect(host.members.values.map((m) => m.name), containsAll(['Ann', 'Bob']));
      expect(ann.view['kind'], 'buzz');
      expect(asList(asMap(ann.view['question'])['clubs']), ['Arsenal', 'Barcelona']);
      expect(ann.taken(1, 'Bob'), isTrue);
    });

    test('the earliest buzz by the database clock answers, on their phone', () async {
      clock = 2000;
      await bob.buzz(bridge.questionKey);
      clock = 1500; // Ann buzzed first by the shared clock, even if it arrives second
      await ann.buzz(bridge.questionKey);
      await settle(300);
      expect(game.phase, BuzzPhase.answering);
      expect(game.answeringTeam, 0);
      expect(bridge.remote?.name, 'Ann');
      expect(asMap(ann.view['answering'])['device'], 'phone-ann');

      await ann.answer(bridge.questionKey, 'thierry-henry');
      await settle();
      expect(game.outcome?.scored, isTrue);
      expect(game.outcome?.team, 0);
    });

    test('phones get the clock again when it drifts, so it never sticks', () async {
      final first = (ann.view['left']! as num).toDouble();
      for (var i = 0; i < 20; i++) {
        game.advance(const Duration(milliseconds: 100));
      }
      await settle();
      final now = (ann.view['left']! as num).toDouble();
      expect(now, lessThan(first - 1));
      expect((now - game.secondsLeft).abs(), lessThan(0.6));
    });

    test('only the answering phone can answer', () async {
      await ann.buzz(bridge.questionKey);
      await settle(300);
      await bob.answer(bridge.questionKey, 'thierry-henry');
      await settle();
      expect(game.phase, BuzzPhase.answering);
    });

    test('in a face-off only the two named phones can buzz', () async {
      bridge.dispose();
      game = ClubConnectionsController(teamCount: 2, questions: [arsenalBarca()]);
      bridge = BuzzBridge(
        room: host,
        controller: game,
        tournament: tournament,
        players: PlayerIndex(const [henry]),
        title: 'CLUB CONNECTIONS',
        prompt: '',
        question: () => const {},
        answerIds: () => game.current.answerIds,
        reveal: () => const [],
        faceOff: () => const FaceOff({0: 'Al', 1: 'Bob'}),
        paused: () => false,
      )..start();
      await ann.buzz(bridge.questionKey); // Ann isn't in this face-off
      await settle(300);
      expect(game.phase, BuzzPhase.open);
      await bob.buzz(bridge.questionKey);
      await settle(300);
      expect(game.answeringTeam, 1);
    });
  });
}
